import XCTest
@testable import ParrotCore

final class RecordingCorpusTests: XCTestCase {
    func testOnUnlessTurnedOff() throws {
        // On by default since the daily review learns from it (fork-009).
        XCTAssertTrue(CorpusSettings().enabled)
        let empty = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.corpus.enabled)
        let off = try JSONDecoder().decode(Settings.self, from: Data(#"{"corpus": {"enabled": false}}"#.utf8))
        XCTAssertFalse(off.corpus.enabled)
    }

    func testFileNamesSortByDate() {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 10, 1, 9, 5, 3)
        let date = Calendar.current.date(from: parts)!
        XCTAssertEqual(RecordingCorpus.fileName(for: date), "2026-10-01_09-05-03.wav")
    }
}
