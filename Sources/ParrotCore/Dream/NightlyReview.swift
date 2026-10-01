import AppKit
import Foundation

// The nightly review (fork-009): `parrot dream prepare` re-listens to the
// corpus and lists recurring substitutions; a judge (Claude, and Jev-Style in
// shadow) classifies them; `parrot dream apply` remembers the verdicts, adds
// dictionary entries (or proposes them) and writes the morning report.

extension Paths {
    /// `~/Library/Application Support/parrot/dream`: candidates, verdicts,
    /// re-transcriptions, reports, dictionary backups, the job's scripts.
    package static var dream: URL { appSupport.appendingPathComponent("dream", isDirectory: true) }
}

/// `settings.json` → `dream`.
struct DreamSettings: Codable, Equatable {
    /// Write accepted entries to the dictionary. Off: they are proposed in
    /// the report only (the first week, fork-009).
    var autoApply = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoApply = try c.decodeIfPresent(Bool.self, forKey: .autoApply) ?? false
    }
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
}

package enum NightlyReview {
    /// Re-transcriptions per night, so a first run on a large corpus ends.
    static let maxReferencesPerRun = 200
    /// Candidates sent to the judge per night.
    static let maxCandidates = 40
    /// A judged pair is asked again once it has been seen this many times as
    /// often as when it was judged.
    static let reaskFactor = 2
    /// A `dictionary` verdict at or above this probability is applied (or
    /// proposed); below, it is listed as uncertain.
    static let acceptProbability = 0.8
    /// The heavy model that re-listens at night: too slow to dictate with.
    static let referenceModel = "whisper-large-v3-turbo"

    static func key(wrong: String, right: String) -> String { "\(wrong.lowercased())→\(right)" }

    // MARK: - prepare

    /// Re-transcribes what isn't yet, then writes `candidates.json`.
    package static func prepare() async throws {
        let dir = try Paths.prepareDirectory(Paths.dream)
        let records = try CorpusRecord.all()
        Log.info("dream: \(records.count) dictations in the corpus")
        try await reTranscribe(records)
        let candidates = try await MainActor.run { try buildCandidates(records) }
        let out = DreamCandidates(generated: ISO8601DateFormatter().string(from: Date()), candidates: candidates)
        try write(out, to: dir.appendingPathComponent("candidates.json"))
        Log.info("dream: \(candidates.count) candidates for the judge")
    }

    private static func reTranscribe(_ records: [CorpusRecord]) async throws {
        let missing = records.filter { $0.reference == nil && FileManager.default.fileExists(atPath: $0.wav.path) }
            .prefix(maxReferencesPerRun)
        guard !missing.isEmpty, let model = ModelRegistry.find(referenceModel) else { return }
        let transcriber = WhisperKitTranscriber(model: model)
        try await transcriber.warmUp()
        let refs = try Paths.prepareDirectory(Paths.dream.appendingPathComponent("references", isDirectory: true))
        for record in missing {
            guard let audio = WAVReader.samples(record.wav), !audio.isEmpty else { continue }
            let transcript = try await transcriber.transcribe(audio, context: TranscriptionContext(language: "fr"))
            let file = try Paths.preparePrivateFile(refs.appendingPathComponent(record.name + ".txt"))
            try Data(transcript.text.utf8).write(to: file)
        }
        await transcriber.unload()
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
            if let judged = memory.entries[k], count < judged.count * reaskFactor { return false }
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

    // MARK: - apply

    /// Reads the judges' decisions, remembers them, applies or proposes the
    /// dictionary entries, and writes the morning report.
    package static func apply(judge: URL?, shadow: URL?) throws {
        let dir = try Paths.prepareDirectory(Paths.dream)
        let candidates = (try? read(DreamCandidates.self, from: dir.appendingPathComponent("candidates.json")))?.candidates ?? []
        let main = judge.flatMap { try? readDecisions($0) }
        let other = shadow.flatMap { try? readDecisions($0) }
        let settings = (try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: Paths.settingsFile))) ?? Settings()

        var memory = VerdictMemory.load()
        var applied: [DreamCandidate] = [], proposed: [DreamCandidate] = []
        let byID = Dictionary(uniqueKeysWithValues: (main?.decisions ?? []).map { ($0.id, $0) })
        for candidate in candidates {
            guard let decision = byID[candidate.id] else { continue }
            memory.entries[candidate.key] = .init(verdict: decision.verdict, count: candidate.count, date: Report.day(Date()))
            guard decision.verdict == "dictionary", decision.probability >= acceptProbability else { continue }
            if settings.dream.autoApply {
                try DictionaryEditor.add(wrong: candidate.wrong, right: candidate.right)
                try DictionaryEditor.log("+ \(candidate.right)  ←  \(candidate.wrong)  (\(candidate.count)×, \(main?.judge ?? "judge") \(decision.probability))")
                applied.append(candidate)
            } else {
                proposed.append(candidate)
            }
        }
        try memory.save()
        let agreement = Agreement.update(main: main, shadow: other)
        let report = Report.render(
            candidates: candidates, main: main, shadow: other, applied: applied, proposed: proposed,
            autoApply: settings.dream.autoApply, agreement: agreement
        )
        let reports = try Paths.prepareDirectory(dir.appendingPathComponent("reports", isDirectory: true))
        let file = try Paths.preparePrivateFile(reports.appendingPathComponent(Report.day(Date()) + ".md"))
        try Data(report.utf8).write(to: file)
        try State(lastRun: ISO8601DateFormatter().string(from: Date()), lastReport: file.path).save()
        Log.info("dream: \(applied.count) applied, \(proposed.count) proposed; report \(file.lastPathComponent)")
    }

    /// A judge's output: ours (`DreamDecisions`) or Claude's raw `--output-format json`, whose
    /// `structured_output` holds the decisions.
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

    /// When the last night ran and where its report is, for Settings.
    package struct State: Codable {
        package var lastRun: String
        package var lastReport: String

        static var file: URL { Paths.dream.appendingPathComponent("state.json") }
        package static func load() -> State? { try? NightlyReview.read(State.self, from: file) }
        func save() throws { try NightlyReview.write(self, to: Self.file) }
    }
}

/// Verdicts already given, so a pair isn't judged every night.
struct VerdictMemory: Codable {
    struct Entry: Codable {
        var verdict: String
        var count: Int
        var date: String
    }

    var entries: [String: Entry] = [:]

    static var file: URL { Paths.dream.appendingPathComponent("verdicts.json") }
    static func load() -> VerdictMemory { (try? NightlyReview.read(VerdictMemory.self, from: file)) ?? VerdictMemory() }
    func save() throws { try NightlyReview.write(self, to: Self.file) }
}

/// How often the shadow judge agrees with the main one, night after night:
/// the measure for moving judging onto the Mac (fork-009).
struct Agreement: Codable {
    var compared = 0
    var agreed = 0
    var lastCompared = 0
    var lastAgreed = 0

    static var file: URL { Paths.dream.appendingPathComponent("agreement.json") }

    static func update(main: DreamDecisions?, shadow: DreamDecisions?) -> Agreement? {
        guard let main, let shadow else { return nil }
        var total = (try? NightlyReview.read(Agreement.self, from: file)) ?? Agreement()
        let theirs = Dictionary(uniqueKeysWithValues: shadow.decisions.map { ($0.id, $0.verdict) })
        let pairs = main.decisions.compactMap { d in theirs[d.id].map { (d.verdict, $0) } }
        total.lastCompared = pairs.count
        total.lastAgreed = pairs.filter { $0.0 == $0.1 }.count
        total.compared += total.lastCompared
        total.agreed += total.lastAgreed
        try? NightlyReview.write(total, to: file)
        return total
    }
}

/// One dictation of the corpus, as the review reads it.
struct CorpusRecord {
    var name: String
    var wav: URL
    var pasted: String
    var final: String?
    var status: String
    var reference: String?

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
                final: record.final, status: record.status.rawValue, reference: reference
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

/// Adds entries to the user's dictionary file, keeping their layout.
enum DictionaryEditor {
    /// Adds `wrong` to the Replaces of `right`'s line, or a new line.
    static func add(wrong: String, right: String) throws {
        let file = Paths.dictionaryFile
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try backup(text)
        var lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { word(of: $0) == right }) {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            lines[i] = line == right ? "\(right)  \(wrong)" : "\(line), \(wrong)"
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append("\(right)  \(wrong)")
            lines.append("")
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

    private static func backup(_ text: String) throws {
        let dir = try Paths.prepareDirectory(Paths.dream.appendingPathComponent("backups", isDirectory: true))
        let file = dir.appendingPathComponent("dictionary-\(Report.day(Date())).txt")
        // One backup per night: the state before the night's first change.
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
            try Data(("# Dictionary changes made at night (fork-009)\n\n" + entry).utf8)
                .write(to: Paths.preparePrivateFile(file))
        }
    }
}

/// The morning report, in French: numbers and lists, no model writes it.
enum Report {
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func render(
        candidates: [DreamCandidate], main: DreamDecisions?, shadow: DreamDecisions?,
        applied: [DreamCandidate], proposed: [DreamCandidate], autoApply: Bool, agreement: Agreement?
    ) -> String {
        let records = (try? CorpusRecord.all()) ?? []
        let since = NightlyReview.State.load().flatMap { ISO8601DateFormatter().date(from: $0.lastRun) } ?? .distantPast
        let recent = records.filter { record in
            let date = (try? record.wav.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (date ?? .distantPast) > since
        }
        var out = "# Revue de nuit — \(day(Date()))\n\n"
        out += "Mode : \(autoApply ? "**automatique**, les entrées sûres vont dans le dictionnaire" : "**propositions seulement**, rien n'est écrit dans le dictionnaire")\n\n"
        out += "## Activité depuis la dernière nuit\n\n"
        out += "- \(recent.count) dictées · \(recent.filter { $0.status == "edited" }.count) corrigées par toi · "
            + "\(recent.filter { $0.status == "unreadable" }.count) illisibles\n"
        out += "- Corpus total : \(records.count) dictées, \(records.filter { $0.status == "edited" }.count) corrigées\n\n"

        let verdicts = Dictionary(uniqueKeysWithValues: (main?.decisions ?? []).map { ($0.id, $0) })
        let shadows = Dictionary(uniqueKeysWithValues: (shadow?.decisions ?? []).map { ($0.id, $0) })
        out += "## Candidats examinés (\(candidates.count))\n\n"
        if main == nil, !candidates.isEmpty { out += "_Le juge n'a pas répondu cette nuit ; les candidats reviendront demain._\n\n" }
        if !candidates.isEmpty {
            out += "| Écrit | → Voulu | Vu | Juge | Ombre |\n|---|---|---|---|---|\n"
            for c in candidates {
                let m = verdicts[c.id].map { "\($0.verdict) \(String(format: "%.2f", $0.probability))" } ?? "—"
                let s = shadows[c.id].map { "\($0.verdict) \(String(format: "%.2f", $0.probability))" } ?? "—"
                out += "| \(c.wrong) | \(c.right) | \(c.count) | \(m) | \(s) |\n"
            }
            out += "\n"
        }
        if !applied.isEmpty {
            out += "## Ajouté au dictionnaire\n\n" + applied.map { "- \($0.right) ← \($0.wrong)" }.joined(separator: "\n") + "\n\n"
            out += "Sauvegarde et historique : `~/Library/Application Support/parrot/dream/`.\n\n"
        }
        if !proposed.isEmpty {
            out += "## Propositions\n\nÀ copier dans le dictionnaire (Réglages → Open Dictionary File) si elles te vont :\n\n```\n"
            out += proposed.map { "\($0.right)  \($0.wrong)" }.joined(separator: "\n") + "\n```\n\n"
        }
        if let agreement, agreement.compared > 0 {
            out += "## Juge local (Jev-Style) face à Claude\n\n"
            out += "- Cette nuit : \(agreement.lastAgreed)/\(agreement.lastCompared) d'accord\n"
            out += "- Depuis le début : \(agreement.agreed)/\(agreement.compared) "
                + "(\(Int((Double(agreement.agreed) / Double(agreement.compared) * 100).rounded())) %)\n"
        }
        return out
    }
}
