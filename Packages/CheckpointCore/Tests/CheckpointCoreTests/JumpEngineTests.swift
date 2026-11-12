import XCTest
@testable import CheckpointCore

final class JumpEngineTests: XCTestCase {
    let points: [Double] = [30, 60, 90]

    // MARK: normalize

    func testNormalizeSortsDedupesAndDropsInvalid() {
        let result = JumpEngine.normalize([90, 30, -1, .nan, 30.02, 60, .infinity, 250], duration: 200)
        XCTAssertEqual(result, [30, 60, 90])
    }

    func testNormalizeKeepsCheckpointsHalfASecondApart() {
        XCTAssertEqual(JumpEngine.normalize([10, 10.5, 10.9]), [10, 10.5, 10.9])
    }

    // MARK: next

    func testNextWithZeroCheckpointsSkipsInterval() {
        XCTAssertEqual(JumpEngine.next(from: 10, checkpoints: [], duration: 200), .seek(to: 25))
    }

    func testNextWithZeroCheckpointsNearEndGoesToNextSong() {
        XCTAssertEqual(JumpEngine.next(from: 190, checkpoints: [], duration: 200), .nextSong)
    }

    func testNextWithZeroCheckpointsUnknownDurationStillSkips() {
        XCTAssertEqual(JumpEngine.next(from: 190, checkpoints: [], duration: nil), .seek(to: 205))
    }

    func testNextJumpsToFirstCheckpointAhead() {
        XCTAssertEqual(JumpEngine.next(from: 0, checkpoints: points, duration: 200), .seek(to: 30))
        XCTAssertEqual(JumpEngine.next(from: 45, checkpoints: points, duration: 200), .seek(to: 60))
    }

    func testNextRightAfterAJumpMovesToFollowingCheckpoint() {
        // We just landed on 60 and the player reports 60.1.
        XCTAssertEqual(JumpEngine.next(from: 60.1, checkpoints: points, duration: 200), .seek(to: 90))
    }

    func testNextPastFinalCheckpointGoesToNextSong() {
        XCTAssertEqual(JumpEngine.next(from: 95, checkpoints: points, duration: 200), .nextSong)
    }

    func testNextWithCheckpointsWithinOneSecondVisitsEach() {
        let close: [Double] = [30, 30.5, 31]
        XCTAssertEqual(JumpEngine.next(from: 29, checkpoints: close, duration: 200), .seek(to: 30))
        XCTAssertEqual(JumpEngine.next(from: 30, checkpoints: close, duration: 200), .seek(to: 30.5))
        XCTAssertEqual(JumpEngine.next(from: 30.5, checkpoints: close, duration: 200), .seek(to: 31))
        XCTAssertEqual(JumpEngine.next(from: 31, checkpoints: close, duration: 200), .nextSong)
    }

    func testNextIgnoresCheckpointsBeyondDuration() {
        XCTAssertEqual(JumpEngine.next(from: 95, checkpoints: [30, 60, 90, 300], duration: 200), .nextSong)
    }

    func testNextHandlesGarbagePosition() {
        XCTAssertEqual(JumpEngine.next(from: .nan, checkpoints: points, duration: 200), .seek(to: 30))
        XCTAssertEqual(JumpEngine.next(from: -5, checkpoints: points, duration: 200), .seek(to: 30))
    }

    // MARK: previous

    func testPreviousGoesToCheckpointBehind() {
        XCTAssertEqual(JumpEngine.previous(from: 75, checkpoints: points), .seek(to: 60))
    }

    func testPreviousJustAfterCheckpointGoesToTheOneBefore() {
        XCTAssertEqual(JumpEngine.previous(from: 61, checkpoints: points), .seek(to: 30))
    }

    func testPreviousBeforeFirstCheckpointRestartsSong() {
        XCTAssertEqual(JumpEngine.previous(from: 20, checkpoints: points), .seek(to: 0))
        XCTAssertEqual(JumpEngine.previous(from: 31, checkpoints: points), .seek(to: 0))
    }

    func testPreviousNearSongStartAsksForPreviousSong() {
        XCTAssertEqual(JumpEngine.previous(from: 1, checkpoints: points), .previousSong)
        XCTAssertEqual(JumpEngine.previous(from: 1, checkpoints: []), .previousSong)
    }

    func testPreviousWithZeroCheckpointsRestarts() {
        XCTAssertEqual(JumpEngine.previous(from: 50, checkpoints: []), .seek(to: 0))
    }

    // MARK: rapid fire (engine + predictor together)

    func testRapidDoubleNextVisitsTwoCheckpoints() {
        var predictor = PressPredictor()
        let reported = 10.0 // the player still reports the old position for both presses

        let first = JumpEngine.next(
            from: predictor.effectivePosition(reported: reported, now: 100.0),
            checkpoints: points, duration: 200)
        XCTAssertEqual(first, .seek(to: 30))
        predictor.recordJump(to: 30, at: 100.0)

        let second = JumpEngine.next(
            from: predictor.effectivePosition(reported: reported, now: 100.3),
            checkpoints: points, duration: 200)
        XCTAssertEqual(second, .seek(to: 60))
    }

    func testRapidDoublePreviousVisitsTwoCheckpoints() {
        var predictor = PressPredictor()
        let reported = 95.0

        let first = JumpEngine.previous(
            from: predictor.effectivePosition(reported: reported, now: 50.0), checkpoints: points)
        XCTAssertEqual(first, .seek(to: 90))
        predictor.recordJump(to: 90, at: 50.0)

        let second = JumpEngine.previous(
            from: predictor.effectivePosition(reported: reported, now: 50.4), checkpoints: points)
        XCTAssertEqual(second, .seek(to: 60))
    }

    // MARK: CheckpointMath

    func testDropTimeCompensatesForReaction() {
        XCTAssertEqual(CheckpointMath.dropTime(at: 61.234, reactionOffset: 0.3, duration: 200), 60.93)
        XCTAssertEqual(CheckpointMath.dropTime(at: 0.1, reactionOffset: 0.3, duration: 200), 0)
    }

    func testNudgeClampsInsideSong() {
        XCTAssertEqual(CheckpointMath.nudge(10, by: 0.1, duration: 200), 10.1)
        XCTAssertEqual(CheckpointMath.nudge(0.05, by: -1, duration: 200), 0)
        XCTAssertEqual(CheckpointMath.nudge(199.8, by: 1, duration: 200), 199.5)
    }
}
