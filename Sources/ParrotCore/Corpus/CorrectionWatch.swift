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
}

/// Watches the span a transcript was pasted into until the user leaves the
/// field, dictates again, or a minute passes, then writes a `CorrectionRecord`.
/// Read-only over Accessibility: it never sets an attribute on the target app.
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

    private struct Watch {
        let file: URL
        let model: String
        let pasted: String
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
    /// Bumped by every `start` and `finish`, so a delayed lookup only starts
    /// the watch it was scheduled for.
    private var generation = 0

    /// Starts watching `pasted`, delivered for the recording `file`. Ends any
    /// watch still running first.
    func start(pasted: String, file: URL, model: String) {
        finish()
        let generation = self.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.locate(pasted: pasted, file: file, model: model)
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

    private func locate(pasted: String, file: URL, model: String) {
        let focus = FocusSnapshot.capture()
        let app = focus.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        guard let element = focus.element, !focus.isSecure,
              let value = element.value(),
              let range = Self.locate(pasted, in: value, cursor: element.cursor())
        else {
            Self.write(CorrectionRecord(model: model, app: app, pasted: pasted, final: nil, status: .unreadable, watched: 0), to: file)
            return
        }
        let text = value as NSString
        let beforeLength = min(Self.anchorLength, range.lowerBound)
        let afterLength = min(Self.anchorLength, text.length - range.upperBound)
        watch = Watch(
            file: file, model: model, pasted: pasted, pid: focus.pid, element: element, app: app,
            before: text.substring(with: NSRange(location: range.lowerBound - beforeLength, length: beforeLength)),
            after: text.substring(with: NSRange(location: range.upperBound, length: afterLength)),
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
        let focus = FocusSnapshot.capture()
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
        return Self.span(in: value, before: watch.before, after: watch.after, near: watch.location)
    }

    private func write(_ watch: Watch) {
        let status: CorrectionRecord.Status = watch.span == watch.pasted ? .unchanged : .edited
        let record = CorrectionRecord(
            model: watch.model, app: watch.app, pasted: watch.pasted, final: watch.span,
            status: status, watched: (Date().timeIntervalSince(watch.started) * 10).rounded() / 10
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
        return text.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
