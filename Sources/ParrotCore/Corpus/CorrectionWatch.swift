import AppKit
import ApplicationServices
import Foundation

/// What became of a pasted transcript, kept beside its recording in the
/// corpus as `<recording>.json` (fork-005): the text Parrot pasted and the
/// same span once the user was done with it. Edits are the transcription
/// errors the user noticed, or words to learn.
struct CorrectionRecord: Codable, Equatable {
    enum Status: String, Codable {
        /// The span changed after the paste.
        case edited
        /// The span was still as pasted.
        case unchanged
        /// The field couldn't be read, or the pasted text wasn't found in it
        /// (terminals, some web and Electron fields): `final` is nil.
        case unreadable
    }

    var model: String
    /// Bundle identifier of the app the text went to.
    var app: String?
    var pasted: String
    var final: String?
    var status: Status
    /// How long the span was watched, in seconds.
    var watched: Double
    /// Parakeet's text before the dictionary and other processors, so the
    /// review sees which dictionary entries fired (fork-009).
    var raw: String? = nil
}

/// Watches the span a transcript was pasted into until the user leaves the
/// field, dictates again, or a minute passes, then writes a `CorrectionRecord`.
/// Reads over Accessibility. The one write: an Electron app that names no
/// focused element is asked to turn its accessibility on
/// (`AXManualAccessibility`, Electron's documented switch for assistive
/// tools), and turned back off when the watch ends. Never
/// `AXEnhancedUserInterface`, which took focus away from Claude's input in
/// OpenWhispr (#1116).
///
/// The span is found where the cursor is after the paste, then followed by
/// the text around it (`anchorLength` characters each side), so edits inside
/// it are captured however its length changes. Text typed right after a
/// dictation pasted at the end of a field joins the span.
@MainActor
final class CorrectionWatch {
    static let shared = CorrectionWatch()

    /// How long after delivery to look for the paste: the target app handles
    /// ⌘V asynchronously, and the injector restores the clipboard at 0.25 s.
    nonisolated static let settleDelay: TimeInterval = 0.4
    nonisolated static let pollInterval: TimeInterval = 1
    nonisolated static let maxDuration: TimeInterval = 60
    nonisolated static let anchorLength = 16
    /// After asking an Electron app for its accessibility, Chromium builds
    /// its tree asynchronously: look again after each of these delays.
    nonisolated static let retryDelays: [TimeInterval] = [0.15, 0.3, 0.5, 0.8, 1, 1, 1, 1]

    private struct Watch {
        let file: URL
        let model: String
        let pasted: String
        let raw: String?
        let pid: pid_t?
        let element: FocusedElement
        let app: String?
        let before: String
        let after: String
        /// Where the span started in the field, in UTF-16 units: the
        /// occurrence of `before` closest to it is the one followed.
        let location: Int
        let started: Date
        var span: String
    }

    private var watch: Watch?
    private var timer: Timer?
    /// Apps whose `AXManualAccessibility` Parrot turned on. They stay on until
    /// Parrot quits: bb took ~2.75 s to expose its focused field after each
    /// request (fork-005), so turning it off after each watch made every
    /// dictation pay that again.
    private var accessibilityOn: Set<pid_t> = []
    private var quitObserver: NSObjectProtocol?

    private init() {
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { CorrectionWatch.shared.restoreAccessibility() }
        }
    }
    /// Bumped by every `start` and `finish`, so a delayed lookup only starts
    /// the watch it was scheduled for.
    private var generation = 0

    /// Starts watching `pasted`, delivered for the recording `file`. Ends any
    /// watch still running first.
    func start(pasted: String, raw: String?, file: URL, model: String) {
        finish()
        let generation = self.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.locate(pasted: pasted, raw: raw, file: file, model: model)
            }
        }
    }

    /// Ends the watch with one last look at the field, and writes its record.
    func finish() {
        guard var watch = stop() else { return }
        if let span = currentSpan(of: watch) { watch.span = span }
        write(watch)
    }

    /// Cancels the timer and any pending lookup; returns the watch it ended.
    private func stop() -> Watch? {
        generation += 1
        timer?.invalidate()
        timer = nil
        defer { watch = nil }
        return watch
    }

    // MARK: -

    /// `attempt` counts the looks taken after asking an Electron app for its
    /// accessibility.
    private func locate(pasted: String, raw: String?, file: URL, model: String, attempt: Int = 0) {
        let focus = Self.focus()
        let app = focus.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        // Which step failed, for the log: never text, only sizes and AX codes.
        func unreadable(_ reason: String) {
            Log.info("  corpus: \(app ?? "unknown app"): \(reason)")
            Self.write(CorrectionRecord(model: model, app: app, pasted: pasted, final: nil, status: .unreadable, watched: 0, raw: raw), to: file)
        }
        guard let element = focus.element else {
            // Diagnostic (fork-005): when, and through which query, the app
            // answers. AX codes only.
            if let pid = focus.pid { Log.info("  corpus: attempt \(attempt): \(Self.focusErrors(pid))") }
            if attempt == 0, let pid = focus.pid, Self.enableAccessibility(of: pid) {
                accessibilityOn.insert(pid)
            }
            guard focus.pid.map(accessibilityOn.contains) == true, attempt < Self.retryDelays.count else {
                return unreadable("no focused element\(attempt > 0 ? " after \(attempt) retries" : "")")
            }
            let generation = self.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.locate(pasted: pasted, raw: raw, file: file, model: model, attempt: attempt + 1)
                }
            }
            return
        }
        if attempt > 0 { Log.info("  corpus: \(app ?? "unknown app"): accessibility on after \(attempt) retries") }
        guard !element.isSecure() else { return unreadable("secure field") }
        guard let value = element.value() else { return unreadable("value unreadable (\(element.valueError()))") }
        let cursor = element.cursor()
        guard let range = Self.locate(pasted, in: value, cursor: cursor) else {
            return unreadable("pasted text (\((pasted as NSString).length) units) not found in \((value as NSString).length) units, cursor \(cursor.map(String.init) ?? "unknown"), \(element.describe())")
        }
        let anchors = Self.anchors(around: range, in: value)
        watch = Watch(
            file: file, model: model, pasted: pasted, raw: raw, pid: focus.pid, element: element, app: app,
            before: anchors.before, after: anchors.after,
            location: range.lowerBound, started: Date(), span: pasted
        )
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard let watch else { return }
        let focus = Self.focus()
        guard focus.pid == watch.pid, focus.element == watch.element else {
            // Focus left the field: its text may be gone (a sent message), so
            // the span from the last look stands.
            _ = stop()
            write(watch)
            return
        }
        if let span = currentSpan(of: watch) { self.watch?.span = span }
        if Date().timeIntervalSince(watch.started) >= Self.maxDuration { finish() }
    }

    /// The span between the anchors in the field now, or nil when the field
    /// can't be read or an anchor is gone (a sent message, a cleared field).
    private func currentSpan(of watch: Watch) -> String? {
        guard let value = watch.element.value() else { return nil }
        // An empty field may read as its placeholder (bb: "Ask for a
        // follow-up…" once a message is sent): nothing to follow there.
        if value == watch.element.placeholder() { return nil }
        guard let span = Self.span(in: value, before: watch.before, after: watch.after, near: watch.location) else { return nil }
        // A dictation that filled its field, read back sharing no word with
        // the paste: the field was emptied and shows its hint as its value
        // (bb reports "Ask for a follow-up…" as AXValue, with no
        // AXPlaceholderValue), not a correction.
        if watch.before.isEmpty, watch.after.isEmpty, Self.sharesNoWord(span, watch.pasted) { return nil }
        return span
    }

    /// The frontmost app and its focused element: asked system-wide, then of
    /// the app itself, which is the only way some Electron apps answer.
    private static func focus() -> (pid: pid_t?, element: FocusedElement?) {
        let snapshot = FocusSnapshot.capture()
        guard snapshot.element == nil, let pid = snapshot.pid else { return (snapshot.pid, snapshot.element) }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return (pid, nil) }
        return (pid, FocusedElement(value as! AXUIElement))
    }

    /// The AX codes of the system-wide and the app's focused-element queries.
    private static func focusErrors(_ pid: pid_t) -> String {
        var value: CFTypeRef?
        let system = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value)
        let app = AXUIElementCreateApplication(pid)
        let own = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        let window = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        return "system \(system.rawValue) · app \(own.rawValue) · window \(window.rawValue)"
    }

    /// Turns on `pid`'s Electron accessibility; false when it was on already
    /// (another assistive tool's, left alone) or the app doesn't take it.
    private static func enableAccessibility(of pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var current: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, manualAccessibilityAttribute, &current) == .success,
           (current as? Bool) == true {
            return false
        }
        let status = AXUIElementSetAttributeValue(app, manualAccessibilityAttribute, kCFBooleanTrue)
        Log.info("  corpus: asked for accessibility (AX \(status.rawValue))")
        return status == .success
    }

    /// Turns off what Parrot turned on, when it quits.
    private func restoreAccessibility() {
        for pid in accessibilityOn {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), Self.manualAccessibilityAttribute, kCFBooleanFalse)
        }
        accessibilityOn = []
    }

    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString

    private func write(_ watch: Watch) {
        let status: CorrectionRecord.Status = watch.span == watch.pasted ? .unchanged : .edited
        let record = CorrectionRecord(
            model: watch.model, app: watch.app, pasted: watch.pasted, final: watch.span,
            status: status, watched: (Date().timeIntervalSince(watch.started) * 10).rounded() / 10, raw: watch.raw
        )
        Self.write(record, to: watch.file)
    }

    private static func write(_ record: CorrectionRecord, to file: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(record)
            let url = try Paths.preparePrivateFile(file)
            try data.write(to: url)
            // The status only: the log never carries text.
            Log.info("  corpus: correction \(record.status.rawValue) after \(record.watched)s")
        } catch {
            Log.error("  corpus: could not write the correction: \(error)")
        }
    }

    // MARK: - Pure, so they are tested

    /// The UTF-16 range of `pasted` in `value`: the occurrence ending closest
    /// to the cursor (the paste leaves the cursor at its end, plus the
    /// trailing space `Spacing` adds), or the only one without a cursor.
    nonisolated static func locate(_ pasted: String, in value: String, cursor: Int?) -> Range<Int>? {
        let needle = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let haystack = value as NSString
        var found: [Range<Int>] = []
        var from = 0
        while from < haystack.length {
            let hit = haystack.range(of: needle, options: [], range: NSRange(location: from, length: haystack.length - from))
            guard hit.location != NSNotFound else { break }
            found.append(hit.location..<(hit.location + hit.length))
            from = hit.location + 1
        }
        guard let cursor else { return found.count == 1 ? found[0] : nil }
        return found.min { abs($0.upperBound - cursor) < abs($1.upperBound - cursor) }
    }

    /// True when `a` and `b` have no word of three letters or more in common.
    nonisolated static func sharesNoWord(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 })
        }
        return words(a).isDisjoint(with: words(b))
    }

    /// Up to `anchorLength` characters each side of `range`. Whitespace alone
    /// is no landmark — the space `Spacing` adds after a paste at the end of
    /// a field would match the first space inside the span — so an anchor
    /// that is only whitespace becomes empty: the start or end of the field.
    nonisolated static func anchors(around range: Range<Int>, in value: String) -> (before: String, after: String) {
        let text = value as NSString
        let beforeLength = min(anchorLength, range.lowerBound)
        let afterLength = min(anchorLength, text.length - range.upperBound)
        let before = text.substring(with: NSRange(location: range.lowerBound - beforeLength, length: beforeLength))
        let after = text.substring(with: NSRange(location: range.upperBound, length: afterLength))
        func landmark(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : s }
        return (landmark(before), landmark(after))
    }

    /// The text between `before` and `after` in `value`, taking the
    /// occurrence of `before` that ends closest to `location` (UTF-16). An
    /// empty anchor is the start or the end of the field.
    nonisolated static func span(in value: String, before: String, after: String, near location: Int) -> String? {
        let text = value as NSString
        var start = 0
        if !before.isEmpty {
            var ends: [Int] = []
            var from = 0
            while from < text.length {
                let hit = text.range(of: before, options: [], range: NSRange(location: from, length: text.length - from))
                guard hit.location != NSNotFound else { break }
                ends.append(hit.location + hit.length)
                from = hit.location + 1
            }
            guard let nearest = ends.min(by: { abs($0 - location) < abs($1 - location) }) else { return nil }
            start = nearest
        }
        var end = text.length
        if !after.isEmpty {
            let hit = text.range(of: after, options: [], range: NSRange(location: start, length: text.length - start))
            guard hit.location != NSNotFound else { return nil }
            end = hit.location
        }
        let span = text.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An emptied span is a sent message or a cleared field, not an edit.
        return span.isEmpty ? nil : span
    }
}

extension FocusedElement {
    /// The field's whole text, or nil when the app doesn't expose it. Call
    /// after `FocusSnapshot.capture()`, which sets the timeout.
    func value() -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// A password field, by its subrole. Electron's fields may answer only
    /// once their app's accessibility is on, after `FocusSnapshot` looked.
    func isSecure() -> Bool {
        var subrole: CFTypeRef?
        return AXUIElementCopyAttributeValue(ref, kAXSubroleAttribute as CFString, &subrole) == .success
            && (subrole as? String) == kAXSecureTextFieldSubrole as String
    }

    /// Role, subrole, placeholder length and character count, for the log:
    /// never text.
    func describe() -> String {
        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ref, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }
        var count: CFTypeRef?
        AXUIElementCopyAttributeValue(ref, kAXNumberOfCharactersAttribute as CFString, &count)
        return "role \(string(kAXRoleAttribute) ?? "?")/\(string(kAXSubroleAttribute) ?? "?")"
            + " · placeholder \(string(kAXPlaceholderValueAttribute).map { "\(($0 as NSString).length)" } ?? "none")"
            + " · characters \((count as? Int).map(String.init) ?? "?")"
    }

    /// The AX error and role when `value()` fails, for the log.
    func valueError() -> String {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(ref, kAXValueAttribute as CFString, &value)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(ref, kAXRoleAttribute as CFString, &role)
        return "AX \(status.rawValue), role \(role as? String ?? "unknown"), \(value.map { String(describing: CFGetTypeID($0)) } ?? "no value")"
    }

    /// The hint an empty field shows, if it has one.
    func placeholder() -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXPlaceholderValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// The insertion point in UTF-16 units, or nil when unknown.
    func cursor() -> Int? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        return range.location
    }
}
