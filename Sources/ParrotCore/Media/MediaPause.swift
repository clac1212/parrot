import AppKit
import Foundation

extension Paths {
    /// `~/Library/Application Support/parrot/mediaremote` — the MediaRemote
    /// adapter built by `scripts/build-mediaremote.sh` (fork-008).
    static var mediaRemote: URL { appSupport.appendingPathComponent("mediaremote", isDirectory: true) }
}

/// Pauses the media playing when a dictation starts and resumes it when the
/// key is released (fork-008): music on the speakers no longer plays into the
/// microphone, and nothing has to be restarted by hand.
///
/// macOS 15.4+ lets only Apple-entitled binaries see and control what is
/// playing (MediaRemote), so this goes through the vendored adapter run by
/// `/usr/bin/perl`: one long-lived `stream` process reports the now-playing
/// app and whether it plays; `send` commands pause and play (~20 ms each).
/// Only what Parrot paused is resumed, and only if the same app is still the
/// one playing media.
@MainActor
final class MediaPause {
    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let script = Paths.mediaRemote.appendingPathComponent("mediaremote-adapter.pl")
    private static let framework = Paths.mediaRemote.appendingPathComponent("MediaRemoteAdapter.framework")
    /// MediaRemote command ids (the adapter's `send` table).
    private static let play = "0"
    private static let pause = "1"
    /// Restarts of a stream that exits, before giving up until relaunch.
    private static let maxRestarts = 5

    private var stream: Process?
    private var restarts = 0
    /// Bytes read from the stream that don't end a line yet.
    private var pending = Data()
    /// The now-playing app and whether it plays, from the last stream line.
    private var nowPlaying = NowPlaying()
    /// The app Parrot paused, to resume at release.
    private var pausedApp: String?

    /// Nil when the adapter isn't installed: the feature is off.
    init?() {
        guard FileManager.default.fileExists(atPath: Self.script.path),
              FileManager.default.fileExists(atPath: Self.framework.path)
        else {
            Log.info("media: adapter not installed (scripts/build-mediaremote.sh); media won't pause while dictating")
            return nil
        }
        startStream()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stream?.terminate() }
        }
    }

    struct NowPlaying: Equatable {
        var app: String?
        var playing = false
    }

    /// One `stream --no-diff` line: `{"type":"data","diff":false,"payload":{…}}`,
    /// the payload empty when nothing reports media. Pure, so it is tested.
    nonisolated static func parse(_ line: Data) -> NowPlaying? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        return NowPlaying(app: payload["bundleIdentifier"] as? String, playing: payload["playing"] as? Bool ?? false)
    }

    // MARK: -

    private func startStream() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [Self.script.path, Self.framework.path, "stream", "--no-diff", "--no-artwork"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.received(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        do {
            try process.run()
            stream = process
        } catch {
            Log.error("media: could not start the adapter: \(error)")
        }
    }

    private func received(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if let state = Self.parse(Data(line)) { nowPlaying = state }
        }
    }

    private func streamEnded() {
        stream = nil
        nowPlaying = NowPlaying()
        guard restarts < Self.maxRestarts else {
            Log.error("media: adapter keeps exiting; media won't pause until Parrot restarts")
            return
        }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts)) { [weak self] in
            MainActor.assumeIsolated { self?.startStream() }
        }
    }

    private func send(_ command: String) {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [Self.script.path, Self.framework.path, "send", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.error("media: could not send a command: \(error)")
        }
    }

    private func pauseIfPlaying() {
        guard nowPlaying.playing, let app = nowPlaying.app else { return }
        pausedApp = app
        send(Self.pause)
        Log.info("media: paused \(app)")
    }

    private func resumeIfPaused() {
        guard let app = pausedApp else { return }
        pausedApp = nil
        // Another app took over media meanwhile: leave both alone.
        guard nowPlaying.app == app else { return }
        send(Self.play)
        Log.info("media: resumed \(app)")
    }
}

extension MediaPause: DictationObserver {
    func dictationStarted() {
        pauseIfPlaying()
    }

    /// The key is released: the microphone is closed.
    func dictationTranscribing() {
        resumeIfPaused()
    }

    /// A short tap, a chord, or a capture that failed to start.
    func dictationFailed(_ error: Error) {
        resumeIfPaused()
    }
}
