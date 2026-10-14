import XCTest
@testable import ParrotCore

final class CapitalizationTests: XCTestCase {
    private let none: (String) -> Bool = { _ in false }

    func testLeadFromTheTextBeforeTheCursor() {
        XCTAssertEqual(Capitalization.lead(""), .sentence)
        XCTAssertEqual(Capitalization.lead("Bonjour, "), .continuation)
        XCTAssertEqual(Capitalization.lead("on verra demain"), .continuation)
        XCTAssertEqual(Capitalization.lead("Note : "), .continuation)
        XCTAssertEqual(Capitalization.lead("C'est fait. "), .sentence)
        XCTAssertEqual(Capitalization.lead("Vraiment ? "), .sentence)
        XCTAssertEqual(Capitalization.lead("il a dit « fin. » "), .sentence)
        XCTAssertEqual(Capitalization.lead("première ligne\n"), .sentence)
        XCTAssertEqual(Capitalization.lead("salut\n- "), .unknown)
        XCTAssertEqual(Capitalization.lead("  "), .sentence)
        XCTAssertEqual(Capitalization.lead(String(repeating: " ", count: FocusedElement.lookBack)), .unknown)
        XCTAssertEqual(Capitalization.lead(nil), .unknown)
    }

    func testAContinuationLosesItsCapital() {
        XCTAssertEqual(Capitalization.adapt("Je voulais te dire.", lead: .continuation, isProperName: none), "je voulais te dire.")
        XCTAssertEqual(Capitalization.adapt("C'est bon.", lead: .continuation, isProperName: none), "c'est bon.")
    }

    func testNamesAndSpellingsKeepTheirCapital() {
        XCTAssertEqual(Capitalization.adapt("PR mergée.", lead: .continuation, isProperName: none), "PR mergée.")
        XCTAssertEqual(Capitalization.adapt("PostHog marche.", lead: .continuation, isProperName: none), "PostHog marche.")
        XCTAssertEqual(Capitalization.adapt("I think so.", lead: .continuation, isProperName: none), "I think so.")
        XCTAssertEqual(Capitalization.adapt("Claude a répondu.", lead: .continuation, isProperName: { $0 == "Claude" }),
                       "Claude a répondu.")
    }

    func testASentenceGainsACapital() {
        XCTAssertEqual(Capitalization.adapt("diorama fini.", lead: .sentence, isProperName: none), "Diorama fini.")
        XCTAssertEqual(Capitalization.adapt("iPhone neuf.", lead: .sentence, isProperName: none), "iPhone neuf.")
        XCTAssertEqual(Capitalization.adapt("Déjà fait.", lead: .sentence, isProperName: none), "Déjà fait.")
    }

    func testUnknownChangesNothing() {
        XCTAssertEqual(Capitalization.adapt("Je voulais.", lead: .unknown, isProperName: none), "Je voulais.")
        XCTAssertEqual(Capitalization.adapt("42 tickets.", lead: .continuation, isProperName: none), "42 tickets.")
    }

    func testProperNamesFromTheDictionary() {
        let dictionary = UserDictionary(terms: ["PostHog", "Hatch OS"], replacements: [.init(from: ["Cloude"], to: "Claude")])
        XCTAssertTrue(Capitalization.isProperName("Claude", in: "Claude a répondu.", dictionary: dictionary))
        XCTAssertTrue(Capitalization.isProperName("Hatch", in: "Hatch est prêt.", dictionary: dictionary))
        XCTAssertFalse(Capitalization.isProperName("Ensuite", in: "Ensuite on verra.", dictionary: dictionary))
    }
}
