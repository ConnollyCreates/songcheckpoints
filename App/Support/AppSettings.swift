import Foundation

/// How the app tries to turn steering-wheel / headphone Next and Previous presses into checkpoint jumps.
/// This is the thing the first car test decides.
enum TriggerMode: String, CaseIterable, Identifiable {
    /// Register our own remote-command handlers, one song in the queue.
    case remoteHandlers = "A"
    /// Queue many copies of the same song; when iOS skips to the next copy, notice and seek it.
    case cloneQueue = "B"
    /// Both at once. A single car test then shows which one actually fired.
    case both = "AB"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remoteHandlers: return "A: Our button handlers"
        case .cloneQueue: return "B: Clone queue + detect"
        case .both: return "A+B: Both (default)"
        }
    }

    var detail: String {
        switch self {
        case .remoteHandlers:
            return "One song in the queue. Next/Previous should reach our handlers. If iOS handles them instead, the app reloads the song at the right checkpoint."
        case .cloneQueue:
            return "The same song is queued many times. A wheel press makes iOS move to an identical copy; the app notices and seeks it to the checkpoint."
        case .both:
            return "Handlers registered and copies queued. The Test Log shows which path fired: \"REMOTE … handler fired\" or \"DETECT … system skip\"."
        }
    }

    var usesRemoteHandlers: Bool { self != .cloneQueue }
    var usesClones: Bool { self != .remoteHandlers }
}

enum SettingsKey {
    static let triggerMode = "triggerMode"
    static let cloneCount = "cloneCount"
    static let skipInterval = "skipInterval"
    static let reactionOffset = "reactionOffset"
    static let activateAudioSession = "activateAudioSession"
    static let heartbeatsVisible = "heartbeatsVisible"
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static func register() {
        defaults.register(defaults: [
            SettingsKey.triggerMode: TriggerMode.both.rawValue,
            SettingsKey.cloneCount: 40,
            SettingsKey.skipInterval: 15.0,
            SettingsKey.reactionOffset: 0.3,
            SettingsKey.activateAudioSession: false,
            SettingsKey.heartbeatsVisible: false
        ])
    }

    static var triggerMode: TriggerMode {
        TriggerMode(rawValue: defaults.string(forKey: SettingsKey.triggerMode) ?? "") ?? .both
    }

    static var cloneCount: Int {
        min(100, max(2, defaults.integer(forKey: SettingsKey.cloneCount)))
    }

    static var skipInterval: Double {
        let value = defaults.double(forKey: SettingsKey.skipInterval)
        return value > 0 ? value : 15
    }

    static var reactionOffset: Double {
        max(0, defaults.double(forKey: SettingsKey.reactionOffset))
    }

    static var activateAudioSession: Bool {
        defaults.bool(forKey: SettingsKey.activateAudioSession)
    }
}
