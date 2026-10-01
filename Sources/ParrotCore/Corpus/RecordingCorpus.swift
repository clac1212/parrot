import Foundation

/// `settings.json` → `corpus`: keep every dictation's audio, to build a
/// benchmark of the user's own French (fork-003). Off unless set by hand:
/// there is no switch in the Settings window.
struct CorpusSettings: Codable, Equatable {
    /// Keep each capture as a WAV in `Paths.corpus`.
    var enabled = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
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
    /// watch: this release comes before anything new is pasted.
    @discardableResult
    static func keep(_ samples: [Float]) -> String? {
        guard isEnabled(), !samples.isEmpty else { return nil }
        CorrectionWatch.shared.finish()
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
    /// with it.
    static func delivered(_ text: String, kept: String?, model: String) {
        guard let kept, !text.isEmpty else { return }
        let file = Paths.corpus.appendingPathComponent(kept).appendingPathExtension("json")
        CorrectionWatch.shared.start(pasted: text, file: file, model: model)
    }

    /// `2026-10-01_10-12-03.wav`, in local time, so files sort by date.
    nonisolated static func fileName(for date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return format.string(from: date) + ".wav"
    }
}
