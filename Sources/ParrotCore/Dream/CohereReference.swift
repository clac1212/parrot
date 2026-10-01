import FluidAudio
import Foundation

/// Cohere Transcribe (2B, through FluidAudio's Core ML port) as the nightly
/// review's re-listener (fork-009): worse than Parakeet Ultra as a transcript
/// (12.9 % vs 8.6 % WER on the user's corrected dictations) but the best at
/// flagging Parakeet's wrong words (77 % recall, 44 % precision; Whisper
/// large-v3-turbo: 70 % / 33 %), with French forced so it never drifts.
/// Too slow to dictate with (~6× real time), fine at night.
final class CohereReference: @unchecked Sendable {
    /// `~/Library/Application Support/parrot/fluidaudio/cohere-transcribe/q8`.
    static var base: URL { Paths.appSupport.appendingPathComponent("fluidaudio", isDirectory: true) }
    static var directory: URL { base.appendingPathComponent("cohere-transcribe/q8", isDirectory: true) }

    /// FluidAudio's Cohere decoder holds 99 tokens per call and French runs
    /// ~6–9 tokens a second, so longer audio is silently truncated: pieces of
    /// at most 9 s, cut at the quietest 200 ms after at least 4 s.
    static let minSegment = 4.0
    static let maxSegment = 9.0

    private let models: CoherePipeline.LoadedModels
    private let pipeline = CoherePipeline()

    private init(models: CoherePipeline.LoadedModels) {
        self.models = models
    }

    /// Loads the model, downloading it (2.1 GB) the first time.
    static func load() async throws -> CohereReference {
        let needed = [
            ModelNames.CohereTranscribe.encoderCompiledFile,
            ModelNames.CohereTranscribe.decoderCacheExternalV2CompiledFile,
            "vocab.json",
        ]
        if !needed.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
            _ = try Paths.prepareDirectory(base)
            try await ModelHub.download(.cohereTranscribeCoreml, to: base)
        }
        let models = try await CoherePipeline.loadModels(encoderDir: directory, decoderDir: directory, vocabDir: directory)
        return CohereReference(models: models)
    }

    /// The transcript of `audio` (16 kHz mono), in French.
    func transcribe(_ audio: [Float]) async throws -> String {
        var texts: [String] = []
        for piece in Self.pieces(audio) {
            let text = try await pipeline.transcribe(audio: piece, models: models, language: .french).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.isHallucination(text) { texts.append(text) }
        }
        return texts.joined(separator: " ")
    }

    /// A lone "Merci." Cohere sometimes adds to a piece that ends in silence.
    static func isHallucination(_ text: String) -> Bool {
        let bare = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return bare.isEmpty || bare == "merci"
    }

    /// `audio` cut into pieces of at most `maxSegment` seconds, each cut at
    /// the quietest 200 ms between `minSegment` and `maxSegment` after the
    /// previous one. Pure, so it is tested.
    static func pieces(_ audio: [Float], sampleRate: Int = 16_000) -> [[Float]] {
        let hop = sampleRate / 100
        let frames = audio.count / hop
        guard Double(audio.count) / Double(sampleRate) > maxSegment, frames > 0 else { return [audio] }
        var energy = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var sum: Float = 0
            for x in audio[(f * hop)..<((f + 1) * hop)] { sum += x * x }
            energy[f] = sum
        }
        let window = 20
        var cuts = [0]
        var start = 0
        while Double(frames - start) / 100 > maxSegment {
            let low = start + Int(minSegment * 100)
            let high = min(frames - window, start + Int(maxSegment * 100) - window)
            guard low <= high else { break }
            var best = low, bestEnergy = Float.greatestFiniteMagnitude
            for i in low...high {
                let e = energy[i..<(i + window)].reduce(0, +)
                if e < bestEnergy { bestEnergy = e; best = i }
            }
            start = best + window / 2
            cuts.append(start)
        }
        cuts.append(frames)
        return (0..<(cuts.count - 1)).map { j in
            let from = cuts[j] * hop
            let to = j == cuts.count - 2 ? audio.count : cuts[j + 1] * hop
            return Array(audio[from..<to])
        }
    }
}
