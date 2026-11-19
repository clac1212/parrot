import AppKit
import DynamicNotchKit
import SwiftUI
import XCTest
@testable import ParrotCore

/// Diagnostic, not a regression test (fork-019): opens a correction in the
/// real notch from an app that is not active, as Parrot is when the user
/// edits text elsewhere, and prints the window's and the nested hosting
/// view's sizes over time. Run with NOTCH_PROBE=1.
final class NotchOfferProbe: XCTestCase {
    @MainActor
    func testTheOfferHasASizeWhileInactive() async throws {
        guard ProcessInfo.processInfo.environment["NOTCH_PROBE"] != nil else { throw XCTSkip("no NOTCH_PROBE") }
        NSApplication.shared.setActivationPolicy(.accessory)
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        let clock = NotchClock()
        let notch = DynamicNotch(hoverBehavior: []) {
            NotchExpandedView(clock: clock, offers: offers)
        } compactLeading: { EmptyView() } compactTrailing: { EmptyView() }
        offers.offer(pending.add([.init(wrong: "pip", right: "Peep")]))
        print("probe: app active \(NSApp.isActive)")
        let screen = try XCTUnwrap(NSScreen.main)
        Task { await notch.expand(on: screen) }

        func firstClick(in view: NSView) -> NSView? {
            if String(describing: type(of: view)).hasPrefix("FirstClickHostingView") { return view }
            for sub in view.subviews { if let found = firstClick(in: sub) { return found } }
            return nil
        }
        for step in 0..<8 {
            try await Task.sleep(for: .milliseconds(250))
            let window = notch.windowController?.window
            let nested = window?.contentView.flatMap(firstClick)
            print("probe: t=\(step * 250) ms · window \(window.map { "\($0.frame.size)" } ?? "none") visible \(window?.isVisible ?? false) alpha \(window?.alphaValue ?? 0)"
                + " · nested \(nested.map { "frame \($0.frame.size) fitting \($0.fittingSize)" } ?? "not found")")
        }
        await notch.hide()
    }
}
