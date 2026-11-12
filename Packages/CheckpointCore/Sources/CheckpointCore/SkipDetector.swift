import Foundation

/// One snapshot of the system player, taken by polling or on a player notification.
public struct PlayerSample: Equatable, Sendable {
    /// Monotonic clock, seconds.
    public var time: Double
    /// Index of the current queue entry, or nil when nothing is loaded / the queue has ended.
    public var entryIndex: Int?
    /// Playhead in seconds, or nil when unknown.
    public var position: Double?
    /// Duration of the current song in seconds, if known.
    public var duration: Double?

    public init(time: Double, entryIndex: Int?, position: Double?, duration: Double?) {
        self.time = time
        self.entryIndex = entryIndex
        self.position = position
        self.duration = duration
    }
}

/// Something the system player did on its own: usually because the user pressed a
/// steering-wheel / headphone / lock-screen button and iOS handled it instead of our app.
public enum SkipEvent: Equatable, Sendable {
    /// The system moved to the next queue entry before the song ended (a "Next" press).
    case systemNext(fromPosition: Double)
    /// The system restarted the entry or moved back an entry (a "Previous" press).
    case systemPrevious(fromPosition: Double)
    /// The song played to its end.
    case naturalEnd
}

/// Works out which button the user pressed when iOS, not our app, handled it.
///
/// Used with the "clone queue": the same song is queued many times in a row, so a system
/// Next press lands on an identical copy at 0:00. We see the entry index change, read the
/// position we were at just before, and seek the copy to the right checkpoint.
public struct SkipDetector: Sendable {
    /// Within this many seconds of the end, an entry change counts as the song finishing naturally.
    public var endTolerance: Double
    /// After a system "restart", the playhead is below this.
    public var restartFloor: Double
    /// ...and before it, the playhead was above this.
    public var restartMinimum: Double
    /// Ignore changes for this long after the app itself seeks or loads a queue.
    public var suppressWindow: Double

    public private(set) var lastSample: PlayerSample?
    private var suppressedUntil: Double = -Double.infinity

    public init(
        endTolerance: Double = 2.0,
        restartFloor: Double = 1.5,
        restartMinimum: Double = 3.0,
        suppressWindow: Double = 1.0
    ) {
        self.endTolerance = endTolerance
        self.restartFloor = restartFloor
        self.restartMinimum = restartMinimum
        self.suppressWindow = suppressWindow
    }

    /// Call whenever the app seeks or replaces the queue, so our own changes aren't mistaken for button presses.
    public mutating func noteAppAction(at time: Double) {
        suppressedUntil = max(suppressedUntil, time + suppressWindow)
    }

    public mutating func reset() {
        lastSample = nil
    }

    /// Feed a new sample; returns an event if the system changed playback on its own.
    public mutating func ingest(_ sample: PlayerSample) -> SkipEvent? {
        defer { lastSample = sample }
        guard let previous = lastSample else { return nil }
        if sample.time < suppressedUntil { return nil }

        let previousPosition = previous.position ?? 0
        let wasNearEnd: Bool = {
            guard let duration = previous.duration, duration.isFinite, duration > 0 else { return false }
            return previousPosition >= duration - endTolerance
        }()

        switch (previous.entryIndex, sample.entryIndex) {
        case let (before?, after?) where after > before:
            return wasNearEnd ? .naturalEnd : .systemNext(fromPosition: previousPosition)

        case let (before?, after?) where after < before:
            return .systemPrevious(fromPosition: previousPosition)

        case (.some, nil):
            // The queue ran out. With a one-song queue, a system Next press ends playback too.
            return wasNearEnd ? .naturalEnd : .systemNext(fromPosition: previousPosition)

        case let (before?, after?) where after == before:
            if let now = sample.position, let then = previous.position,
               then >= restartMinimum, now <= restartFloor {
                return .systemPrevious(fromPosition: then)
            }
            return nil

        default:
            return nil
        }
    }
}
