import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT through FluidAudio, on the Neural Engine (fork-004).
/// A transducer: its time follows the length of the audio, not the number of
/// words, unlike Whisper's decoder.
///
/// Parakeet takes no prompt, so the dictionary's example sentence is unused;
/// its word replacements still apply after transcription.
package actor ParakeetTranscriber: ModelTranscriber {
    let modelID: String
    private let model: TranscriptionModel
    private var manager: AsrManager?
    /// Set by `unload`: this transcriber was replaced and loads nothing more.
    private var retired = false

    /// The version behind the registry's only Parakeet model.
    private static let version = AsrModelVersion.ultra
    /// Same trim and padding as Whisper, so both engines hear the same audio.
    private static let tuning = WhisperTuning.standard
    /// Shorter audio is padded with silence up to this many samples (1 s), as
    /// FluidVoice does: FluidAudio refuses under 0.3 s, and a transducer has
    /// little to go on in less.
    static let minimumSamples = 16_000

    package init(model: TranscriptionModel) {
        self.modelID = model.id
        self.model = model
    }

    /// `~/Library/Application Support/parrot/fluidaudio/parakeet-ultra`. The
    /// last component is FluidAudio's folder name for `.ultra`, which it
    /// checks when loading.
    private static var directory: URL {
        Paths.appSupport
            .appendingPathComponent("fluidaudio", isDirectory: true)
            .appendingPathComponent("parakeet-ultra", isDirectory: true)
    }

    static func isCached(_ model: TranscriptionModel) -> Bool {
        AsrModels.modelsExist(at: directory, version: version)
    }

    func warmUp(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if manager != nil || retired { return }
        Log.info("loading \(model.id)...")
        _ = try Paths.prepareDirectory(Paths.appSupport)
        let models = try await AsrModels.downloadAndLoad(to: Self.directory, version: Self.version) { p in
            progress?(p.fractionCompleted)
        }
        try Task.checkCancellation()
        let loaded = AsrManager()
        try await loaded.loadModels(models)
        // One pass on silence, so the first dictation doesn't pay for the
        // Neural Engine's first run.
        var state = try TdtDecoderState()
        _ = try? await loaded.transcribe([Float](repeating: 0, count: Self.minimumSamples), decoderState: &state)
        // Replaced while loading (a model change during startup): drop it.
        if retired {
            await loaded.cleanup()
            return
        }
        manager = loaded
        Log.info("✓ \(model.id) ready")
    }

    func unload() async {
        retired = true
        guard let manager else { return }
        self.manager = nil
        await manager.cleanup()
    }

    /// Decodes in `context.language` when the Language setting or the single
    /// spoken language fixes one: for French, FluidAudio then swaps English
    /// function words ("the", "and"…) for their best French candidate. With
    /// Automatic and several languages, Parakeet picks the language itself.
    package func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        if manager == nil { try await warmUp() }
        guard let manager else { throw TranscriberError.notLoaded }

        let started = CFAbsoluteTimeGetCurrent()
        var input = Self.tuning.prepare(audio)
        let audioSeconds = Double(input.count) / AudioCapture.targetSampleRate
        guard !input.isEmpty else {
            // Nothing but silence: nothing to say.
            return Transcript(text: "", timings: TranscriberTimings(total: CFAbsoluteTimeGetCurrent() - started))
        }
        if input.count < Self.minimumSamples {
            input += [Float](repeating: 0, count: Self.minimumSamples - input.count)
        }
        let code = Self.language(for: context, model: model)
        let preprocessing = CFAbsoluteTimeGetCurrent() - started

        var state = try TdtDecoderState()
        let result = try await manager.transcribe(input, decoderState: &state, language: code.flatMap(Language.init(rawValue:)))
        let total = CFAbsoluteTimeGetCurrent() - started

        var timings = TranscriberTimings(audioSeconds: audioSeconds, preprocessing: preprocessing, total: total)
        if let metrics = result.performanceMetrics {
            timings.preprocessing += metrics.preprocessorTime
            timings.encoder = metrics.encoderTime
            timings.decoder = metrics.decoderTime
        }
        timings.postprocessing = max(0, total - timings.preprocessing - timings.encoder - timings.decoder)
        timings.language = code
        timings.tokens = result.tokenTimings?.count ?? 0
        // FluidAudio decodes in 15 s windows past that length.
        timings.windows = max(1, Int((audioSeconds / 15).rounded(.up)))
        let text = Self.clean(result.text)
        return Transcript(text: text, timings: timings)
    }

    /// Parakeet Ultra emits its unknown token, `<unk>`, where a person would
    /// write quotes or a dash ("qui dit <unk> mets à jour"): Moondream's
    /// post-training taught it marks its vocabulary lacks. Parakeet v3, on
    /// the same audio, writes "-" or nothing (fork-004). Dropped rather than
    /// guessed: quotes in one sentence, a dash in another. Pure, so it is
    /// tested.
    static func clean(_ text: String) -> String {
        guard text.contains("<unk>") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Before a comma or a period, the token goes with its space
        // ("blablabla <unk>, en" → "blablabla, en"); elsewhere it leaves one
        // space. The rest of the text, French spacing included, is untouched.
        var out = text.replacingOccurrences(of: #" *<unk> *(?=[,.…])"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #" *<unk> *"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The language code to pass, or nil to let Parakeet choose.
    static func language(for context: TranscriptionContext, model: TranscriptionModel) -> String? {
        let spoken = context.spokenLanguages.isEmpty ? SpokenLanguage.preferredCodes() : context.spokenLanguages
        switch SpokenLanguage.plan(setting: context.language, spoken: spoken, model: model) {
        case .fixed(let code): return code
        case .none, .detect: return nil
        }
    }
}
