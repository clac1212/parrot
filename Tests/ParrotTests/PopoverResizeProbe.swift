import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

/// Diagnostic: does NSPopover animate a contentSize change, and how?
/// Run with PANEL_ANIMATION=1.
final class PopoverResizeProbe: XCTestCase {
    @MainActor
    func testContentSizeAnimation() throws {
        guard ProcessInfo.processInfo.environment["PANEL_ANIMATION"] != nil else { throw XCTSkip("no PANEL_ANIMATION") }
        NSApplication.shared.setActivationPolicy(.accessory)
        let anchor = NSWindow(contentRect: NSRect(x: 400, y: 900, width: 60, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        anchor.orderFrontRegardless()
        let popover = NSPopover()
        let hosting = NSHostingController(rootView: Color.gray.frame(maxWidth: .infinity, maxHeight: .infinity))
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 360, height: 400)
        popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        func run(_ label: String, _ change: () -> Void) {
            let window = hosting.view.window!
            change()
            let start = Date()
            var line: [String] = []
            while Date().timeIntervalSince(start) < 0.45 {
                line.append(String(format: "%.0f", window.frame.height))
                RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 60))
            }
            print("PROBE \(label): " + line.joined(separator: " ") + String(format: " | top=%.0f", window.frame.maxY))
        }
        run("plain set 600") { popover.contentSize = NSSize(width: 360, height: 600) }
        run("window animate 400") {
            // Resize the popover's window ourselves, top edge fixed.
            let window = hosting.view.window!
            var frame = window.frame
            frame.origin.y += frame.height - 426
            frame.size.height = 426
            window.setFrame(frame, display: true, animate: true)
        }
        run("context 600") {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                popover.contentSize = NSSize(width: 360, height: 600)
            }
        }
        popover.close()
    }
}
