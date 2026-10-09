import ApplicationServices
import Foundation

/// Dictations with nowhere to go (fork-013): said over a web page or a
/// button, not in a text field. Instead of a paste that lands nowhere, each
/// joins the ones before it on the clipboard, a paragraph each, and the
/// notch says how many are waiting. The block leaves either way the user
/// sends it:
/// - a dictation in a field pastes the block first, then itself;
/// - ⌘V in a field: Parrot can't see the keystroke (its key tap watches
///   modifiers only, by design) and macOS reads the clipboard as soon as it
///   changes (tested 2026-10-09), so while a block waits Parrot looks at the
///   focused field once a second for its first words.
/// Past `expiry` with nothing new, the block starts over.
@MainActor
final class PendingDictations {
    static let shared = PendingDictations()
    static let expiry: TimeInterval = 10 * 60

    private var texts: [String] = []
    private var last: Date?
    /// What the overlay says after the latest delivery, read once.
    private var notice: String?
    /// Looks for the block in the focused field while one waits.
    private var watch: Timer?

    enum Route: Equatable {
        /// No text field: leave this block on the clipboard.
        case clipboard(String)
        /// A text field: paste this, the waiting block first if any.
        case field(String)
    }

    /// Where `text` goes given `focus`.
    func route(_ text: String, focus: FocusSnapshot, at date: Date = Date()) -> Route {
        let role = focus.element.flatMap { Self.role(of: $0.ref) }
        guard Self.isNowhere(role: role, editable: focus.element.map { Self.isEditable($0.ref) } ?? false) else {
            return .field(flush(text, at: date))
        }
        let block = add(text, at: date)
        watchForPaste()
        // The role and a count only: the log never carries text.
        Log.info("  nowhere to paste (\(role ?? "?")): \(texts.count) waiting on the clipboard")
        return .clipboard(block)
    }

    /// `text` with the waiting block before it, which then starts over.
    func flush(_ text: String, at date: Date) -> String {
        defer { clear() }
        guard let last, date.timeIntervalSince(last) <= Self.expiry, !texts.isEmpty else { return text }
        Log.info("  \(texts.count) waiting dictations pasted with this one")
        return (texts + [text]).joined(separator: "\n\n")
    }

    /// Adds `text` to the block, or starts a new one past `expiry`.
    func add(_ text: String, at date: Date) -> String {
        if let last, date.timeIntervalSince(last) > Self.expiry { texts = [] }
        texts.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        last = date
        notice = texts.count == 1 ? "1 dictée en attente · ⌘V pour coller" : "\(texts.count) dictées en attente · ⌘V pour coller"
        return texts.joined(separator: "\n\n")
    }

    func clear() {
        texts = []
        last = nil
        notice = nil
        watch?.invalidate()
        watch = nil
    }

    private func watchForPaste() {
        guard watch == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookForPaste() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }

    private func lookForPaste() {
        guard let last, Date().timeIntervalSince(last) <= Self.expiry, let first = texts.first else { return clear() }
        let focus = FocusSnapshot.capture()
        guard let element = focus.element, !focus.isSecure else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element.ref, kAXValueAttribute as CFString, &value) == .success,
              let value = value as? String, Self.holdsBlock(value, first: first) else { return }
        Log.info("  waiting dictations pasted")
        clear()
    }

    /// Whether a field's text holds the block, by the first dictation's
    /// opening words. Pure, so it is tested.
    nonisolated static func holdsBlock(_ value: String, first: String) -> Bool {
        let mark = String(first.prefix(40))
        return !mark.isEmpty && value.contains(mark)
    }

    /// The line to show for the latest delivery, once.
    func takeNotice() -> String? {
        defer { notice = nil }
        return notice
    }

    /// Roles that hold no text to edit: a page, a link, a button, a list…
    /// Seen in the log as the focus of pastes that found no field (Dia:
    /// `AXWebArea`, `AXButton`). An element that says nothing — Electron
    /// still building its tree — or an `AXGroup`, which some editors use for
    /// their canvas, counts as a field: a dictation is never held back from
    /// one by a guess.
    nonisolated static let nowhereRoles: Set<String> = [
        "AXWebArea", "AXButton", "AXLink", "AXImage", "AXStaticText", "AXHeading",
        "AXList", "AXOutline", "AXTable", "AXRow", "AXCell", "AXScrollArea",
        "AXWindow", "AXApplication", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXTabGroup", "AXToolbar", "AXSplitGroup",
    ]

    /// Pure, so it is tested.
    nonisolated static func isNowhere(role: String?, editable: Bool) -> Bool {
        guard let role, !editable else { return false }
        return nowhereRoles.contains(role)
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// A value the app lets us set is text the user can edit, whatever the
    /// role says.
    private static func isEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }
}
