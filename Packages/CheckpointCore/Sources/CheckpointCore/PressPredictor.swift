import Foundation

/// Handles rapid-fire presses.
///
/// A seek takes a moment to land, so the player's reported position is stale right after a jump.
/// If a second press arrives in that gap and we compute from the stale position, we jump to the
/// same checkpoint twice. Instead, for `window` seconds after a jump we predict the playhead as
/// "where we jumped to, plus the time that has passed since".
public struct PressPredictor: Sendable {
    public var window: Double
    public private(set) var lastTarget: Double?
    public private(set) var lastJumpTime: Double?

    public init(window: Double = 1.5) {
        self.window = window
    }

    /// The position to use for the next decision. `now` is any monotonic clock in seconds.
    public func effectivePosition(reported: Double, now: Double) -> Double {
        guard let lastTarget, let lastJumpTime else { return reported }
        let elapsed = now - lastJumpTime
        guard elapsed >= 0, elapsed <= window else { return reported }
        return lastTarget + elapsed
    }

    public mutating func recordJump(to target: Double, at now: Double) {
        lastTarget = target
        lastJumpTime = now
    }

    public mutating func reset() {
        lastTarget = nil
        lastJumpTime = nil
    }
}
