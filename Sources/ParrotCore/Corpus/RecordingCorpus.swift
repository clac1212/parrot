import Foundation

/// `settings.json` → `corpus`: keep every dictation's audio and what became
/// of its text (fork-003, fork-005). On by default since the daily review
/// learns from it (fork-009); audio is deleted after 30 days. `false` turns
/// both off.
struct CorpusSettings: Codable, Equatable {
    /// Keep each capture as a WAV in `Paths.corpus`.
    var enabled = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

extension Paths {
    /// `~/Library/Application Support/parrot/corpus` — the recordings kept by
    /// `RecordingCorpus`. Not Caches: the system would purge a corpus that
    /// takes days of dictation to build.
    static var corpus: URL { appSupport.appendingPathComponent("corpus", isDirectory: true) }
}

/// Keeps each dictation's audio, as captured (16 kHz mono, before the silence
/// trim), when `corpus.enabled` is set, and what became of its transcript
/// once pasted (`CorrectionWatch`, fork-005).
@MainActor
enum RecordingCorpus {
    /// Read at each release; set by the daemon from the settings.
    static var isEnabled: () -> Bool = { false }

    /// Keeps `samples`; returns the recording's name without extension, or
    /// nil when the corpus is off. Ends the previous dictation's correction
    /// watch, corpus or not (it also feeds fork-019's offers): this release
    /// comes before anything new is pasted.
    @discardableResult
    static func keep(_ samples: [Float]) -> String? {
        CorrectionWatch.shared.finish()
        ClipboardPasteWatch.shared.cancel()
        guard isEnabled(), !samples.isEmpty else { return nil }
        let name = fileName(for: Date())
        // Off the main actor: the transcription waits on it.
        Task.detached(priority: .utility) {
            do {
                let dir = try Paths.prepareDirectory(Paths.corpus)
                let file = try Paths.preparePrivateFile(dir.appendingPathComponent(name))
                try WAVWriter.write(samples: samples, sampleRate: Int(AudioCapture.targetSampleRate), to: file.path)
                Log.info("  corpus: kept \(name)")
            } catch {
                Log.error("  corpus: could not keep the recording: \(error)")
            }
        }
        return (name as NSString).deletingPathExtension
    }

    /// `text` was pasted for the recording `kept`: watch what the user does
    /// with it. Without the corpus (`kept` nil) the watch still runs, for
    /// fork-019's offers to learn a correction, and writes nothing.
    static func delivered(_ text: String, raw: String, kept: String?, model: String) {
        guard !text.isEmpty else { return }
        let file = record(kept)
        CorrectionWatch.shared.start(pasted: text, raw: raw == text ? nil : raw, file: file, model: model)
        // fork-019: it went to the clipboard block (fork-013) instead; watch
        // it once the user pastes it. A block of several dictations has no
        // one record: offers only.
        if let block = PendingDictations.shared.waiting {
            let single = block.count == 1
            ClipboardPasteWatch.shared.expect(block.text, raw: single && raw != text ? raw : nil, file: single ? file : nil, model: model)
        }
    }

    /// `text` was left on the clipboard because focus moved during the
    /// dictation: watch it once the user pastes it (fork-019).
    static func copied(_ text: String, raw: String, kept: String?, model: String) {
        ClipboardPasteWatch.shared.expect(text, raw: raw == text ? nil : raw, file: record(kept), model: model)
    }

    private static func record(_ kept: String?) -> URL? {
        kept.map { Paths.corpus.appendingPathComponent($0).appendingPathExtension("json") }
    }

    /// `2026-10-01_10-12-03.wav`, in local time, so files sort by date.
    nonisolated static func fileName(for date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return format.string(from: date) + ".wav"
    }
}
