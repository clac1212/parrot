import XCTest
@testable import ParrotCore

final class DreamTests: XCTestCase {
    func testSubstitutionsOfMisheardWords() {
        let subs = WordAlignment.substitutions(
            from: "Ok, la jeune femme dictée, je mets une correction.",
            to: "Ok, je viens de faire une dictée, je mets une correction."
        )
        // "je viens de faire une" is five words: past `maxWords`, a phrase
        // no dictionary entry should rewrite.
        XCTAssertTrue(subs.isEmpty)
        XCTAssertEqual(
            WordAlignment.substitutions(from: "on déploie sur Vercelle demain", to: "on déploie sur Vercel demain"),
            [.init(wrong: "Vercelle", right: "Vercel")]
        )
    }

    func testCasingIntoACanonicalSpelling() {
        XCTAssertEqual(
            WordAlignment.substitutions(from: "regarde posthog et la pr", to: "regarde PostHog et la PR"),
            [.init(wrong: "posthog", right: "PostHog"), .init(wrong: "pr", right: "PR")]
        )
        // A capital that only starts a sentence is not a spelling.
        XCTAssertTrue(WordAlignment.substitutions(from: "bonjour toi", to: "Bonjour toi").isEmpty)
    }

    func testInsertionsAreNotSubstitutions() {
        XCTAssertTrue(WordAlignment.substitutions(from: "sécurité normalement", to: "Sur la partie sécurité normalement").isEmpty)
    }

    func testExcerpt() {
        XCTAssertEqual(
            WordAlignment.excerpt("un deux trois quatre cinq six sept huit neuf dix", around: "cinq", words: 2),
            "trois quatre cinq six sept"
        )
        XCTAssertNil(WordAlignment.excerpt("rien ici", around: "absent"))
    }

    func testPhoneticSimilarity() {
        XCTAssertGreaterThan(FrenchPhonetics.similarity("Vercelle", "Vercel"), 0.8)
        XCTAssertGreaterThan(FrenchPhonetics.similarity("post hoc", "PostHog"), 0.6)
        XCTAssertGreaterThan(FrenchPhonetics.similarity("ces", "ses"), 0.9)
        XCTAssertLessThan(FrenchPhonetics.similarity("bonjour", "Vercel"), 0.4)
    }
}
