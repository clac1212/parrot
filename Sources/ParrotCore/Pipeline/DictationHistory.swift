import Foundation

/// The last day's dictations, to copy one again from the panel (fork-015):
/// a paste that landed nowhere, a field that was cleared, a crash. Recorded
/// before delivery, so a failed paste is kept too.
///
/// Transcript text on disk, deliberately (as fork-005): one owner-only
/// file, nothing older than `keep`. The log never carries text.
@MainActor
final class DictationHistory: ObservableObject {
    static let shared = DictationHistory(file: Paths.history)
    nonisolated static let keep: TimeInterval = 24 * 60 * 60

    struct Entry: Codable, Equatable, Identifiable {
        let date: Date
        let text: String
        var id: Date { date }
    }

    /// Newest first, none older than `keep` when last pruned.
    @Published private(set) var entries: [Entry]
    private let file: URL
    private let writer = DispatchQueue(label: "parrot.history", qos: .utility)

    init(file: URL) {
        self.file = file
        entries = Self.recent(Self.load(file), now: Date())
    }

    func add(_ text: String, at date: Date = Date()) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries = Self.recent([Entry(date: date, text: text)] + entries, now: date)
        save()
    }

    /// Drops what has aged past `keep`; the panel calls it before showing.
    func prune(now: Date = Date()) {
        let kept = Self.recent(entries, now: now)
        guard kept != entries else { return }
        entries = kept
        save()
    }

    /// Within `keep` of `now`, newest first. Pure, so it is tested.
    nonisolated static func recent(_ entries: [Entry], now: Date) -> [Entry] {
        entries.filter { now.timeIntervalSince($0.date) <= keep }.sorted { $0.date > $1.date }
    }

    /// "14:32", or "hier 23:58" for the day before. Pure, so it is tested.
    nonisolated static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "HH:mm"
        let time = format.string(from: date)
        return calendar.isDate(date, inSameDayAs: now) ? time : "hier \(time)"
    }

    private func save() {
        let entries = entries
        let file = file
        writer.async {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(entries)
                // Rewritten in place: an atomic write would replace the
                // 0600 file with one at the default mode.
                try Paths.prepareDirectory(file.deletingLastPathComponent())
                try data.write(to: Paths.preparePrivateFile(file))
            } catch {
                Log.error("history: could not save: \(error)")
            }
        }
    }

    private static func load(_ file: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([Entry].self, from: data)
        } catch {
            // A write cut short by a crash: start over rather than stop.
            Log.warning("history: unreadable, starting over: \(error)")
            return []
        }
    }
}

/// The last processor: records the text as it will be pasted, unchanged.
struct HistoryProcessor: TranscriptProcessor {
    func process(_ transcript: Transcript) -> Transcript {
        // The controller runs processors on the main actor.
        MainActor.assumeIsolated { DictationHistory.shared.add(transcript.text) }
        return transcript
    }
}

extension Paths {
    static var history: URL { appSupport.appendingPathComponent("history.json") }
}
