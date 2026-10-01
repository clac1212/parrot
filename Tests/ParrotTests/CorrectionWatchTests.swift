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

    func testWhitespaceIsNoAnchor() {
        // A dictation alone in its field, with the space Spacing adds after it.
        let value = "Ok, là je viens de faire une dictée. "
        let range = CorrectionWatch.locate("Ok, là je viens de faire une dictée.", in: value, cursor: 37)!
        let anchors = CorrectionWatch.anchors(around: range, in: value)
        XCTAssertEqual(anchors.before, "")
        XCTAssertEqual(anchors.after, "")
        let edited = "Ok, là je viens de faire une seule dictée. "
        XCTAssertEqual(
            CorrectionWatch.span(in: edited, before: anchors.before, after: anchors.after, near: range.lowerBound),
            "Ok, là je viens de faire une seule dictée."
        )
    }

    func testAnEmptiedFieldIsNoEdit() {
        XCTAssertNil(CorrectionWatch.span(in: "", before: "", after: "", near: 0))
        XCTAssertNil(CorrectionWatch.span(in: " \n", before: "", after: "", near: 0))
    }

    func testEmptyAnchorsAreTheFieldEnds() {
        XCTAssertEqual(CorrectionWatch.span(in: "tout le champ ", before: "", after: "", near: 0), "tout le champ")
        XCTAssertEqual(CorrectionWatch.span(in: "avant: la dictée", before: "avant:", after: "", near: 6), "la dictée")
    }

    func testTheBeforeAnchorClosestToTheSpanIsUsed() {
        let value = "ok. un. ok. deux. fin"
        XCTAssertEqual(CorrectionWatch.span(in: value, before: "ok.", after: " fin", near: 11), "deux.")
    }

    func testSharesNoWord() {
        XCTAssertTrue(CorrectionWatch.sharesNoWord("Ask for a follow-up. @ to mention files", "Ok, je viens de faire une dictée."))
        XCTAssertFalse(CorrectionWatch.sharesNoWord("Ok, je viens de faire une dictée.", "Ok, la jeune femme dictée."))
        // Words under three letters don't count.
        XCTAssertTrue(CorrectionWatch.sharesNoWord("et je", "et je"))
    }

    func testAMissingAnchorGivesNothing() {
        XCTAssertNil(CorrectionWatch.span(in: "message envoyé", before: "Bonjour, ", after: "", near: 9))
        XCTAssertNil(CorrectionWatch.span(in: "Bonjour, texte", before: "Bonjour, ", after: " Merci", near: 9))
    }
}
