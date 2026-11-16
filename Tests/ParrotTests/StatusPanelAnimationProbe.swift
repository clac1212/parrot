import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

/// Diagnostic, not a regression test: shows the real panel in its
/// `MenuBarPanel` on screen, unfolds the history, and samples at 60 Hz where the popover
/// window is and where the header's text is (its accessibility frame, in
/// screen points). Run with PANEL_ANIMATION=1; prints a table.
final class StatusPanelAnimationProbe: XCTestCase {
    @MainActor
    func testUnfoldMotion() throws {
        guard ProcessInfo.processInfo.environment["PANEL_ANIMATION"] != nil else { throw XCTSkip("no PANEL_ANIMATION") }
        NSApplication.shared.setActivationPolicy(.accessory)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let history = DictationHistory(file: dir.appendingPathComponent("history.json"))
        for i in 0..<8 { history.add("Dictée \(i), assez longue pour tenir sur deux lignes dans le panneau.", at: Date().addingTimeInterval(-Double(i) * 60)) }
        let store = SettingsStore(file: dir.appendingPathComponent("settings.json"))
        let model = StatusPanelModel(store: store, history: history)
        model.status = "Prêt · maintiens fn pour dicter"
        model.modelLine = "Parakeet Ultra"

        let hosting = StatusPopover.hosting(StatusPanelView(model: model))
        let panel = MenuBarPanel(content: hosting)
        NSApp.activate(ignoringOtherApps: true)
        panel.show(under: NSRect(x: 400, y: NSScreen.main!.frame.maxY - 24, width: 30, height: 24))
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        func headerFrame() -> NSRect? {
            func find(_ element: Any) -> NSRect? {
                if let e = element as? NSAccessibilityElementProtocol, let label = (e as AnyObject).accessibilityLabel?() ?? nil,
                   label.hasPrefix("Prêt") { return (e as AnyObject).accessibilityFrame() }
                if let e = element as? NSObject, let value = e.value(forKey: "accessibilityLabel") as? String, value.hasPrefix("Prêt"),
                   let frame = e.value(forKey: "accessibilityFrame") as? NSRect { return frame }
                for child in ((element as? NSObject)?.value(forKey: "accessibilityChildren") as? [Any]) ?? [] {
                    if let f = find(child) { return f }
                }
                return nil
            }
            return find(hosting.view)
        }
        _ = headerFrame
        /// The rendered layers: their presentation (on-screen, mid-animation)
        /// frames, two levels deep, in the hosting view's coordinates.
        func layers() -> String {
            guard let root = hosting.view.layer else { return "no layer" }
            var out: [String] = ["flipped=\(hosting.view.isFlipped) geomFlipped=\(root.isGeometryFlipped)"]
            func walk(_ layer: CALayer, depth: Int) {
                guard depth <= 3 else { return }
                for (i, sub) in (layer.sublayers ?? []).enumerated() where i < 6 {
                    let f = (sub.presentation() ?? sub).frame
                    out.append(String(format: "%@%d:%@ y=%.1f h=%.1f", String(repeating: ".", count: depth), i, String(describing: type(of: sub)), f.minY, f.height))
                    walk(sub, depth: depth + 1)
                }
            }
            walk(root, depth: 0)
            // Every drawn layer in root coordinates (presentation values):
            // the lowest edge (the footer) and the drawn layers below the
            // history's first card (y > 150), with their opacity.
            var bottom: CGFloat = 0
            var below: [String] = []
            func all(_ layer: CALayer) {
                for sub in layer.sublayers ?? [] {
                    let p = sub.presentation() ?? sub
                    let f = (layer.presentation() ?? layer) === (root.presentation() ?? root) ? p.frame : root.convert(p.frame, from: layer)
                    if f.height > 0, f.height < 300 { bottom = max(bottom, f.maxY) }
                    if f.minY > 150, f.minY < 400, f.height < 60, below.count < 4 { below.append(String(format: "%.0f/%.2f", f.minY, p.opacity)) }
                    all(sub)
                }
            }
            all(root)
            let header = (root.sublayers?.first).map { ($0.presentation() ?? $0).frame.minY } ?? -1
            return String(format: "header=%.1f bottom=%.1f ", header, bottom) + "below[" + below.joined(separator: " ") + "]"
        }
        func sample(_ label: String) {
            let window = hosting.view.window!
            print(String(format: "PROBE %@ t=%.3f window.top=%.1f window.h=%.1f view.h=%.1f ", label, CACurrentMediaTime().truncatingRemainder(dividingBy: 100), window.frame.maxY, window.frame.height, hosting.view.frame.height) + layers())
        }
        sample("before")
        model.historyExpanded = true  // as the header button does
        let start = Date()
        while Date().timeIntervalSince(start) < 0.6 {
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 60))
            sample("unfold")
        }
        model.historyExpanded = false
        let start2 = Date()
        while Date().timeIntervalSince(start2) < 0.6 {
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 60))
            sample("fold")
        }
        panel.orderOut(nil)
    }
}
