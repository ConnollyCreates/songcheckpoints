import Foundation
import Combine
import MediaPlayer
import AVFoundation
import UIKit
import CheckpointCore

/// Where a Next / Previous request came from. Logged on every jump so the car test shows which path works.
enum TriggerSource: String {
    case remoteCommand = "our wheel/remote handler (A)"
    case systemDetected = "system skip, detected (B)"
    case siri = "Siri / Shortcut"
    case app = "in-app button"
}

/// Owns playback through Apple's application queue player (plays Library songs, no paid MusicKit service needed),
/// turns button presses into checkpoint jumps, and records what happened for the test log.
@MainActor
final class PlayerService: ObservableObject {
    static let shared = PlayerService()

    let player: MPMusicPlayerApplicationController = MPMusicPlayerController.applicationQueuePlayer

    @Published private(set) var session: [MPMediaItem] = []
    @Published private(set) var sessionIndex = 0
    @Published private(set) var currentTrack: TrackRecord?
    @Published private(set) var checkpointRecords: [CheckpointRecord] = []
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var lastAction = "Nothing yet"
    @Published private(set) var activeMode: TriggerMode = .both

    var currentItem: MPMediaItem? {
        session.indices.contains(sessionIndex) ? session[sessionIndex] : nil
    }

    /// Always read fresh from the database so edits apply to the very next press.
    var checkpointTimes: [Double] {
        (currentTrack?.checkpoints ?? []).map { $0.time }
    }

    private let diag = DiagnosticsLog.shared
    private var started = false
    private var detector = SkipDetector()
    private var predictor = PressPredictor()
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var queueLength = 0
    private var loadGeneration = 0
    private var finishedGeneration = -1
    private var lastLoadUsedStoreIDs = false
    /// True between replacing the queue and starting playback; detection is paused so a slow load isn't read as a button press.
    private var isLoading = false
    private var lastHeartbeatWallClock: Date?

    private init() {}

    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var policy: JumpPolicy { JumpPolicy(skipInterval: AppSettings.skipInterval) }
    private var knownDuration: Double? { duration > 0 ? duration : nil }

    // MARK: - Lifecycle

    func ensureStarted() {
        guard !started else { return }
        started = true
        player.repeatMode = MPMusicRepeatMode.none
        player.shuffleMode = MPMusicShuffleMode.off
        player.beginGeneratingPlaybackNotifications()
        observeNotifications()
        startTimers()
        diag.log("APP", "Launched. iOS \(UIDevice.current.systemVersion), \(DeviceInfo.model), library access \(LibraryAccess.statusLabel)")
        applyTriggerMode(reloadSong: false)
    }

    /// Re-reads settings, swaps handlers, and optionally reloads the current song so a new mode takes effect.
    func applyTriggerMode(reloadSong: Bool) {
        let mode = AppSettings.triggerMode
        activeMode = mode
        removeRemoteTargets()
        if mode.usesRemoteHandlers { registerRemoteTargets() }
        configureAudioSession()
        let copies = mode.usesClones ? AppSettings.cloneCount : 1
        diag.log("MODE", "\(mode.title). Queue copies per song: \(copies). Audio session activation: \(AppSettings.activateAudioSession ? "on" : "off")")
        if reloadSong, currentItem != nil {
            loadCurrentSong(startAt: currentPositionForDecision())
        }
    }

    // MARK: - Session

    func play(items: [MPMediaItem], startAt index: Int = 0) {
        guard !items.isEmpty else { return }
        session = items
        sessionIndex = min(max(index, 0), items.count - 1)
        diag.log("QUEUE", "New session: \(items.count) song(s), starting at #\(sessionIndex + 1)")
        loadCurrentSong(startAt: 0)
    }

    func togglePlayPause() {
        if player.playbackState == .playing {
            player.pause()
        } else if currentItem != nil {
            if player.indexOfNowPlayingItem == NSNotFound {
                loadCurrentSong(startAt: 0)
            } else {
                player.play()
            }
        }
    }

    func skipSong(by delta: Int) {
        advanceSong(by: delta, reason: "in-app song button")
    }

    // MARK: - Checkpoint actions

    func nextCheckpoint(source: TriggerSource) {
        performNext(from: currentPositionForDecision(), source: source)
    }

    func previousCheckpoint(source: TriggerSource) {
        performPrevious(from: currentPositionForDecision(), source: source)
    }

    @discardableResult
    func dropCheckpoint(source: TriggerSource) -> CheckpointRecord? {
        guard let item = currentItem else {
            diag.log("EDIT", "Drop ignored: nothing loaded")
            return nil
        }
        let track = currentTrack ?? CheckpointStore.ensureTrack(for: item)
        currentTrack = track
        let time = CheckpointMath.dropTime(
            at: currentPositionForDecision(),
            reactionOffset: AppSettings.reactionOffset,
            duration: knownDuration
        )
        let checkpoint = CheckpointStore.addCheckpoint(time: time, to: track)
        reloadCheckpoints()
        lastAction = "Dropped checkpoint at \(fmt(time))"
        diag.log("EDIT", "Dropped checkpoint at \(fmt(time)) via \(source.rawValue)")
        return checkpoint
    }

    /// Plays from slightly before `time` so you can hear whether a checkpoint lands on the beat.
    func preview(at time: Double, leadIn: Double = 2) {
        guard currentItem != nil else { return }
        seek(to: max(0, time - leadIn))
        if player.playbackState != .playing { player.play() }
    }

    func reloadCheckpoints() {
        checkpointRecords = currentTrack?.sortedCheckpoints ?? []
    }

    // MARK: - Jump logic

    private func performNext(from reported: Double, source: TriggerSource) {
        guard currentItem != nil else {
            diag.log("JUMP", "NEXT via \(source.rawValue) ignored: nothing loaded")
            return
        }
        let time = now
        let effective = predictor.effectivePosition(reported: reported, now: time)
        let action = JumpEngine.next(from: effective, checkpoints: checkpointTimes, duration: knownDuration, policy: policy)
        let summary = "NEXT via \(source.rawValue): \(fmt(effective)) → \(describe(action))"
        diag.log("JUMP", summary)
        lastAction = summary
        apply(action, at: time)
    }

    private func performPrevious(from reported: Double, source: TriggerSource) {
        guard currentItem != nil else {
            diag.log("JUMP", "PREVIOUS via \(source.rawValue) ignored: nothing loaded")
            return
        }
        let time = now
        let effective = predictor.effectivePosition(reported: reported, now: time)
        let action = JumpEngine.previous(from: effective, checkpoints: checkpointTimes, policy: policy)
        let summary = "PREVIOUS via \(source.rawValue): \(fmt(effective)) → \(describe(action))"
        diag.log("JUMP", summary)
        lastAction = summary
        apply(action, at: time)
    }

    private func apply(_ action: JumpAction, at time: Double) {
        switch action {
        case .seek(let target):
            predictor.recordJump(to: target, at: time)
            seek(to: target)
        case .nextSong:
            advanceSong(by: 1, reason: "past the last checkpoint")
        case .previousSong:
            advanceSong(by: -1, reason: "previous at song start")
        }
    }

    private func seek(to target: Double) {
        let index = player.indexOfNowPlayingItem
        if index == NSNotFound {
            // iOS ended our queue (e.g. it skipped past a one-song queue). Reload at the target.
            diag.log("JUMP", "Queue had ended; reloading song at \(fmt(target))")
            loadCurrentSong(startAt: target)
            return
        }
        if queueLength > 1, queueLength - index <= 3 {
            diag.log("JUMP", "Running out of queued copies; reloading at \(fmt(target))")
            loadCurrentSong(startAt: target)
            return
        }
        noteAppAction()
        player.currentPlaybackTime = target
    }

    private func advanceSong(by delta: Int, reason: String) {
        let newIndex = sessionIndex + delta
        guard session.indices.contains(newIndex) else {
            if delta < 0 {
                seek(to: 0)
            } else {
                noteAppAction()
                player.stop()
                diag.log("QUEUE", "End of session (\(reason)). Stopped.")
            }
            return
        }
        sessionIndex = newIndex
        diag.log("QUEUE", "\(delta > 0 ? "Next" : "Previous") song (\(reason))")
        loadCurrentSong(startAt: 0)
    }

    private func currentPositionForDecision() -> Double {
        let raw = player.currentPlaybackTime
        return raw.isFinite ? raw : position
    }

    private func noteAppAction() {
        detector.noteAppAction(at: now)
    }

    // MARK: - Queue loading

    private func loadCurrentSong(startAt startTime: Double, useStoreIDs: Bool = false) {
        guard let item = currentItem else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let copies = activeMode.usesClones ? AppSettings.cloneCount : 1

        isLoading = true
        noteAppAction()
        detector.reset()
        predictor.reset()

        if useStoreIDs {
            player.setQueue(with: Array(repeating: item.playbackStoreID, count: copies))
        } else {
            player.setQueue(with: MPMediaItemCollection(items: Array(repeating: item, count: copies)))
        }
        lastLoadUsedStoreIDs = useStoreIDs
        queueLength = copies
        duration = item.playbackDuration
        currentTrack = CheckpointStore.ensureTrack(for: item)
        reloadCheckpoints()

        diag.log("QUEUE", "Loading \"\(item.title ?? "Unknown")\" ×\(copies)\(useStoreIDs ? " (store IDs)" : ""), start \(fmt(startTime)), \(checkpointRecords.count) checkpoint(s)")

        player.prepareToPlay { [weak self] error in
            let message = error?.localizedDescription
            let service = self
            Task { @MainActor in
                service?.finishLoad(generation: generation, startTime: startTime, note: message.map { "prepareToPlay error: \($0)" })
            }
        }
        // prepareToPlay sometimes never calls back; don't let that strand playback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                self?.finishLoad(generation: generation, startTime: startTime, note: "prepareToPlay timed out after 3s")
            }
        }
    }

    private func finishLoad(generation: Int, startTime: Double, note: String?) {
        guard generation == loadGeneration, finishedGeneration < generation else { return }
        finishedGeneration = generation
        isLoading = false
        detector.reset()
        if let note { diag.log("QUEUE", note) }
        noteAppAction()
        if startTime > 0.5 { player.currentPlaybackTime = startTime }
        player.play()
        if queueLength > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.verifyQueue(generation: generation) }
            }
        }
    }

    /// Checks that iOS really kept all the copies (some versions may collapse duplicates).
    private func verifyQueue(generation: Int) {
        guard generation == loadGeneration else { return }
        let expected = queueLength
        player.perform(queueTransaction: { _ in }, completionHandler: { [weak self] queue, error in
            let count = queue.items.count
            let message = error?.localizedDescription
            let service = self
            Task { @MainActor in
                service?.queueVerified(generation: generation, expected: expected, count: count, error: message)
            }
        })
    }

    private func queueVerified(generation: Int, expected: Int, count: Int, error: String?) {
        guard generation == loadGeneration else { return }
        if let error {
            diag.log("QUEUE", "Queue check failed: \(error)")
            return
        }
        diag.log("QUEUE", "iOS reports \(count) queued entr\(count == 1 ? "y" : "ies") (asked for \(expected))")
        guard count < expected else { return }
        queueLength = max(1, count)
        if count <= 1, !lastLoadUsedStoreIDs, let item = currentItem, LibraryAccess.isUsableStoreID(item.playbackStoreID) {
            diag.log("QUEUE", "Copies were collapsed; retrying with Apple Music store IDs")
            loadCurrentSong(startAt: currentPositionForDecision(), useStoreIDs: true)
        } else if count <= 1 {
            diag.log("QUEUE", "⚠️ This iPhone won't queue duplicate copies, so mode B can't work here")
        }
    }

    // MARK: - Polling & detection

    private func startTimers() {
        let poll = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let heartbeat = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat() }
        }
        RunLoop.main.add(poll, forMode: .common)
        RunLoop.main.add(heartbeat, forMode: .common)
        timers = [poll, heartbeat]
    }

    private func tick() {
        let index = player.indexOfNowPlayingItem
        let entry: Int? = index == NSNotFound ? nil : index
        let raw = player.currentPlaybackTime
        let reported: Double? = raw.isFinite ? raw : nil

        position = reported ?? 0
        isPlaying = player.playbackState == .playing
        if let item = currentItem, item.playbackDuration > 0 { duration = item.playbackDuration }

        guard !session.isEmpty, !isLoading else { return }
        let sample = PlayerSample(time: now, entryIndex: entry, position: reported, duration: knownDuration)
        guard let event = detector.ingest(sample) else { return }

        switch event {
        case .systemNext(let from):
            diag.log("DETECT", "System skip NEXT at \(fmt(from)) (iOS handled the button) → now entry \(entry.map(String.init) ?? "none")")
            performNext(from: from, source: .systemDetected)
        case .systemPrevious(let from):
            diag.log("DETECT", "System PREVIOUS/restart from \(fmt(from)) (iOS handled the button)")
            performPrevious(from: from, source: .systemDetected)
        case .naturalEnd:
            diag.log("DETECT", "Song ended naturally")
            advanceSong(by: 1, reason: "song ended")
        }
    }

    private func heartbeat() {
        let wallClock = Date()
        if let last = lastHeartbeatWallClock, wallClock.timeIntervalSince(last) > 15 {
            diag.log("HEART", "⚠️ No heartbeat for \(Int(wallClock.timeIntervalSince(last)))s: the app was suspended")
        }
        lastHeartbeatWallClock = wallClock
        let remaining = UIApplication.shared.backgroundTimeRemaining
        let remainingText = remaining > 100_000 ? "unlimited" : "\(Int(remaining))s"
        let index = player.indexOfNowPlayingItem
        diag.log("HEART", "pos \(fmt(position)) entry \(index == NSNotFound ? "none" : String(index)) \(stateName(player.playbackState)) bgTime \(remainingText)")
    }

    // MARK: - Remote commands (mode A)

    private func registerRemoteTargets() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()

        addTarget(center.nextTrackCommand, name: "nextTrack") { [weak self] _ in
            self?.nextCheckpoint(source: .remoteCommand)
            return .success
        }
        addTarget(center.previousTrackCommand, name: "previousTrack") { [weak self] _ in
            self?.previousCheckpoint(source: .remoteCommand)
            return .success
        }
        addTarget(center.seekForwardCommand, name: "seekForward") { [weak self] event in
            if let seek = event as? MPSeekCommandEvent, seek.type == .beginSeeking {
                self?.nextCheckpoint(source: .remoteCommand)
            }
            return .success
        }
        addTarget(center.seekBackwardCommand, name: "seekBackward") { [weak self] event in
            if let seek = event as? MPSeekCommandEvent, seek.type == .beginSeeking {
                self?.previousCheckpoint(source: .remoteCommand)
            }
            return .success
        }
        addTarget(center.playCommand, name: "play") { [weak self] _ in
            self?.player.play()
            return .success
        }
        addTarget(center.pauseCommand, name: "pause") { [weak self] _ in
            self?.player.pause()
            return .success
        }
        addTarget(center.togglePlayPauseCommand, name: "togglePlayPause") { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }

    private func addTarget(
        _ command: MPRemoteCommand,
        name: String,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let token = command.addTarget { event in
            MainActor.assumeIsolated {
                DiagnosticsLog.shared.log("REMOTE", "✅ \(name) handler fired (our code received the button)")
                return handler(event)
            }
        }
        remoteTargets.append((command: command, token: token))
    }

    private func removeRemoteTargets() {
        for target in remoteTargets {
            target.command.removeTarget(target.token)
        }
        remoteTargets.removeAll()
    }

    private func configureAudioSession() {
        guard AppSettings.activateAudioSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            diag.log("AUDIO", "Audio session active (.playback)")
        } catch {
            diag.log("AUDIO", "Audio session error: \(error.localizedDescription)")
        }
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let index = self.player.indexOfNowPlayingItem
                self.diag.log("PLAYER", "Now-playing entry changed → \(index == NSNotFound ? "none" : String(index))")
                self.tick()
            }
        })

        observers.append(center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.diag.log("PLAYER", "Playback state → \(self.stateName(self.player.playbackState))")
                self.tick()
            }
        })

        let lifecycle: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "Entered background"),
            (UIApplication.willEnterForegroundNotification, "Returning to foreground"),
            (UIApplication.willTerminateNotification, "Terminating"),
            (UIApplication.didReceiveMemoryWarningNotification, "Memory warning")
        ]
        for (name, text) in lifecycle {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DiagnosticsLog.shared.log("APP", text) }
            })
        }

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let text: String
            switch type {
            case .some(.began): text = "began (Siri, call, or another app)"
            case .some(.ended): text = "ended"
            default: text = "unknown"
            }
            MainActor.assumeIsolated { DiagnosticsLog.shared.log("AUDIO", "Interruption \(text)") }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
                .map { "\($0.portType.rawValue) \"\($0.portName)\"" }
                .joined(separator: ", ")
            MainActor.assumeIsolated {
                DiagnosticsLog.shared.log("AUDIO", "Route changed (reason \(rawReason)) → \(outputs.isEmpty ? "no output" : outputs)")
            }
        })
    }

    // MARK: - Formatting

    private func fmt(_ seconds: Double) -> String {
        TimeFormat.string(seconds)
    }

    private func describe(_ action: JumpAction) -> String {
        switch action {
        case .seek(let target): return "seek \(fmt(target))"
        case .nextSong: return "next song"
        case .previousSong: return "previous song"
        }
    }

    func stateName(_ state: MPMusicPlaybackState) -> String {
        switch state {
        case .stopped: return "stopped"
        case .playing: return "playing"
        case .paused: return "paused"
        case .interrupted: return "interrupted"
        case .seekingForward: return "seekingForward"
        case .seekingBackward: return "seekingBackward"
        @unknown default: return "unknown"
        }
    }
}
