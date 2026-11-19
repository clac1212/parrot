import XCTest
@testable import ParrotCore

/// fork-019: a replacement keeps the capital that started a sentence.
final class SentenceStartTests: XCTestCase {
    private func apply(_ text: String, _ from: String, _ to: String) -> String {
        DictionaryReplacer(rules: [.init(from: from, to: to)]).apply(to: text)
    }

    func testACapitalThatStartedASentenceStays() {
        XCTAssertEqual(apply("C'est bon. Vert d'eau.", "vert", "verre"), "C'est bon. Verre d'eau.")
        XCTAssertEqual(apply("Vert d'eau.", "vert", "verre"), "Verre d'eau.")
        XCTAssertEqual(apply("Ah ! Vert ? « Vert »", "vert", "verre"), "Ah ! Verre ? « Verre »")
        XCTAssertEqual(apply("fin\nVert", "vert", "verre"), "fin\nVerre")
    }

    func testElsewhereTheUsersSpellingStays() {
        XCTAssertEqual(apply("un Vert d'eau", "vert", "verre"), "un verre d'eau", "a capital mid-sentence is not kept")
        XCTAssertEqual(apply("Un vert. vert", "vert", "verre"), "Un verre. verre", "no capital to keep")
        XCTAssertEqual(apply("Bébé dort.", "bébé", "BB"), "BB dort.")
        XCTAssertEqual(apply("C'est Peep.", "pip", "Peep"), "C'est Peep.")
        XCTAssertEqual(apply("Pip. Pip", "pip", "Peep"), "Peep. Peep")
    }

    func testSentenceStarts() {
        let text = "a. (b c" as NSString
        XCTAssertTrue(SentenceStart.starts(at: 0, in: text))
        XCTAssertTrue(SentenceStart.starts(at: 4, in: text), "after « . ( »")
        XCTAssertFalse(SentenceStart.starts(at: 6, in: text))
    }
}
