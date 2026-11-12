import XCTest
@testable import CheckpointCore

final class PressPredictorTests: XCTestCase {
    func testWithoutAJumpUsesReportedPosition() {
        let predictor = PressPredictor()
        XCTAssertEqual(predictor.effectivePosition(reported: 42, now: 10), 42)
    }

    func testInsideWindowPredictsFromLastTarget() {
        var predictor = PressPredictor(window: 1.5)
        predictor.recordJump(to: 60, at: 10)
        XCTAssertEqual(predictor.effectivePosition(reported: 20, now: 10.5), 60.5, accuracy: 0.0001)
    }

    func testAfterWindowTrustsPlayerAgain() {
        var predictor = PressPredictor(window: 1.5)
        predictor.recordJump(to: 60, at: 10)
        XCTAssertEqual(predictor.effectivePosition(reported: 62, now: 12), 62)
    }

    func testClockGoingBackwardsIsIgnored() {
        var predictor = PressPredictor()
        predictor.recordJump(to: 60, at: 10)
        XCTAssertEqual(predictor.effectivePosition(reported: 5, now: 9), 5)
    }

    func testReset() {
        var predictor = PressPredictor()
        predictor.recordJump(to: 60, at: 10)
        predictor.reset()
        XCTAssertEqual(predictor.effectivePosition(reported: 5, now: 10.1), 5)
    }
}
