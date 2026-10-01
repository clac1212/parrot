import XCTest
@testable import ParrotCore

final class CorrectionWatchTests: XCTestCase {
    func testLocatesThePasteEndingAtTheCursor() {
        let value = "salut. salut. fin"
        // Two occurrences; the cursor sits after the second one and its space.
        XCTAssertEqual(CorrectionWatch.locate("salut.", in: value, cursor: 14), 7..<13)
        XCTAssertEqual(CorrectionWatch.locate(" salut. ", in: value, cursor: 6), 0..<6)
    }

    func testWithoutCursorOnlyAUniqueMatchCounts() {
        XCTAssertEqual(CorrectionWatch.locate("fin", in: "début fin", cursor: nil), 6..<9)
        XCTAssertNil(CorrectionWatch.locate("a", in: "a a", cursor: nil))
        XCTAssertNil(CorrectionWatch.locate("absent", in: "rien", cursor: 3))
        XCTAssertNil(CorrectionWatch.locate("  ", in: "rien", cursor: 3))
    }

    func testSpanFollowsEditsBetweenAnchors() {
        let edited = "Bonjour, je teste OpenTheso demain. Merci"
        XCTAssertEqual(
            CorrectionWatch.span(in: edited, before: "Bonjour, ", after: " Merci", near: 9),
            "je teste OpenTheso demain."
        )
    }

    func testEmptyAnchorsAreTheFieldEnds() {
        XCTAssertEqual(CorrectionWatch.span(in: "tout le champ ", before: "", after: "", near: 0), "tout le champ")
        XCTAssertEqual(CorrectionWatch.span(in: "avant: la dictée", before: "avant:", after: "", near: 6), "la dictée")
    }

    func testTheBeforeAnchorClosestToTheSpanIsUsed() {
        let value = "ok. un. ok. deux. fin"
        XCTAssertEqual(CorrectionWatch.span(in: value, before: "ok.", after: " fin", near: 11), "deux.")
    }

    func testAMissingAnchorGivesNothing() {
        XCTAssertNil(CorrectionWatch.span(in: "message envoyé", before: "Bonjour, ", after: "", near: 9))
        XCTAssertNil(CorrectionWatch.span(in: "Bonjour, texte", before: "Bonjour, ", after: " Merci", near: 9))
    }
}
