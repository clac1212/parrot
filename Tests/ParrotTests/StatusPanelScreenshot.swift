import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

/// Diagnostic: the real panel in its `MenuBarPanel` on screen, photographed with
/// `screencapture` — the only way to see Liquid Glass, which offscreen
/// snapshots don't draw. PANEL_SCREENSHOT=<dir> writes folded.png and
/// unfolded.png there. Needs Screen Recording for the terminal.
final class StatusPanelScreenshot: XCTestCase {
    @MainActor
    func testScreenshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["PANEL_SCREENSHOT"] else { throw XCTSkip("no PANEL_SCREENSHOT") }
        NSApplication.shared.setActivationPolicy(.accessory)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let history = DictationHistory(file: tmp.appendingPathComponent("history.json"))
        for (minutes, text) in [(300, "Salut, je te renvoie le lien du doc demain matin."), (120, "Ok pour moi, on se cale un point jeudi à 14 h pour en parler avec toute l'équipe."), (40, "Pense à relancer le fournisseur pour la livraison de mardi."), (2, "Test parrot.")] {
            history.add(text, at: Date().addingTimeInterval(-Double(minutes) * 60))
        }
        let store = SettingsStore(file: tmp.appendingPathComponent("settings.json"))
        let model = StatusPanelModel(store: store, history: history)
        model.status = StatusPanelModel.french(status: "idle · hold fn to dictate")
        model.modelLine = "Parakeet Ultra"

        NSApp.activate(ignoringOtherApps: true)
        let hosting = StatusPopover.hosting(StatusPanelView(model: model))
        let panel = MenuBarPanel(content: hosting)
        panel.show(under: NSRect(x: 500, y: NSScreen.main!.frame.maxY - 24, width: 30, height: 24))
        func shoot(_ name: String) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            let number = hosting.view.window!.windowNumber
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-o", "-l", "\(number)", "\(dir)/\(name).png"]
            try task.run()
            while task.isRunning { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        try shoot("folded")
        model.historyExpanded = true
        try shoot("unfolded")
        panel.orderOut(nil)
    }
}
