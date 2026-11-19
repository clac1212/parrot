import AppKit
import ApplicationServices

/// A dictation Parrot left on the clipboard instead of pasting it — focus
/// moved while the user spoke, or there was no text field (fork-013) — is
/// watched for corrections once the user pastes it (fork-019). Parrot can't
/// see the ⌘V (its key tap watches modifiers only, by design), so while the
/// text waits it reads the focused field twice a second for the text's
/// opening words, then hands it to `CorrectionWatch` as if it had pasted it.
///
/// It stops looking when the clipboard changes (the user copied something
/// else, so a later paste isn't this text), when the next dictation is
/// released, or after `PendingDictations.expiry`.
@MainActor
final class ClipboardPasteWatch {
    static let shared = ClipboardPasteWatch()
    nonisolated static let pollInterval: TimeInterval = 0.5

    private struct Waiting {
        let text: String
        let raw: String?
        /// The corpus record, for a single dictation; nil for a block of
        /// several, whose text no one recording holds.
        let file: URL?
        let model: String
        let changeCount: Int
        let since: Date
    }

    private var waiting: Waiting?
    private var timer: Timer?
    private let changeCount: () -> Int
    private let now: () -> Date
    /// The focused field's text, nil when it can't be read or is secure.
    private let focusedText: () -> String?
    /// Hands a pasted dictation to the correction watch.
    private let watch: (_ text: String, _ raw: String?, _ file: URL?, _ model: String) -> Void

    init(
        changeCount: @escaping () -> Int = { NSPasteboard.general.changeCount },
        now: @escaping () -> Date = Date.init,
        focusedText: (() -> String?)? = nil,
        watch: ((String, String?, URL?, String) -> Void)? = nil
    ) {
        self.changeCount = changeCount
        self.now = now
        self.focusedText = focusedText ?? Self.focusedText
        self.watch = watch ?? { CorrectionWatch.shared.start(pasted: $0, raw: $1, file: $2, model: $3) }
    }

    /// True while a dictation waits to be pasted.
    var isWaiting: Bool { waiting != nil }

    /// `text` was just put on the clipboard for the user to paste.
    func expect(_ text: String, raw: String?, file: URL?, model: String) {
        guard !text.isEmpty else { return }
        waiting = Waiting(text: text, raw: raw, file: file, model: model, changeCount: changeCount(), since: now())
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        waiting = nil
        timer?.invalidate()
        timer = nil
    }

    /// One look; the timer's body.
    func look() {
        guard let waiting, changeCount() == waiting.changeCount,
              now().timeIntervalSince(waiting.since) <= PendingDictations.expiry else { return cancel() }
        guard let value = focusedText(), PendingDictations.holdsBlock(value, first: waiting.text) else { return }
        cancel()
        Log.info("  corpus: dictation pasted by the user, watching it")
        watch(waiting.text, waiting.raw, waiting.file, waiting.model)
    }

    static func focusedText() -> String? {
        let focus = FocusSnapshot.capture()
        guard let element = focus.element, !focus.isSecure else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element.ref, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
