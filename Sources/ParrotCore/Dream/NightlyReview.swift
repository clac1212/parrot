import AppKit
import Foundation

// The daily review (fork-009), a loop that needs nothing from the user:
// `parrot dream prepare` re-listens to the corpus, lists recurring
// substitutions and audits the entries it learned before; a judge (Claude)
// classifies both; `parrot dream apply` adds the safe entries to the
// dictionary, removes learned ones that did harm, and writes the report.

extension Paths {
    /// `~/Library/Application Support/parrot/dream`: candidates, verdicts,
    /// re-transcriptions, reports, dictionary backups, the job's scripts.
    package static var dream: URL { appSupport.appendingPathComponent("dream", isDirectory: true) }
}

struct DreamCandidate: Codable, Equatable {
    struct Example: Codable, Equatable {
        var pasted: String?
        var final: String?
        var reference: String?
    }

    var id: String
    var wrong: String
    var right: String
    var count: Int
    var userEdits: Int
    var referenceHits: Int
    /// Dictations where the re-transcription disagreed but the user left
    /// the pasted text as it was.
    var userKept: Int
    var phonetic: Double
    var wrongIsFrenchWord: Bool
    var examples: [Example]

    enum CodingKeys: String, CodingKey {
        case id, wrong, right, count, phonetic, examples
        case userEdits = "user_edits", referenceHits = "reference_hits", userKept = "user_kept"
        case wrongIsFrenchWord = "wrong_is_french_word"
    }

    var key: String { NightlyReview.key(wrong: wrong, right: right) }
}

struct DreamCandidates: Codable {
    var generated: String
    var candidates: [DreamCandidate]
    /// Learned entries with evidence against them (since 2026-10-02).
    var audits: [DreamAudit]?
}

struct DreamDecision: Codable, Equatable {
    var id: String
    var verdict: String
    var probability: Double
    var reason: String?
}

struct DreamDecisions: Codable {
    var judge: String?
    var decisions: [DreamDecision]
    /// `keep` or `remove` per audit id.
    var audits: [DreamDecision]?
}

package enum NightlyReview {
    /// Re-transcriptions per night, so a first run on a large corpus ends.
    static let maxReferencesPerRun = 200
    /// Candidates sent to the judge per night.
    static let maxCandidates = 40
    /// A judged pair is asked again once it has been seen this many times as
    /// often as when it was judged.
    static let reaskFactor = 2
    /// A `dictionary` verdict is applied at or above this probability…
    static let acceptProbability = 0.85
    /// …and once the error was seen this many times: the two guards that
    /// replace the user's review.
    static let minOccurrences = 2
    /// A `remove` verdict on a learned entry is applied at or above this.
    static let removeProbability = 0.7
    /// Days of corpus audio kept (the text records stay).
    static let retentionDays = 30
    /// The model that re-listens at night (`CohereReference`).
    static let referenceModel = "cohere-transcribe"

    static func key(wrong: String, right: String) -> String { "\(wrong.lowercased())→\(right)" }

    // MARK: - prepare

    /// Re-transcribes what isn't yet, then writes `candidates.json`.
    package static func prepare() async throws {
        let dir = try Paths.prepareDirectory(Paths.dream)
        let records = try CorpusRecord.all()
        Log.info("dream: \(records.count) dictations in the corpus")
        try await reTranscribe(records)
        let listened = try CorpusRecord.all()
        pruneAudio(listened)
        let candidates = try await MainActor.run { try buildCandidates(listened) }
        let audits = buildAudits(listened, learned: Learned.load())
        let out = DreamCandidates(generated: ISO8601DateFormatter().string(from: Date()), candidates: candidates, audits: audits)
        try write(out, to: dir.appendingPathComponent("candidates.json"))
        Log.info("dream: \(candidates.count) candidates and \(audits.count) audits for the judge")
    }

    private static func reTranscribe(_ records: [CorpusRecord]) async throws {
        let missing = records.filter { $0.reference == nil && FileManager.default.fileExists(atPath: $0.wav.path) }
            .prefix(maxReferencesPerRun)
        guard !missing.isEmpty else { return }
        let cohere = try await CohereReference.load()
        let refs = try Paths.prepareDirectory(Paths.dream.appendingPathComponent("references", isDirectory: true))
        for record in missing {
            guard let audio = WAVReader.samples(record.wav), !audio.isEmpty else { continue }
            let text = try await cohere.transcribe(audio)
            let file = try Paths.preparePrivateFile(refs.appendingPathComponent(record.name + ".txt"))
            try Data(text.utf8).write(to: file)
        }
        Log.info("dream: re-transcribed \(missing.count) dictations with \(referenceModel)")
    }

    @MainActor
    static func buildCandidates(_ records: [CorpusRecord]) throws -> [DreamCandidate] {
        struct Tally {
            var wrong: String, right: String
            var user = 0, reference = 0, kept = 0
            var examples: [DreamCandidate.Example] = []
        }
        var tallies: [String: Tally] = [:]
        func note(_ sub: WordAlignment.Substitution, _ record: CorpusRecord, user: Bool) {
            let k = key(wrong: sub.wrong, right: sub.right)
            var t = tallies[k] ?? Tally(wrong: sub.wrong, right: sub.right)
            if user { t.user += 1 } else if record.status == "unchanged" { t.kept += 1 } else { t.reference += 1 }
            if t.examples.count < 3 {
                t.examples.append(.init(
                    pasted: WordAlignment.excerpt(record.pasted, around: sub.wrong),
                    final: record.final.flatMap { WordAlignment.excerpt($0, around: sub.right) },
                    reference: record.reference.flatMap { WordAlignment.excerpt($0, around: sub.right) }
                ))
            }
            tallies[k] = t
        }
        for record in records {
            var seen = Set<String>()
            if record.status == "edited", let final = record.final {
                for sub in WordAlignment.substitutions(from: record.pasted, to: final)
                where seen.insert("u" + key(wrong: sub.wrong, right: sub.right)).inserted {
                    note(sub, record, user: true)
                }
            }
            if let reference = record.reference {
                for sub in WordAlignment.substitutions(from: record.pasted, to: reference)
                where seen.insert("r" + key(wrong: sub.wrong, right: sub.right)).inserted {
                    note(sub, record, user: false)
                }
            }
        }

        let dictionary = (try? UserDictionary.parse(Data(contentsOf: Paths.dictionaryFile))) ?? .empty
        let mapped = Set(dictionary.replacements.flatMap { r in r.from.map { key(wrong: $0, right: r.to) } })
        let memory = VerdictMemory.load()
        let speller = NSSpellChecker.shared

        let kept = tallies.values.filter { t in
            let k = key(wrong: t.wrong, right: t.right)
            let count = t.user + t.reference
            guard t.user >= 1 || t.reference >= 2 else { return false }
            guard !mapped.contains(k), t.wrong.contains(where: \.isLetter) else { return false }
            if let judged = memory.entries[k], judged.verdict == VerdictMemory.removed || count < judged.count * reaskFactor { return false }
            return true
        }
        .sorted { ($0.user * 3 + $0.reference) > ($1.user * 3 + $1.reference) }
        .prefix(maxCandidates)

        return kept.enumerated().map { i, t in
            let isWord = t.wrong.split(separator: " ").allSatisfy { word in
                speller.checkSpelling(of: String(word), startingAt: 0, language: "fr", wrap: false,
                                      inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
            }
            return DreamCandidate(
                id: "c\(i + 1)", wrong: t.wrong, right: t.right, count: t.user + t.reference,
                userEdits: t.user, referenceHits: t.reference, userKept: t.kept,
                phonetic: (FrenchPhonetics.similarity(t.wrong, t.right) * 100).rounded() / 100,
                wrongIsFrenchWord: isWord, examples: t.examples
            )
        }
    }

        // MARK: - audits

    /// The learned entries that fired in dictations where the user changed
    /// the replaced word or the re-listener heard something else: evidence
    /// that the entry may be doing harm, for the judge to keep or remove.
    static func buildAudits(_ records: [CorpusRecord], learned: Learned) -> [DreamAudit] {
        var audits: [DreamAudit] = []
        for (key, entry) in learned.entries.sorted(by: { $0.key < $1.key }) {
            var audit = DreamAudit(id: "", key: key, wrong: entry.wrong, right: entry.right)
            for record in records {
                guard let raw = record.raw, contains(raw, entry.wrong), contains(record.pasted, entry.right) else { continue }
                audit.fired += 1
                var evidence = false
                if record.status == "edited", let final = record.final {
                    if contains(final, entry.right) { audit.userKept += 1 } else { audit.userReverted += 1; evidence = true }
                } else if record.status == "unchanged" {
                    audit.userKept += 1
                }
                if let reference = record.reference, !contains(reference, entry.right) {
                    audit.referenceDisagreed += 1
                    evidence = true
                }
                if evidence, audit.examples.count < 3 {
                    audit.examples.append(.init(
                        pasted: WordAlignment.excerpt(record.pasted, around: entry.right),
                        final: record.final.flatMap { WordAlignment.excerpt($0, around: entry.right) } ?? record.final.map { String($0.prefix(120)) },
                        reference: record.reference.map { String($0.prefix(160)) }
                    ))
                }
            }
            if audit.userReverted + audit.referenceDisagreed > 0 { audits.append(audit) }
        }
        return audits.enumerated().map { i, a in var a = a; a.id = "a\(i + 1)"; return a }
    }

    /// Whether `text` holds `phrase` as whole words, ignoring case.
    static func contains(_ text: String, _ phrase: String) -> Bool {
        let t = WordAlignment.tokens(text).map(\.key), p = WordAlignment.tokens(phrase).map(\.key)
        guard !p.isEmpty, t.count >= p.count else { return false }
        return (0...(t.count - p.count)).contains { Array(t[$0..<($0 + p.count)]) == p }
    }

    /// Audio older than `retentionDays` is deleted once re-listened to; the
    /// text records stay, they are what the loop learns from.
    static func pruneAudio(_ records: [CorpusRecord], now: Date = Date()) {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        var removed = 0
        for record in records where record.reference != nil {
            guard let date = format.date(from: record.name),
                  now.timeIntervalSince(date) > Double(retentionDays) * 86_400,
                  (try? FileManager.default.removeItem(at: record.wav)) != nil
            else { continue }
            removed += 1
        }
        if removed > 0 { Log.info("dream: deleted the audio of \(removed) dictations older than \(retentionDays) days") }
    }

    // MARK: - apply

    /// Remembers the verdicts, removes the learned entries the judge found
    /// harmful, adds the ones it found safe, and writes the report. Nothing
    /// asks the user: the next run audits what this one added.
    package static func apply(judge: URL?, shadow: URL? = nil) throws {
        let dir = try Paths.prepareDirectory(Paths.dream)
        let input = try? read(DreamCandidates.self, from: dir.appendingPathComponent("candidates.json"))
        let candidates = input?.candidates ?? [], audits = input?.audits ?? []
        let main = judge.flatMap { try? readDecisions($0) }
        let trial = shadow.flatMap { try? readDecisions($0) }
        let today = Report.day(Date())

        var memory = VerdictMemory.load()
        var learned = Learned.load()
        let byID = Dictionary(uniqueKeysWithValues: (main?.decisions ?? []).map { ($0.id, $0) })
        for candidate in candidates {
            guard let decision = byID[candidate.id], memory.entries[candidate.key]?.verdict != VerdictMemory.removed else { continue }
            memory.entries[candidate.key] = .init(
                verdict: decision.verdict, count: candidate.count, date: today,
                probability: decision.probability, wrong: candidate.wrong, right: candidate.right,
                example: candidate.examples.first.map(Proposal.example)
            )
        }

        // Remove first: a learned entry that did harm goes, for good.
        var removed: [(Learned.Entry, String)] = []
        let auditVerdicts = Dictionary(uniqueKeysWithValues: (main?.audits ?? []).map { ($0.id, $0) })
        for audit in audits {
            guard let entry = learned.entries[audit.key] else { continue }
            let verdict = auditVerdicts[audit.id]
            // Without a judge, only overwhelming evidence removes.
            let remove = verdict.map { $0.verdict == "remove" && $0.probability >= removeProbability }
                ?? (audit.userReverted >= 2 && audit.userKept == 0)
            guard remove else { continue }
            let reason = verdict?.reason ?? "reverted \(audit.userReverted)× by the user"
            try DictionaryEditor.remove(wrong: entry.wrong, right: entry.right, dropLine: entry.createdLine)
            try DictionaryEditor.log("− \(entry.right)  ←  \(entry.wrong)  (\(reason))")
            learned.entries[audit.key] = nil
            learned.removed[audit.key] = .init(wrong: entry.wrong, right: entry.right, at: today, reason: reason)
            memory.entries[audit.key]?.verdict = VerdictMemory.removed
            removed.append((entry, reason))
        }

        // Then add every safe verdict not in the dictionary yet.
        let dictionary = (try? UserDictionary.parse(Data(contentsOf: Paths.dictionaryFile))) ?? .empty
        var applied: [Proposal] = []
        for proposal in memory.pending(in: dictionary) where learned.removed[proposal.key] == nil {
            let created = try DictionaryEditor.add(wrong: proposal.wrong, right: proposal.right)
            try DictionaryEditor.log("+ \(proposal.right)  ←  \(proposal.wrong)  (\(proposal.count)×, \(String(format: "%.2f", proposal.probability)))")
            learned.entries[proposal.key] = .init(wrong: proposal.wrong, right: proposal.right, added: today, createdLine: created)
            applied.append(proposal)
        }
        try memory.save()
        try learned.save()

        // The trial judge is compared, never applied (fork-009 §6).
        let comparison = ShadowTrial.compare(candidates: candidates, audits: audits, main: main, trial: trial)
        let totals = comparison.flatMap { try? ShadowTrial.record($0) }
        let report = Report.render(
            candidates: candidates, audits: audits, main: main, applied: applied,
            removed: removed, learned: learned
        ) + ShadowTrial.section(comparison, totals: totals, trial: trial, candidates: candidates)
        let reports = try Paths.prepareDirectory(dir.appendingPathComponent("reports", isDirectory: true))
        // One report per run, so a second run the same day keeps the first.
        let file = try Paths.preparePrivateFile(reports.appendingPathComponent(Report.stamp(Date()) + ".md"))
        try Data(report.utf8).write(to: file)
        let end = ISO8601DateFormatter().string(from: Date())
        let judged = main != nil || (candidates.isEmpty && audits.isEmpty)
        try State(
            lastRun: end, lastReport: file.path, candidates: candidates.count,
            applied: applied.count, removed: removed.count, learned: learned.entries.count, judged: judged
        ).save()
        try Journal.append(Journal.Entry(
            at: end, result: "done", reason: judged ? "" : "no judge",
            candidates: candidates.count, applied: applied.count, removed: removed.count
        ))
        Log.info("dream: \(applied.count) learned, \(removed.count) removed; report \(file.lastPathComponent)")
    }

    /// A judge's output: ours (`DreamDecisions`) or Claude's raw
    /// `--output-format json`, whose `structured_output` holds the decisions.
    static func readDecisions(_ url: URL) throws -> DreamDecisions {
        let data = try Data(contentsOf: url)
        if let decoded = try? JSONDecoder().decode(DreamDecisions.self, from: data) { return decoded }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let structured = object["structured_output"]
        else { throw CocoaError(.fileReadCorruptFile) }
        var decisions = try JSONDecoder().decode(DreamDecisions.self, from: JSONSerialization.data(withJSONObject: structured))
        decisions.judge = decisions.judge ?? "claude"
        return decisions
    }

    // MARK: - files

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let file = try Paths.preparePrivateFile(url)
        try encoder.encode(value).write(to: file)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// The last run, for the panel.
    package struct State: Codable {
        package var lastRun: String
        package var lastReport: String
        package var candidates: Int?
        package var applied: Int?
        package var removed: Int?
        /// Entries the loop added and still keeps.
        package var learned: Int?
        /// False when the judge didn't answer: candidates come back next run.
        package var judged: Bool?

        static var file: URL { Paths.dream.appendingPathComponent("state.json") }
        package static func load() -> State? { try? NightlyReview.read(State.self, from: file) }
        func save() throws { try NightlyReview.write(self, to: Self.file) }
    }
}

struct DreamAudit: Codable, Equatable {
    var id: String
    var key: String
    var wrong: String
    var right: String
    /// Dictations where the entry rewrote `wrong` into `right`.
    var fired = 0
    var userReverted = 0
    var userKept = 0
    var referenceDisagreed = 0
    var examples: [DreamCandidate.Example] = []

    enum CodingKeys: String, CodingKey {
        case id, key, wrong, right, fired, examples
        case userReverted = "user_reverted", userKept = "user_kept", referenceDisagreed = "reference_disagreed"
    }
}

/// A second judge running beside the main one for a trial: the same
/// candidates, its verdicts compared and counted, nothing applied
/// (fork-009 §6, Bonsai 2 27B). What decides a switch is the dictionary
/// additions: would both judges have written the same entries?
struct ShadowTrial: Codable, Equatable {
    var runs = 0
    var compared = 0
    var sameVerdict = 0
    /// Additions (dictionary, ≥ acceptProbability, seen ≥ minOccurrences).
    var addBoth = 0
    var addMainOnly = 0
    var addTrialOnly = 0
    var auditsCompared = 0
    var auditsSame = 0

    static var file: URL { Paths.dream.appendingPathComponent("shadow.json") }

    /// Nil when either judge is missing.
    static func compare(candidates: [DreamCandidate], audits: [DreamAudit],
                        main: DreamDecisions?, trial: DreamDecisions?) -> ShadowTrial? {
        guard let main, let trial else { return nil }
        let a = Dictionary(uniqueKeysWithValues: main.decisions.map { ($0.id, $0) })
        let b = Dictionary(uniqueKeysWithValues: trial.decisions.map { ($0.id, $0) })
        func adds(_ d: DreamDecision?, _ c: DreamCandidate) -> Bool {
            guard let d else { return false }
            return d.verdict == "dictionary" && d.probability >= NightlyReview.acceptProbability
                && c.count >= NightlyReview.minOccurrences
        }
        var run = ShadowTrial(runs: 1)
        for c in candidates {
            guard let x = a[c.id], let y = b[c.id] else { continue }
            run.compared += 1
            if x.verdict == y.verdict { run.sameVerdict += 1 }
            switch (adds(x, c), adds(y, c)) {
            case (true, true): run.addBoth += 1
            case (true, false): run.addMainOnly += 1
            case (false, true): run.addTrialOnly += 1
            case (false, false): break
            }
        }
        let aa = Dictionary(uniqueKeysWithValues: (main.audits ?? []).map { ($0.id, $0.verdict) })
        let ba = Dictionary(uniqueKeysWithValues: (trial.audits ?? []).map { ($0.id, $0.verdict) })
        for audit in audits {
            guard let x = aa[audit.id], let y = ba[audit.id] else { continue }
            run.auditsCompared += 1
            if x == y { run.auditsSame += 1 }
        }
        return run
    }

    /// Adds `run` to the running totals; returns them.
    static func record(_ run: ShadowTrial) throws -> ShadowTrial {
        var t = (try? NightlyReview.read(ShadowTrial.self, from: file)) ?? ShadowTrial()
        t.runs += run.runs; t.compared += run.compared; t.sameVerdict += run.sameVerdict
        t.addBoth += run.addBoth; t.addMainOnly += run.addMainOnly; t.addTrialOnly += run.addTrialOnly
        t.auditsCompared += run.auditsCompared; t.auditsSame += run.auditsSame
        try NightlyReview.write(t, to: file)
        return t
    }

    /// The report's section; empty when no trial judge ran.
    static func section(_ run: ShadowTrial?, totals: ShadowTrial?, trial: DreamDecisions?, candidates: [DreamCandidate]) -> String {
        guard let run, let totals else { return "" }
        let b = Dictionary(uniqueKeysWithValues: (trial?.decisions ?? []).map { ($0.id, $0) })
        var out = "\n## Essai : Bonsai (juge local) face à Claude\n\n"
        out += "Bonsai juge les mêmes candidats ; ses verdicts ne sont jamais appliqués.\n\n"
        out += "| | Cette revue | Depuis le début |\n|---|---|---|\n"
        out += "| Même verdict | \(run.sameVerdict)/\(run.compared) | \(totals.sameVerdict)/\(totals.compared) |\n"
        out += "| Ajouts décidés par les deux | \(run.addBoth) | \(totals.addBoth) |\n"
        out += "| Ajouts de Claude que Bonsai rate | \(run.addMainOnly) | \(totals.addMainOnly) |\n"
        out += "| **Ajouts de Bonsai que Claude refuse** | **\(run.addTrialOnly)** | **\(totals.addTrialOnly)** |\n"
        if totals.auditsCompared > 0 {
            out += "| Vérifications : même verdict | \(run.auditsSame)/\(run.auditsCompared) | \(totals.auditsSame)/\(totals.auditsCompared) |\n"
        }
        out += "\nCritère pour basculer : les ajouts de Bonsai que Claude refuse restent à 0 sur quelques dizaines d'ajouts.\n"
        if !candidates.isEmpty {
            out += "\n| Écrit | → Voulu | Bonsai |\n|---|---|---|\n"
            for c in candidates {
                let v = b[c.id].map { "\($0.verdict) \(String(format: "%.2f", $0.probability))" } ?? "—"
                out += "| \(c.wrong) | \(c.right) | \(v) |\n"
            }
        }
        return out
    }
}

/// `dream/learned.json`: what the loop wrote to the dictionary, so it only
/// ever removes its own entries, never the user's, and what it removed, so
/// those never come back.
struct Learned: Codable {
    struct Entry: Codable, Equatable {
        var wrong: String
        var right: String
        var added: String
        /// The loop wrote the whole line (not just a Replaces item): removing
        /// the entry removes the line.
        var createdLine: Bool
    }

    struct Removal: Codable, Equatable {
        var wrong: String
        var right: String
        var at: String
        var reason: String
    }

    var entries: [String: Entry] = [:]
    var removed: [String: Removal] = [:]

    static var file: URL { Paths.dream.appendingPathComponent("learned.json") }
    static func load() -> Learned { (try? NightlyReview.read(Learned.self, from: file)) ?? Learned() }
    func save() throws { try NightlyReview.write(self, to: Self.file) }
}

/// `dream/runs.jsonl`: one line per attempt — done, failed or skipped (the
/// script writes those two) — to know what ran while the Mac was asleep.
enum Journal {
    struct Entry: Codable {
        var at: String
        var result: String
        var reason: String
        var candidates: Int?
        var applied: Int?
        var removed: Int?
    }

    static var file: URL { Paths.dream.appendingPathComponent("runs.jsonl") }

    static func append(_ entry: Entry) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try encoder.encode(entry) + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try handle.close()
        } else {
            try line.write(to: Paths.preparePrivateFile(file))
        }
    }
}

/// A dictionary entry the judge accepted: `right  wrong` in the file.
struct Proposal: Equatable {
    var key: String
    var wrong: String
    var right: String
    var count: Int
    var probability: Double
    var example: String?

    /// "… nosamment … → … notamment …": what was pasted, then what the user
    /// kept or the re-listener heard.
    static func example(_ e: DreamCandidate.Example) -> String {
        let after = e.final ?? e.reference
        return [e.pasted, after].compactMap { $0.map { "… \($0) …" } }.joined(separator: " → ")
    }
}

/// Verdicts already given, so a pair isn't judged every run.
struct VerdictMemory: Codable {
    struct Entry: Codable {
        var verdict: String
        var count: Int
        var date: String
        /// Recorded since 2026-10-02; older entries count as accepted.
        var probability: Double?
        var wrong: String?
        var right: String?
        /// Where it was seen: "… nosamment … → … notamment …".
        var example: String?
    }

    /// A learned entry the audit removed: never added again.
    static let removed = "removed"

    var entries: [String: Entry] = [:]

    /// Safe `dictionary` verdicts (probability and recurrence) the dictionary
    /// doesn't map yet, most seen first.
    func pending(in dictionary: UserDictionary) -> [Proposal] {
        let mapped = Set(dictionary.replacements.flatMap { r in r.from.map { NightlyReview.key(wrong: $0, right: r.to) } })
        return entries.compactMap { key, entry -> Proposal? in
            guard entry.verdict == "dictionary", (entry.probability ?? 1) >= NightlyReview.acceptProbability,
                  entry.count >= NightlyReview.minOccurrences, !mapped.contains(key)
            else { return nil }
            let parts = key.components(separatedBy: "→")
            guard let wrong = entry.wrong ?? parts.first, let right = entry.right ?? parts.last else { return nil }
            return Proposal(
                key: key, wrong: wrong, right: right, count: entry.count,
                probability: entry.probability ?? 1, example: entry.example
            )
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.right < $1.right }
    }

    static var file: URL { Paths.dream.appendingPathComponent("verdicts.json") }
    static func load() -> VerdictMemory { (try? NightlyReview.read(VerdictMemory.self, from: file)) ?? VerdictMemory() }
    func save() throws { try NightlyReview.write(self, to: Self.file) }
}

/// One dictation of the corpus, as the review reads it.
struct CorpusRecord {
    var name: String
    var wav: URL
    var pasted: String
    var final: String?
    var status: String
    var reference: String?
    /// Parakeet's text before the dictionary (records since 2026-10-02).
    var raw: String?

    static func all() throws -> [CorpusRecord] {
        let dir = Paths.corpus
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let refs = Paths.dream.appendingPathComponent("references", isDirectory: true)
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { file in
            let name = String(file.dropLast(5))
            guard let record = try? JSONDecoder().decode(CorrectionRecord.self, from: Data(contentsOf: dir.appendingPathComponent(file)))
            else { return nil }
            let reference = try? String(contentsOf: refs.appendingPathComponent(name + ".txt"), encoding: .utf8)
            return CorpusRecord(
                name: name, wav: dir.appendingPathComponent(name + ".wav"), pasted: record.pasted,
                final: record.final, status: record.status.rawValue, reference: reference, raw: record.raw
            )
        }
    }
}

/// Reads the corpus' WAVs: 16-bit PCM mono, as `WAVWriter` writes them.
enum WAVReader {
    static func samples(_ url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count > 12,
              data.prefix(4) == Data("RIFF".utf8)
        else { return nil }
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let size = Int(data[(offset + 4)..<(offset + 8)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            let body = offset + 8
            if id == "data" {
                let end = min(data.count, body + size)
                return stride(from: body, to: end - 1, by: 2).map { i in
                    Float(Int16(bitPattern: UInt16(data[i]) | UInt16(data[i + 1]) << 8)) / 32768
                }
            }
            offset = body + size + (size % 2)
        }
        return nil
    }
}

/// Edits the user's dictionary file, keeping their layout.
enum DictionaryEditor {
    /// Adds `wrong` to the Replaces of `right`'s line, or a new line.
    /// Returns true when it wrote a new line.
    @discardableResult
    static func add(wrong: String, right: String) throws -> Bool {
        let file = Paths.dictionaryFile
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try backup(text)
        var lines = text.components(separatedBy: "\n")
        var created = false
        if let i = lines.firstIndex(where: { word(of: $0) == right }) {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            lines[i] = line == right ? "\(right)  \(wrong)" : "\(line), \(wrong)"
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append("\(right)  \(wrong)")
            lines.append("")
            created = true
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
        return created
    }

    /// Takes `wrong` out of `right`'s Replaces; drops the line when it was
    /// the loop's and nothing is left on it.
    static func remove(wrong: String, right: String, dropLine: Bool) throws {
        let file = Paths.dictionaryFile
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { word(of: $0) == right }) else { return }
        try backup(text)
        let items = replaces(of: lines[i]).filter { $0.lowercased() != wrong.lowercased() }
        if items.isEmpty {
            if dropLine { lines.remove(at: i) } else { lines[i] = right }
        } else {
            lines[i] = "\(right)  \(items.joined(separator: ", "))"
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
    }

    /// The word column of a dictionary line, or nil for comments and blanks.
    static func word(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        let parts = trimmed.components(separatedBy: "\t").first?.components(separatedBy: "  ")
        return parts?.first?.trimmingCharacters(in: .whitespaces)
    }

    /// The Replaces items of a line: everything after its first tab or run of
    /// two spaces, split at commas.
    static func replaces(of line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let separator = trimmed.range(of: "\t") ?? trimmed.range(of: "  ")
        guard let separator else { return [] }
        return trimmed[separator.upperBound...].split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func backup(_ text: String) throws {
        let dir = try Paths.prepareDirectory(Paths.dream.appendingPathComponent("backups", isDirectory: true))
        let file = dir.appendingPathComponent("dictionary-\(Report.day(Date())).txt")
        // One backup per day: the state before the day's first change.
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try Data(text.utf8).write(to: Paths.preparePrivateFile(file))
    }

    static func log(_ line: String) throws {
        let file = Paths.dream.appendingPathComponent("changelog.md")
        let entry = "- \(Report.day(Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try handle.close()
        } else {
            try Data(("# Dictionary changes made by the daily review (fork-009)\n\n" + entry).utf8)
                .write(to: Paths.preparePrivateFile(file))
        }
    }
}

/// The report, in French: numbers and lists, no model writes it.
enum Report {
    /// `2026-10-02_09-10`, for one report per run.
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: date)
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Per day, the share of readable dictations the user corrected: the
    /// number the loop exists to bring down. Pure, so it is tested.
    static func editRate(_ records: [(name: String, status: String)], days: Int = 7) -> [(day: String, edited: Int, readable: Int)] {
        var byDay: [String: (Int, Int)] = [:]
        for r in records where r.status != "unreadable" {
            let day = String(r.name.prefix(10))
            var t = byDay[day] ?? (0, 0)
            t.1 += 1
            if r.status == "edited" { t.0 += 1 }
            byDay[day] = t
        }
        return byDay.keys.sorted().suffix(days).map { (day: $0, edited: byDay[$0]!.0, readable: byDay[$0]!.1) }
    }

    static func render(
        candidates: [DreamCandidate], audits: [DreamAudit], main: DreamDecisions?,
        applied: [Proposal], removed: [(Learned.Entry, String)], learned: Learned
    ) -> String {
        let records = (try? CorpusRecord.all()) ?? []
        var out = "# Revue — \(stamp(Date()).replacingOccurrences(of: "_", with: " "))\n\n"
        out += "Parrot apprend seul : il ajoute au dictionnaire ce qu'il est sûr d'avoir mal entendu, "
            + "et retire ce qui a fait plus de mal que de bien.\n\n"

        out += "## Ce que la boucle a fait\n\n"
        if applied.isEmpty, removed.isEmpty { out += "- Rien à changer cette fois.\n" }
        for p in applied { out += "- **Appris** : \(p.wrong) → \(p.right) (vu \(p.count)×)\n" }
        for (e, reason) in removed { out += "- **Retiré** : \(e.wrong) → \(e.right) — \(reason)\n" }
        out += "- Mots appris en tout : \(learned.entries.count)"
        if !learned.removed.isEmpty { out += " · retirés depuis le début : \(learned.removed.count)" }
        out += "\n\n"

        out += "## Dictées corrigées par toi, par jour\n\n| Jour | Corrigées |\n|---|---|\n"
        for d in editRate(records.map { ($0.name, $0.status) }) {
            out += "| \(d.day) | \(d.edited)/\(d.readable) (\(d.readable > 0 ? Int((Double(d.edited) / Double(d.readable) * 100).rounded()) : 0) %) |\n"
        }
        out += "\n"

        let verdicts = Dictionary(uniqueKeysWithValues: (main?.decisions ?? []).map { ($0.id, $0) })
        if main == nil, !(candidates.isEmpty && audits.isEmpty) {
            out += "_Le juge n'a pas répondu : les candidats reviendront à la prochaine revue._\n\n"
        }
        if !candidates.isEmpty {
            out += "## Candidats examinés (\(candidates.count))\n\n| Écrit | → Voulu | Vu | Verdict |\n|---|---|---|---|\n"
            for c in candidates {
                let v = verdicts[c.id].map { "\($0.verdict) \(String(format: "%.2f", $0.probability))" } ?? "—"
                out += "| \(c.wrong) | \(c.right) | \(c.count) | \(v) |\n"
            }
            out += "\n"
        }
        if !audits.isEmpty {
            let auditVerdicts = Dictionary(uniqueKeysWithValues: (main?.audits ?? []).map { ($0.id, $0) })
            out += "## Mots appris vérifiés (\(audits.count))\n\n| Entrée | Appliquée | Défaite par toi | Cohere autrement | Verdict |\n|---|---|---|---|---|\n"
            for a in audits {
                let v = auditVerdicts[a.id].map { "\($0.verdict) \(String(format: "%.2f", $0.probability))" } ?? "—"
                out += "| \(a.wrong) → \(a.right) | \(a.fired) | \(a.userReverted) | \(a.referenceDisagreed) | \(v) |\n"
            }
            out += "\n"
        }
        out += "Historique et sauvegardes : `~/Library/Application Support/parrot/dream/`.\n"
        return out
    }
}
