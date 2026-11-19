import AppKit
import SwiftUI

/// What the notch shows of the pending corrections (fork-019), and when.
///
/// - **Live**: a correction just made comes out of the notch with Ajouter
///   and ✕, and a bar that drains in `duration`, held while the pointer is
///   over it. Answered, the next one of the same edit follows; timed out, it
///   stays pending.
/// - **List**: the pointer resting on the notch (`hoverDelay`) when nothing
///   else is shown opens every pending correction, each with ✓ and ✕; it
///   folds when the pointer leaves.
///
/// A dictation always wins: it takes the notch back, and what was shown
/// stays pending. `NotchOverlay` does the showing; this decides.
@MainActor
final class NotchOffers: ObservableObject {
    enum Mode: Equatable {
        case none
        case live(PendingCorrections.Item)
        case list
    }

    nonisolated static let duration: TimeInterval = 8
    /// Left after the pointer leaves a live offer.
    nonisolated static let linger: TimeInterval = 3
    nonisolated static let hoverDelay: TimeInterval = 0.3
    /// Before the list folds once the pointer left it.
    nonisolated static let listGrace: TimeInterval = 0.5

    @Published private(set) var mode: Mode = .none
    /// The live offer's bar: when it runs out, or the time left while held.
    @Published private(set) var endsAt: Date?
    @Published private(set) var heldRemaining: TimeInterval = duration
    /// Black notch (white text) or a floating card (system colours).
    @Published var onNotch = true

    let pending: PendingCorrections
    /// Shows the expanded notch, clickable; hides it.
    var present: () -> Void = {}
    var dismiss: () -> Void = {}
    /// A dictation is under way: nothing comes out of the notch.
    var isBusy: () -> Bool = { false }

    /// The live offers still to come from the latest edit.
    private var batch: [UUID] = []
    private var generation = 0

    /// `nil`: the app's queue (a default argument can't read it off the main actor).
    init(pending: PendingCorrections? = nil) {
        self.pending = pending ?? .shared
    }

    /// Corrections just queued: the newest comes out live.
    func offer(_ items: [PendingCorrections.Item]) {
        guard !items.isEmpty, !isBusy() else { return }
        batch = items.map(\.id)
        showNextLive()
    }

    /// The pointer rested on the notch.
    func pointerOnNotch() {
        pending.prune()
        guard mode == .none, !pending.items.isEmpty, !isBusy() else { return }
        generation += 1
        mode = .list
        present()
    }

    func answer(_ item: PendingCorrections.Item, accepted: Bool) {
        pending.answer(item, accepted: accepted)
        switch mode {
        case .live: showNextLive()
        case .list where pending.items.isEmpty: close()
        default: break
        }
    }

    /// The pointer entered or left what the notch shows.
    func hover(_ inside: Bool) {
        generation += 1
        switch mode {
        case .live:
            if inside {
                if let endsAt { heldRemaining = max(0, endsAt.timeIntervalSinceNow) }
                endsAt = nil
            } else {
                heldRemaining = max(heldRemaining, Self.linger)
                run(for: heldRemaining)
            }
        case .list where !inside:
            closeLater(after: Self.listGrace)
        default: break
        }
    }

    /// A dictation started: give the notch back; everything stays pending.
    func yield() {
        generation += 1
        batch = []
        mode = .none
        endsAt = nil
    }

    var morePending: Int {
        guard case .live(let item) = mode else { return 0 }
        return pending.items.filter { $0.id != item.id }.count
    }

    /// The bar's fill, 1 → 0.
    func fraction(at date: Date) -> Double {
        let left = endsAt.map { $0.timeIntervalSince(date) } ?? heldRemaining
        return min(1, max(0, left / Self.duration))
    }

    private func showNextLive() {
        while let id = batch.first {
            batch.removeFirst()
            if let item = pending.items.first(where: { $0.id == id }) {
                mode = .live(item)
                heldRemaining = Self.duration
                run(for: Self.duration)
                present()
                return
            }
        }
        close()
    }

    private func run(for seconds: TimeInterval) {
        endsAt = Date().addingTimeInterval(seconds)
        closeLater(after: seconds)
    }

    private func closeLater(after delay: TimeInterval) {
        generation += 1
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.close()
            }
        }
    }

    private func close() {
        generation += 1
        batch = []
        guard mode != .none else { return }
        mode = .none
        endsAt = nil
        dismiss()
    }
}

// MARK: - Views

/// The notch's expanded content: a message (fork-013), or the corrections.
struct NotchExpandedView: View {
    @ObservedObject var clock: NotchClock
    @ObservedObject var offers: NotchOffers

    var body: some View {
        switch offers.mode {
        case .none:
            NotchMessageView(clock: clock)
        case .live(let item):
            FirstClick(scheme: offers.onNotch ? .dark : nil) {
                LiveOfferView(item: item, offers: offers)
            }
        case .list:
            FirstClick(scheme: offers.onNotch ? .dark : nil) {
                PendingListView(offers: offers)
            }
        }
    }
}

struct LiveOfferView: View {
    let item: PendingCorrections.Item
    @ObservedObject var offers: NotchOffers

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CorrectionPair(item: item)
                if offers.morePending > 0 {
                    Text("+\(offers.morePending)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Ajouter") { offers.answer(item, accepted: true) }
                    .panelButton(prominent: true)
                RefuseButton { offers.answer(item, accepted: false) }
            }
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
        .frame(minWidth: 300)
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .onHover { offers.hover($0) }
    }
}

struct PendingListView: View {
    @ObservedObject var offers: NotchOffers
    @ObservedObject private var pending: PendingCorrections

    init(offers: NotchOffers) {
        self.offers = offers
        pending = offers.pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ajouter au dictionnaire ?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(pending.items.prefix(6)) { item in
                PendingCorrectionRow(item: item) { offers.answer(item, accepted: $0) }
            }
            if pending.items.count > 6 {
                Text("et \(pending.items.count - 6) autres dans le panneau de Parrot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 300, alignment: .leading)
        .padding(.horizontal, 6)
        .onHover { offers.hover($0) }
    }
}

/// One pending correction with ✓ and ✕: the notch's list and the panel.
struct PendingCorrectionRow: View {
    let item: PendingCorrections.Item
    let answer: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            CorrectionPair(item: item)
            Spacer(minLength: 12)
            Button { answer(true) } label: {
                Image(systemName: "checkmark").font(.caption.weight(.bold))
            }
            .panelButton(prominent: true)
            .help("Ajouter au dictionnaire")
            RefuseButton { answer(false) }
        }
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
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> FirstClickHostingView<AnyView> {
        let view = FirstClickHostingView(rootView: root)
        view.sizingOptions = [.intrinsicContentSize]
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
        NSScreen.screens.contains { screen in
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
            let width = screen.frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            let notch = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
            return notch.insetBy(dx: -6, dy: 0).contains(point)
        }
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
    }
}
