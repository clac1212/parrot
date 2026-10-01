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

    func testCoherePiecesStayUnderNineSeconds() {
        // 30 s of tone with a silent 200 ms every 5 s.
        var audio = [Float](repeating: 0.1, count: 30 * 16_000)
        for s in stride(from: 5, to: 30, by: 5) {
            for i in (s * 16_000)..<(s * 16_000 + 3_200) { audio[i] = 0 }
        }
        let pieces = CohereReference.pieces(audio)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.count }, audio.count)
        XCTAssertTrue(pieces.allSatisfy { Double($0.count) / 16_000 <= CohereReference.maxSegment })
        XCTAssertGreaterThan(pieces.count, 3)
        XCTAssertEqual(CohereReference.pieces(Array(audio.prefix(8 * 16_000))).count, 1)
    }

    func testCohereHallucinationFilter() {
        XCTAssertTrue(CohereReference.isHallucination("Merci."))
        XCTAssertTrue(CohereReference.isHallucination(" "))
        XCTAssertFalse(CohereReference.isHallucination("Merci pour ton retour."))
    }

    func testPhoneticSimilarity() {
        XCTAssertGreaterThan(FrenchPhonetics.similarity("Vercelle", "Vercel"), 0.8)
        XCTAssertGreaterThan(FrenchPhonetics.similarity("post hoc", "PostHog"), 0.6)
        XCTAssertGreaterThan(FrenchPhonetics.similarity("ces", "ses"), 0.9)
        XCTAssertLessThan(FrenchPhonetics.similarity("bonjour", "Vercel"), 0.4)
    }
}
