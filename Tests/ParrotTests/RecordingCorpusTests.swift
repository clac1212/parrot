import XCTest
@testable import ParrotCore

final class RecordingCorpusTests: XCTestCase {
    func testOffUnlessSet() throws {
        XCTAssertFalse(CorpusSettings().enabled)
        let empty = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.corpus.enabled)
        let on = try JSONDecoder().decode(Settings.self, from: Data(#"{"corpus": {"enabled": true}}"#.utf8))
        XCTAssertTrue(on.corpus.enabled)
    }

    func testFileNamesSortByDate() {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 10, 1, 9, 5, 3)
        let date = Calendar.current.date(from: parts)!
        XCTAssertEqual(RecordingCorpus.fileName(for: date), "2026-10-01_09-05-03.wav")
    }
}
