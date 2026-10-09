import AppKit
import DynamicNotchKit
import SwiftUI

/// The dictation indicator, Dynamic Island–style around the MacBook notch
/// (fork-002): a pulsing dot and the elapsed time left of the notch, the
/// pill's live waveform right of it. Messages unfold under the notch. On a
/// screen without a notch, falls back to the bottom pill (`RecordingOverlay`).
///
/// Click-through like the pill: dictation is push-to-talk, there is nothing
/// to click, and a click must never give the notch's window the focus the
/// text is about to be pasted into.
@MainActor
final class NotchOverlay {
    private let pill = RecordingOverlay()
    private let levels = OverlayModel()
    private let clock = NotchClock()
    private let notch: DynamicNotch<NotchMessageView, NotchLeadingView, NotchTrailingView>
    /// Whether the notch, not the pill, shows the current state.
    private var onNotch = false
    /// Bumped by every show, so a message timer only hides its own message.
    private var generation = 0

    init() {
        let levels = levels
        let clock = clock
        notch = DynamicNotch(hoverBehavior: []) {
            NotchMessageView(clock: clock)
        } compactLeading: {
            NotchLeadingView(clock: clock)
        } compactTrailing: {
            NotchTrailingView(levels: levels)
        }
        // Morph straight from the compact state to a message, without
        // vanishing in between.
        notch.transitionConfiguration = .init(skipIntermediateHides: true)
    }

    /// Push a new audio level (0…~1). Safe to call from any thread.
    nonisolated func pushLevel(_ level: Float) {
        Task { @MainActor in
            if self.onNotch {
                self.levels.pushLevel(level)
            } else {
                self.pill.pushLevel(level)
            }
        }
    }

    // MARK: -

    /// The screen to show the notch on, or nil to use the pill: the same
    /// screen the pill would use, if it has a notch.
    private static func notchScreen() -> NSScreen? {
        guard let screen = NSScreen.main, screen.auxiliaryTopLeftArea != nil else { return nil }
        return screen
    }

    private func record() {
        generation += 1
        guard let screen = Self.notchScreen() else { return useThePill(.recording) }
        onNotch = true
        levels.resetLevels()
        levels.state = .recording
        clock.start()
        show { await $0.compact(on: screen) }
    }

    private func transcribe() {
        generation += 1
        guard onNotch else { return pill.show(.transcribing) }
        levels.state = .transcribing
        clock.stop()
    }

    private func showMessage(_ text: String) {
        generation += 1
        guard let screen = Self.notchScreen() else {
            leaveTheNotch()
            return pill.showMessage(text)
        }
        onNotch = true
        clock.message = text
        show { await $0.expand(on: screen) }
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + RecordingOverlay.messageDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.hide()
            }
        }
    }

    private func hide() {
        generation += 1
        guard onNotch else { return pill.hide() }
        Task { await notch.hide() }
    }

    private func useThePill(_ state: RecordingOverlay.State) {
        leaveTheNotch()
        pill.show(state)
    }

    /// The main screen changed to one without a notch: fold the notch, which
    /// may still show a message whose timer the new state cancelled.
    private func leaveTheNotch() {
        guard onNotch else { return }
        onNotch = false
        Task { await notch.hide() }
    }

    /// Runs a DynamicNotch transition, then makes its window click-through.
    /// DynamicNotchKit builds a new window each time the notch appears, in
    /// the synchronous start of the transition, so the window exists by the
    /// time this main-queue block runs, before the animation ends.
    private func show(_ transition: @escaping @MainActor (DynamicNotch<NotchMessageView, NotchLeadingView, NotchTrailingView>) async -> Void) {
        let notch = notch
        Task { await transition(notch) }
        DispatchQueue.main.async {
            notch.windowController?.window?.ignoresMouseEvents = true
        }
    }
}

extension NotchOverlay: DictationObserver {
    func dictationStarted() {
        record()
    }

    func dictationTranscribing() {
        transcribe()
    }

    func dictationFinished(_ result: DictationResult) {
        // Kept on the clipboard instead of pasted (fork-013): say so.
        if let notice = PendingDictations.shared.takeNotice() {
            showMessage(notice)
        } else {
            hide()
        }
    }

    func dictationFailed(_ error: Error) {
        if let text = RecordingOverlay.message(for: error) {
            showMessage(text)
        } else {
            hide()
        }
    }
}

/// When the recording started and stopped, and the message to unfold.
@MainActor
final class NotchClock: ObservableObject {
    @Published private(set) var startedAt = Date()
    /// Set on release: the time stops while transcribing.
    @Published private(set) var stoppedAt: Date?
    @Published var message = ""

    func start() {
        startedAt = Date()
        stoppedAt = nil
    }

    func stop() {
        stoppedAt = Date()
    }

    /// "0:07", "1:42": minutes and seconds since the press.
    nonisolated static func elapsed(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(0, seconds))).formatted(.time(pattern: .minuteSecond))
    }
}

/// Left of the notch: a dot pulsing while recording, and the elapsed time.
struct NotchLeadingView: View {
    @ObservedObject var clock: NotchClock

    var body: some View {
        HStack(spacing: 6) {
            RecordingDot(recording: clock.stoppedAt == nil)
            TimelineView(.periodic(from: clock.startedAt, by: 1)) { context in
                Text(NotchClock.elapsed((clock.stoppedAt ?? context.date).timeIntervalSince(clock.startedAt)))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Right of the notch: the pill's waveform, settling into dots while
/// transcribing.
struct NotchTrailingView: View {
    @ObservedObject var levels: OverlayModel

    var body: some View {
        Waveform(
            levels: levels.levels,
            transcribing: levels.state == .transcribing,
            heardVoice: levels.heardVoice
        )
        .frame(width: 36, height: 14)
    }
}

/// Unfolded under the notch: one line, for example why a recording failed.
struct NotchMessageView: View {
    @ObservedObject var clock: NotchClock

    var body: some View {
        Text(clock.message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
    }
}

/// Red and pulsing while recording; still, in the waveform's blue, once the
/// key is released.
private struct RecordingDot: View {
    let recording: Bool

    var body: some View {
        if recording {
            dot(.red).phaseAnimator([false, true]) { dot, dimmed in
                dot.opacity(dimmed ? 0.35 : 1)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        } else {
            dot(Color(red: 181 / 255, green: 209 / 255, blue: 255 / 255))
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}
