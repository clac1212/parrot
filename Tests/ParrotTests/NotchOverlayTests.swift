import XCTest
@testable import ParrotCore

final class NotchOverlayTests: XCTestCase {
    func testElapsedIsMinutesAndSeconds() {
        XCTAssertEqual(NotchClock.elapsed(0), "0:00")
        XCTAssertEqual(NotchClock.elapsed(7.9), "0:07")
        XCTAssertEqual(NotchClock.elapsed(102), "1:42")
        XCTAssertEqual(NotchClock.elapsed(-0.2), "0:00")
    }
}
