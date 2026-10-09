import XCTest
@testable import ParrotCore

@MainActor
final class PendingDictationsTests: XCTestCase {
    func testDictationsJoinAsParagraphs() {
        let pending = PendingDictations()
        let start = Date()
        XCTAssertEqual(pending.add(" Le titre est trop long. ", at: start), "Le titre est trop long.")
        XCTAssertEqual(pending.takeNotice(), "1 dictée en attente · ⌘V pour coller")
        XCTAssertNil(pending.takeNotice())
        XCTAssertEqual(pending.add("Et le bouton est mal aligné.", at: start + 60),
                       "Le titre est trop long.\n\nEt le bouton est mal aligné.")
        XCTAssertEqual(pending.takeNotice(), "2 dictées en attente · ⌘V pour coller")
    }

    func testAnOldBlockStartsOver() {
        let pending = PendingDictations()
        let start = Date()
        _ = pending.add("avant", at: start)
        XCTAssertEqual(pending.add("après", at: start + PendingDictations.expiry + 1), "après")
    }

    func testClearStartsOver() {
        let pending = PendingDictations()
        _ = pending.add("avant", at: Date())
        pending.clear()
        XCTAssertNil(pending.takeNotice())
        XCTAssertEqual(pending.add("après", at: Date()), "après")
    }

    func testADictationInAFieldTakesTheBlockAlong() {
        let pending = PendingDictations()
        let start = Date()
        _ = pending.add("Le titre est trop long.", at: start)
        _ = pending.add("Le bouton est mal aligné.", at: start + 30)
        XCTAssertEqual(pending.flush("Corrige les deux.", at: start + 60),
                       "Le titre est trop long.\n\nLe bouton est mal aligné.\n\nCorrige les deux.")
        // Gone once pasted.
        XCTAssertEqual(pending.flush("Merci.", at: start + 90), "Merci.")
    }

    func testAnOldBlockIsNotPastedAlong() {
        let pending = PendingDictations()
        let start = Date()
        _ = pending.add("avant", at: start)
        XCTAssertEqual(pending.flush("après", at: start + PendingDictations.expiry + 1), "après")
    }

    func testTheBlockIsRecognizedInAField() {
        let first = "Le titre de la page est beaucoup trop long pour un écran de téléphone."
        XCTAssertTrue(PendingDictations.holdsBlock("Retour sur la page :\n\n" + first + "\n\nEt le bouton…", first: first))
        XCTAssertFalse(PendingDictations.holdsBlock("Retour sur la page", first: first))
        XCTAssertTrue(PendingDictations.holdsBlock("ok. merci", first: "ok."))
        XCTAssertFalse(PendingDictations.holdsBlock("rien", first: ""))
    }

    func testOnlyAKnownNonTextRoleIsNowhere() {
        XCTAssertTrue(PendingDictations.isNowhere(role: "AXWebArea", editable: false))
        XCTAssertTrue(PendingDictations.isNowhere(role: "AXButton", editable: false))
        XCTAssertFalse(PendingDictations.isNowhere(role: "AXTextArea", editable: false))
        XCTAssertFalse(PendingDictations.isNowhere(role: "AXGroup", editable: false))
        // An element that says nothing, or one whose text can be set, is a field.
        XCTAssertFalse(PendingDictations.isNowhere(role: nil, editable: false))
        XCTAssertFalse(PendingDictations.isNowhere(role: "AXWebArea", editable: true))
    }
}
