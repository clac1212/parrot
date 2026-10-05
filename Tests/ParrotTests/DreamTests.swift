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

final class VerdictMemoryTests: XCTestCase {
    func testExampleShowsBothSides() {
        XCTAssertEqual(
            Proposal.example(.init(pasted: "et nosamment le", final: "et notamment le", reference: nil)),
            "… et nosamment le … → … et notamment le …"
        )
    }

    func testPendingSkipsWhatTheDictionaryMaps() {
        var memory = VerdictMemory()
        memory.entries["nosamment→notamment"] = .init(verdict: "dictionary", count: 2, date: "2026-10-02")
        memory.entries["durama→diorama"] = .init(verdict: "dictionary", count: 1, date: "2026-10-02", probability: 0.9, wrong: "Durama", right: "diorama")
        memory.entries["vrai→ouais"] = .init(verdict: "rewrite", count: 1, date: "2026-10-02")
        memory.entries["cei→soit"] = .init(verdict: "dictionary", count: 1, date: "2026-10-02", probability: 0.6)
        let dictionary = UserDictionary(replacements: [.init(from: ["Durama"], to: "diorama")])
        // Durama is mapped, vrai is no entry, cei is unsure; nosamment counts.
        XCTAssertEqual(memory.pending(in: dictionary).map(\.key), ["nosamment→notamment"])
        memory.entries["nosamment→notamment"]?.verdict = VerdictMemory.removed
        XCTAssertTrue(memory.pending(in: dictionary).isEmpty)
    }

    func testOneSightingIsNotEnough() {
        var memory = VerdictMemory()
        memory.entries["parod→parrot"] = .init(verdict: "dictionary", count: 1, date: "2026-10-02", probability: 0.95)
        XCTAssertTrue(memory.pending(in: .empty).isEmpty)
    }
}

final class LearningLoopTests: XCTestCase {
    private func record(_ name: String, raw: String?, pasted: String, final: String?, status: String, reference: String? = nil) -> CorpusRecord {
        CorpusRecord(name: name, wav: URL(fileURLWithPath: "/dev/null"), pasted: pasted, final: final,
                     status: status, reference: reference, raw: raw)
    }

    func testAuditCountsWhereALearnedEntryFiredAndWasUndone() {
        var learned = Learned()
        learned.entries["la paire→la PR"] = .init(wrong: "la paire", right: "la PR", added: "2026-10-02", createdLine: true)
        let records = [
            record("2026-10-02_10-00-00", raw: "regarde la paire", pasted: "regarde la PR", final: "regarde la paire", status: "edited"),
            record("2026-10-02_11-00-00", raw: "merge la paire", pasted: "merge la PR", final: "merge la PR", status: "unchanged"),
            record("2026-10-02_12-00-00", raw: "rien", pasted: "rien", final: "rien", status: "unchanged"),
        ]
        let audits = NightlyReview.buildAudits(records, learned: learned)
        XCTAssertEqual(audits.count, 1)
        XCTAssertEqual(audits[0].fired, 2)
        XCTAssertEqual(audits[0].userReverted, 1)
        XCTAssertEqual(audits[0].userKept, 1)
        XCTAssertEqual(audits[0].id, "a1")
    }

    func testAnEntryWithoutEvidenceIsNotAudited() {
        var learned = Learned()
        learned.entries["nosamment→notamment"] = .init(wrong: "nosamment", right: "notamment", added: "2026-10-02", createdLine: true)
        let records = [record("2026-10-02_10-00-00", raw: "et nosamment", pasted: "et notamment", final: "et notamment", status: "unchanged")]
        XCTAssertTrue(NightlyReview.buildAudits(records, learned: learned).isEmpty)
    }

    func testContainsWholeWordsOnly() {
        XCTAssertTrue(NightlyReview.contains("Regarde la PR demain", "la pr"))
        XCTAssertFalse(NightlyReview.contains("la prière", "la pr"))
    }

    func testReplacesOfALine() {
        XCTAssertEqual(DictionaryEditor.replaces(of: "Vercel  Versailles, Vercelle"), ["Versailles", "Vercelle"])
        XCTAssertEqual(DictionaryEditor.replaces(of: "Parakeet"), [])
        XCTAssertEqual(DictionaryEditor.replaces(of: "Claude Code\tclaude code"), ["claude code"])
    }

    func testEditRatePerDay() {
        let rate = Report.editRate([
            ("2026-10-01_10-00-00", "edited"), ("2026-10-01_11-00-00", "unchanged"),
            ("2026-10-02_10-00-00", "unchanged"), ("2026-10-02_11-00-00", "unreadable"),
        ])
        XCTAssertEqual(rate.map(\.day), ["2026-10-01", "2026-10-02"])
        XCTAssertEqual(rate.map(\.edited), [1, 0])
        XCTAssertEqual(rate.map(\.readable), [2, 1])
    }
}

final class ShadowTrialTests: XCTestCase {
    private func candidate(_ id: String, count: Int) -> DreamCandidate {
        DreamCandidate(id: id, wrong: "w\(id)", right: "r\(id)", count: count, userEdits: 1, referenceHits: 1,
                       userKept: 0, phonetic: 0.8, wrongIsFrenchWord: false, examples: [])
    }

    func testCountsAdditionsBothWays() {
        let cands = [candidate("c1", count: 2), candidate("c2", count: 2), candidate("c3", count: 1), candidate("c4", count: 3),
                     candidate("c5", count: 2)]
        let main = DreamDecisions(judge: "claude", decisions: [
            .init(id: "c1", verdict: "dictionary", probability: 0.9),
            .init(id: "c2", verdict: "dictionary", probability: 0.95),
            .init(id: "c3", verdict: "dictionary", probability: 0.95),  // seen once: no addition
            .init(id: "c4", verdict: "one_off", probability: 0.9),
            .init(id: "c5", verdict: "dictionary", probability: 0.8),
        ])
        let trial = DreamDecisions(judge: "bonsai", decisions: [
            .init(id: "c1", verdict: "dictionary", probability: 0.9),
            .init(id: "c2", verdict: "one_off", probability: 0.8),
            .init(id: "c3", verdict: "dictionary", probability: 0.9),
            .init(id: "c4", verdict: "dictionary", probability: 0.9),
            .init(id: "c5", verdict: "dictionary", probability: 0.9),
        ])
        let run = ShadowTrial.compare(candidates: cands, audits: [], main: main, trial: trial)!
        XCTAssertEqual(run.compared, 5)
        XCTAssertEqual(run.sameVerdict, 3)
        XCTAssertEqual(run.addBoth, 1)
        XCTAssertEqual(run.addMainOnly, 1)
        // c4: Claude said one_off — a disagreement; c5: Claude said
        // dictionary at 0.8 — only less sure.
        XCTAssertEqual(run.addTrialOnlyDisagree, 1)
        XCTAssertEqual(run.addTrialOnlyLessSure, 1)
    }

    func testNoTrialNoComparison() {
        XCTAssertNil(ShadowTrial.compare(candidates: [], audits: [], main: nil, trial: nil))
    }
}
