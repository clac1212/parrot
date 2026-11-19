import AppKit
import SwiftUI

/// What the notch shows of the pending corrections (fork-019), and when.
///
/// - **Live**: a correction just made comes out of the notch as one row,
///   with Ajouter and ✕, « +2 » when others wait, and a bar that drains in
///   `duration`. Answered, the next one of the same edit follows; timed out,
///   it stays pending.
/// - **All**: the pointer on what is shown or on the notch above it, or
///   resting on the notch (`hoverDelay`) when nothing is shown, unfolds
///   every pending correction under that first row, which stays where it
///   was, with « Tout ajouter » and « Tout refuser ». It folds `listGrace`
///   after the pointer left the notch and the rows. The user's design: an
///   overview, not one at a time (2026-11-19).
///
/// While something is shown, one test decides where the pointer is: the
/// notch and the rows as one rectangle, read `trackInterval` apart
/// (`track`). A first version had two — SwiftUI's hover on the rows, and the
/// notch's monitor only when nothing was shown — so the pointer on the notch
/// did nothing during a live offer, then unfolded everything the moment it
/// timed out (seen by the user, 2026-11-19).
///
/// A dictation always wins: it takes the notch back, and what was shown
/// stays pending. `NotchOverlay` does the showing; this decides.
@MainActor
final class NotchOffers: ObservableObject {
    enum Mode: Equatable {
        case none
        case live(PendingCorrections.Item)
        case all
    }

    /// The user found 8 s long (2026-11-19).
    nonisolated static let duration: TimeInterval = 5
    nonisolated static let hoverDelay: TimeInterval = 0.3
    /// Before the list folds once the pointer left it.
    nonisolated static let listGrace: TimeInterval = 0.5
    /// Rows the notch shows; the panel lists the rest.
    nonisolated static let maxRows = 6
    nonisolated static let trackInterval: TimeInterval = 0.05

    @Published private(set) var mode: Mode = .none
    /// When the live offer's bar runs out.
    @Published private(set) var endsAt: Date?
    /// Black notch (white text) or a floating card (system colours).
    @Published var onNotch = true

    let pending: PendingCorrections
    /// Shows the expanded notch, clickable; hides it.
    var present: () -> Void = {}
    var dismiss: () -> Void = {}
    /// A dictation is under way: nothing comes out of the notch.
    var isBusy: () -> Bool = { false }

    /// Whether the pointer is on the notch or what it shows; read while
    /// something is shown. Tests set it; the app's reads the screen.
    var pointerInside: () -> Bool = { false }
    /// The view that shows the rows, for `pointerInside`.
    weak var content: NSView?

    /// The live offers still to come from the latest edit.
    private var batch: [UUID] = []
    private var generation = 0
    /// Since when the pointer has been away from the list.
    private var outsideSince: Date?
    private var tracker: Timer?
    private let now: () -> Date

    /// `nil`: the app's queue (a default argument can't read it off the main actor).
    init(pending: PendingCorrections? = nil, now: @escaping () -> Date = Date.init) {
        self.pending = pending ?? .shared
        self.now = now
    }

    /// Corrections just queued: the newest comes out live.
    func offer(_ items: [PendingCorrections.Item]) {
        guard !items.isEmpty else { return }
        // Diagnostic (2026-11-19): an offer the user didn't see come out.
        guard !isBusy() else { return Log.info("  notch: offer kept pending, a dictation is under way") }
        batch = items.map(\.id)
        showNextLive()
    }

    /// The pointer rested on the notch.
    func pointerOnNotch() {
        pending.prune()
        guard mode == .none, !pending.items.isEmpty, !isBusy() else { return }
        generation += 1
        outsideSince = nil
        mode = .all
        Log.info("  notch: list unfolded (pointer on the notch)")
        present()
        startTracking()
    }

    func answer(_ item: PendingCorrections.Item, accepted: Bool) {
        pending.answer(item, accepted: accepted)
        switch mode {
        case .live: showNextLive()
        case .all where pending.items.isEmpty: close(because: "all answered")
        default: break
        }
    }

    /// « Tout ajouter » / « Tout refuser ».
    func answerAll(accepted: Bool) {
        for item in pending.items { pending.answer(item, accepted: accepted) }
        close(because: "all answered")
    }

    /// Where the pointer is, read `trackInterval` apart while something is
    /// shown. On a live offer it unfolds the list; away from the list for
    /// `listGrace`, the list folds.
    func track(inside: Bool) {
        switch mode {
        case .live where inside:
            // Unfold everything under the live row; no more countdown.
            generation += 1
            batch = []
            endsAt = nil
            outsideSince = nil
            mode = .all
            Log.info("  notch: list unfolded (pointer on the offer)")
        case .all where inside:
            outsideSince = nil
        case .all:
            let t = now()
            guard let since = outsideSince else { outsideSince = t; return }
            if t.timeIntervalSince(since) >= Self.listGrace { close(because: "pointer left") }
        default: break
        }
    }

    /// A dictation started: give the notch back; everything stays pending.
    func yield() {
        generation += 1
        batch = []
        if mode != .none { Log.info("  notch: corrections folded (dictation)") }
        mode = .none
        endsAt = nil
        stopTracking()
    }

    /// The rows to show: the live one alone, or all, the live one first.
    var rows: [PendingCorrections.Item] {
        switch mode {
        case .none: return []
        case .live(let item): return [item]
        case .all: return Array(pending.items.prefix(Self.maxRows))
        }
    }

    /// Pending beyond the rows shown.
    var hidden: Int { max(0, pending.items.count - rows.count) }

    /// The bar's fill, 1 → 0.
    func fraction(at date: Date) -> Double {
        guard let endsAt else { return 0 }
        return min(1, max(0, endsAt.timeIntervalSince(date) / Self.duration))
    }

    private func showNextLive() {
        while let id = batch.first {
            batch.removeFirst()
            if let item = pending.items.first(where: { $0.id == id }) {
                // On top, so it stays the first row once everything unfolds.
                pending.raise(item)
                mode = .live(item)
                endsAt = now().addingTimeInterval(Self.duration)
                closeLater(after: Self.duration)
                present()
                startTracking()
                return
            }
        }
        close(because: "answered")
    }

    private func closeLater(after delay: TimeInterval) {
        generation += 1
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.close(because: "timed out")
            }
        }
    }

    /// `reason` for the log: what folded the notch, never what it showed.
    private func close(because reason: String) {
        generation += 1
        batch = []
        stopTracking()
        guard mode != .none else { return }
        mode = .none
        endsAt = nil
        Log.info("  notch: corrections folded (\(reason))")
        dismiss()
    }

    private func startTracking() {
        guard tracker == nil else { return }
        let timer = Timer(timeInterval: Self.trackInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.track(inside: self.pointerInside())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tracker = timer
    }

    private func stopTracking() {
        tracker?.invalidate()
        tracker = nil
        outsideSince = nil
    }

    /// The notch and the rows as one rectangle, with a few points of slack:
    /// the black between them counts as on it.
    func pointerOnShown() -> Bool {
        guard let view = content, let window = view.window else { return false }
        let rows = window.convertToScreen(view.convert(view.bounds, to: nil))
        let notch = NSScreen.screens.first { $0.frame.intersects(rows) }.flatMap(NotchHover.notchRect(of:))
        return (notch.map { rows.union($0) } ?? rows).insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }
}

// MARK: - Views

/// The notch's expanded content: a message (fork-013), or the corrections —
/// one view for live and all, so the first row stays put when it unfolds.
struct NotchExpandedView: View {
    @ObservedObject var clock: NotchClock
    @ObservedObject var offers: NotchOffers

    var body: some View {
        if offers.mode == .none {
            NotchMessageView(clock: clock)
        } else {
            FirstClick(scheme: offers.onNotch ? .dark : nil, register: { offers.content = $0 }) {
                CorrectionsView(offers: offers)
            }
        }
    }
}

struct CorrectionsView: View {
    @ObservedObject var offers: NotchOffers
    @ObservedObject private var pending: PendingCorrections

    init(offers: NotchOffers) {
        self.offers = offers
        pending = offers.pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(offers.rows) { item in
                PendingCorrectionRow(item: item, more: offers.mode == .all ? 0 : offers.hidden) {
                    offers.answer(item, accepted: $0)
                }
            }
            if offers.mode == .all {
                if offers.hidden > 0 {
                    Text("et \(offers.hidden) autres dans le panneau de Parrot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if pending.items.count > 1 {
                    AnswerAllButtons { offers.answerAll(accepted: $0) }
                        .padding(.top, 2)
                }
            } else {
                TimelineView(.animation(paused: offers.endsAt == nil)) { context in
                    GeometryReader { geometry in
                        Capsule().fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule().fill(.secondary)
                                    .frame(width: geometry.size.width * offers.fraction(at: context.date))
                            }
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(minWidth: 320, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

/// One pending correction with Ajouter and ✕: the notch and the panel.
/// `more`: « +2 » after the pair, when it stands for others.
struct PendingCorrectionRow: View {
    let item: PendingCorrections.Item
    var more = 0
    let answer: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            CorrectionPair(item: item)
            if more > 0 {
                Text("+\(more)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Ajouter") { answer(true) }
                .panelButton(prominent: true)
            RefuseButton { answer(false) }
        }
    }
}

/// « Tout ajouter » and « Tout refuser », under several pending corrections.
struct AnswerAllButtons: View {
    let answer: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Tout refuser") { answer(false) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("Tout ajouter") { answer(true) }
                .panelButton()
        }
        .font(.callout)
    }
}

/// « ~~pip~~ → Peep »
struct CorrectionPair: View {
    let item: PendingCorrections.Item

    var body: some View {
        HStack(spacing: 5) {
            Text(item.wrong).strikethrough().foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            Text(item.right).fontWeight(.semibold)
        }
        .lineLimit(1)
    }
}

private struct RefuseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Ne jamais ajouter")
    }
}

/// Hosts `content` in a view that takes the first click: the notch's window
/// never becomes key (the field being corrected keeps the keyboard), and
/// DynamicNotchKit's hosting view spends a first click on an inactive window
/// (`acceptsFirstMouse` is false, probed 2026-11-19). The colour scheme is
/// passed by hand: a nested hosting view doesn't inherit the environment.
struct FirstClick<Content: View>: NSViewRepresentable {
    let scheme: ColorScheme?
    /// Hears the hosting view once made, to find it on screen.
    var register: (NSView) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> FirstClickHostingView<AnyView> {
        let view = FirstClickHostingView(rootView: root)
        view.sizingOptions = [.intrinsicContentSize]
        register(view)
        return view
    }

    func updateNSView(_ view: FirstClickHostingView<AnyView>, context: Context) {
        view.rootView = root
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FirstClickHostingView<AnyView>, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    private var root: AnyView {
        if let scheme { AnyView(content().environment(\.colorScheme, scheme)) } else { AnyView(content()) }
    }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Watches the pointer over the notch while nothing is shown: a global
/// monitor (mouse moves in other apps; no permission needed for the mouse),
/// a test against the notch's rectangle, and a short dwell.
@MainActor
final class NotchHover {
    private var monitor: Any?
    private var inside = false
    private var generation = 0
    private let onRest: () -> Void
    private let wanted: () -> Bool

    /// `wanted` is asked at each move: no pending correction, no test.
    init(wanted: @escaping () -> Bool, onRest: @escaping () -> Void) {
        self.wanted = wanted
        self.onRest = onRest
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }
    }

    private func moved() {
        guard wanted() else { inside = false; return }
        let now = Self.isOnNotch(NSEvent.mouseLocation)
        guard now != inside else { return }
        inside = now
        generation += 1
        guard now else { return }
        let entered = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchOffers.hoverDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == entered, self.inside else { return }
                self.onRest()
            }
        }
    }

    /// The point lies on a screen's notch (a few points of slack each side).
    static func isOnNotch(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { notchRect(of: $0)?.insetBy(dx: -6, dy: 0).contains(point) == true }
    }

    /// The notch of `screen`, in screen coordinates; nil without one.
    static func notchRect(of screen: NSScreen) -> NSRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        let height = screen.safeAreaInsets.top
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}

/// The pending corrections in the menu-bar panel's Dictée card, under
/// Dictionnaire (fork-019): the place that works on every Mac, notch or
/// not. Nothing when none is pending.
struct PendingCorrectionsRows: View {
    @ObservedObject var pending: PendingCorrections

    var body: some View {
        ForEach(pending.items.prefix(5)) { item in
            PanelDivider()
            PendingCorrectionRow(item: item) { pending.answer(item, accepted: $0) }
                .padding(.leading, PanelStyle.textLeading)
                .padding(.trailing, 10)
                .frame(minHeight: PanelStyle.rowHeight)
        }
        if pending.items.count > 1 {
            AnswerAllButtons { accepted in
                for item in pending.items { pending.answer(item, accepted: accepted) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }
}
