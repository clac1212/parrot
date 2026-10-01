import Foundation

/// A `Transcriber` backed by a model that loads before use and unloads on a
/// swap (#43), whatever its engine (fork-004). Startup, the model switcher
/// and `parrot models` hold one of these instead of a WhisperKit transcriber.
protocol ModelTranscriber: Transcriber {
    /// Downloads the model if needed, then loads it. `progress` gets the
    /// download's fraction done, 0 to 1, when there is anything to download.
    func warmUp(progress: (@Sendable (Double) -> Void)?) async throws
    /// Frees the model after a swap; a load still running is dropped.
    func unload() async
}

extension WhisperKitTranscriber: ModelTranscriber {}

/// The transcriber for each engine in the registry.
enum Transcribers {
    static func make(_ model: TranscriptionModel) -> any ModelTranscriber {
        switch model.engine {
        case .whisperKit: WhisperKitTranscriber(model: model)
        case .parakeet: ParakeetTranscriber(model: model)
        }
    }

    /// True if `model`'s weights are already under `Paths.appSupport`.
    static func isCached(_ model: TranscriptionModel) -> Bool {
        switch model.engine {
        case .whisperKit: WhisperKitTranscriber.isCached(model)
        case .parakeet: ParakeetTranscriber.isCached(model)
        }
    }
}
