import Foundation

/// Tunable rules for how Next / Previous move between checkpoints.
public struct JumpPolicy: Equatable, Sendable {
    /// When a song has no checkpoints, Next skips forward by this many seconds.
    public var skipInterval: Double
    /// A checkpoint closer than this ahead of the playhead counts as "where we already are",
    /// so pressing Next right after a jump moves on to the following checkpoint.
    public var forwardEpsilon: Double
    /// Pressing Previous within this many seconds after a checkpoint goes to the one before it
    /// (same idea as a music player's "restart vs. previous track" rule).
    public var previousGrace: Double
    /// Pressing Previous within this many seconds of the song start (with no checkpoint behind)
    /// asks for the previous song instead of restarting.
    public var restartThreshold: Double
    /// Never seek closer than this to the end of the song.
    public var endPadding: Double

    public init(
        skipInterval: Double = 15,
        forwardEpsilon: Double = 0.25,
        previousGrace: Double = 2.0,
        restartThreshold: Double = 3.0,
        endPadding: Double = 1.0
    ) {
        self.skipInterval = skipInterval
        self.forwardEpsilon = forwardEpsilon
        self.previousGrace = previousGrace
        self.restartThreshold = restartThreshold
        self.endPadding = endPadding
    }

    public static let `default` = JumpPolicy()
}

/// What the player should do in response to a Next / Previous press.
public enum JumpAction: Equatable, Sendable {
    case seek(to: Double)
    case nextSong
    case previousSong
}

/// Pure checkpoint math. No player or UI dependencies, so it is fully unit-testable.
public enum JumpEngine {
    /// Checkpoints closer together than this are treated as duplicates.
    public static let duplicateTolerance: Double = 0.05

    /// Sorts, removes invalid values and near-duplicates, and drops checkpoints past the end of the song.
    public static func normalize(_ checkpoints: [Double], duration: Double? = nil) -> [Double] {
        let valid = checkpoints
            .filter { $0.isFinite && $0 >= 0 }
            .filter { time in
                guard let duration, duration.isFinite, duration > 0 else { return true }
                return time < duration
            }
            .sorted()
        var result: [Double] = []
        for time in valid {
            if let last = result.last, time - last < duplicateTolerance { continue }
            result.append(time)
        }
        return result
    }

    /// Decide what Next does from `position`.
    /// - No checkpoints: skip forward `skipInterval` (or go to the next song if that would pass the end).
    /// - Otherwise: jump to the first checkpoint meaningfully ahead, or the next song if none remain.
    public static func next(
        from position: Double,
        checkpoints: [Double],
        duration: Double?,
        policy: JumpPolicy = .default
    ) -> JumpAction {
        let position = sanitize(position)
        let points = normalize(checkpoints, duration: duration)

        if points.isEmpty {
            let target = position + policy.skipInterval
            if let duration, duration.isFinite, duration > 0, target > duration - policy.endPadding {
                return .nextSong
            }
            return .seek(to: target)
        }

        if let target = points.first(where: { $0 > position + policy.forwardEpsilon }) {
            return .seek(to: target)
        }
        return .nextSong
    }

    /// Decide what Previous does from `position`.
    /// - Goes to the latest checkpoint at least `previousGrace` behind the playhead.
    /// - With no such checkpoint: restart the song, or ask for the previous song if we're already near the start.
    public static func previous(
        from position: Double,
        checkpoints: [Double],
        policy: JumpPolicy = .default
    ) -> JumpAction {
        let position = sanitize(position)
        let points = normalize(checkpoints)

        if let target = points.last(where: { $0 <= position - policy.previousGrace }) {
            return .seek(to: target)
        }
        if position < policy.restartThreshold {
            return .previousSong
        }
        return .seek(to: 0)
    }

    private static func sanitize(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }
}

/// Helpers for creating and editing checkpoints.
public enum CheckpointMath {
    /// People tap "Drop Checkpoint" slightly after they hear the moment; shift the time back to compensate.
    public static func dropTime(at position: Double, reactionOffset: Double, duration: Double?) -> Double {
        clamp(position - reactionOffset, duration: duration)
    }

    /// Nudge a checkpoint by `delta` seconds, keeping it inside the song.
    public static func nudge(_ time: Double, by delta: Double, duration: Double?) -> Double {
        clamp(time + delta, duration: duration)
    }

    /// Keeps a time inside [0, duration - 0.5] and rounds to 0.01s so stored values stay tidy.
    public static func clamp(_ time: Double, duration: Double?) -> Double {
        var value = time.isFinite ? time : 0
        if let duration, duration.isFinite, duration > 0.5 {
            value = min(value, duration - 0.5)
        }
        value = max(0, value)
        return (value * 100).rounded() / 100
    }
}
