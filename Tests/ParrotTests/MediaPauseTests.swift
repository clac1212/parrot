import XCTest
@testable import ParrotCore

final class MediaPauseTests: XCTestCase {
    func testParsesAStreamLine() {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","playing":true,"title":"x"}}"#
        XCTAssertEqual(MediaPause.parse(Data(line.utf8)), .init(app: "com.spotify.client", playing: true))
    }

    func testAnEmptyPayloadIsNothingPlaying() {
        let line = #"{"type":"data","diff":false,"payload":{}}"#
        XCTAssertEqual(MediaPause.parse(Data(line.utf8)), .init(app: nil, playing: false))
    }

    func testGarbageIsIgnored() {
        XCTAssertNil(MediaPause.parse(Data("not json".utf8)))
    }
}
