import XCTest
@testable import CheckpointCore

final class SkipDetectorTests: XCTestCase {
    private func sample(_ t: Double, _ index: Int?, _ position: Double?, duration: Double? = 200) -> PlayerSample {
        PlayerSample(time: t, entryIndex: index, position: position, duration: duration)
    }

    func testFirstSampleNeverFires() {
        var detector = SkipDetector()
        XCTAssertNil(detector.ingest(sample(0, 0, 10)))
    }

    func testSteadyPlaybackIsQuiet() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 10))
        XCTAssertNil(detector.ingest(sample(0.25, 0, 10.25)))
        XCTAssertNil(detector.ingest(sample(0.5, 0, 10.5)))
    }

    func testCloneAdvanceMidSongIsSystemNext() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 47.5))
        XCTAssertEqual(detector.ingest(sample(0.25, 1, 0.1)), .systemNext(fromPosition: 47.5))
    }

    func testAdvanceAtEndIsNaturalEnd() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 199.2))
        XCTAssertEqual(detector.ingest(sample(0.25, 1, 0.0)), .naturalEnd)
    }

    func testQueueOfOneEndingMidSongIsSystemNext() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 80))
        XCTAssertEqual(detector.ingest(sample(0.25, nil, nil)), .systemNext(fromPosition: 80))
    }

    func testQueueOfOneEndingAtEndIsNaturalEnd() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 199.5))
        XCTAssertEqual(detector.ingest(sample(0.25, nil, nil)), .naturalEnd)
    }

    func testRestartWithinEntryIsSystemPrevious() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 3, 75))
        XCTAssertEqual(detector.ingest(sample(0.25, 3, 0.2)), .systemPrevious(fromPosition: 75))
    }

    func testMovingBackAnEntryIsSystemPrevious() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 3, 1.0))
        XCTAssertEqual(detector.ingest(sample(0.25, 2, 0.0)), .systemPrevious(fromPosition: 1.0))
    }

    func testAppSeekBackwardsIsSuppressed() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 75))
        detector.noteAppAction(at: 0.1)
        XCTAssertNil(detector.ingest(sample(0.25, 0, 0.5)))
    }

    func testAppQueueReloadIsSuppressedThenDetectionResumes() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 5, 40))
        detector.noteAppAction(at: 0.1)
        XCTAssertNil(detector.ingest(sample(0.3, 0, 0)))       // our own reload
        XCTAssertNil(detector.ingest(sample(1.2, 0, 1.0)))
        _ = detector.ingest(sample(10, 0, 10))
        XCTAssertEqual(detector.ingest(sample(10.25, 1, 0)), .systemNext(fromPosition: 10))
    }

    func testUnknownDurationNeverCountsAsNaturalEnd() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, 0, 199.5, duration: nil))
        XCTAssertEqual(detector.ingest(sample(0.25, 1, 0, duration: nil)), .systemNext(fromPosition: 199.5))
    }

    func testNothingLoadedToSomethingLoadedIsQuiet() {
        var detector = SkipDetector()
        _ = detector.ingest(sample(0, nil, nil))
        XCTAssertNil(detector.ingest(sample(0.25, 0, 0)))
    }
}
