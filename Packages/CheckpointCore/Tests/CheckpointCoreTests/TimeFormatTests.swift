import XCTest
@testable import CheckpointCore

final class TimeFormatTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(TimeFormat.string(0), "0:00.0")
        XCTAssertEqual(TimeFormat.string(65.34), "1:05.3")
        XCTAssertEqual(TimeFormat.string(59.96), "1:00.0")
        XCTAssertEqual(TimeFormat.string(605, tenths: false), "10:05")
        XCTAssertEqual(TimeFormat.string(.nan), "0:00.0")
        XCTAssertEqual(TimeFormat.string(-3), "0:00.0")
    }
}
