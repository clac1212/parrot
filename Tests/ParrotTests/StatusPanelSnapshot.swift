import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

/// Renders the panel to $PANEL_SNAPSHOT (a PNG path) when set; skipped otherwise.
final class StatusPanelSnapshot: XCTestCase {
    @MainActor
    func testRenderPanel() throws {
        guard let path = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT"] else { throw XCTSkip("no PANEL_SNAPSHOT") }
        let store = SettingsStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("panel-settings.json"))
        store.update { $0.model.id = "parakeet-ultra"; $0.language.code = "fr"; $0.corpus.enabled = true }
        let model = StatusPanelModel(store: store)
        model.status = StatusPanelModel.french(status: "idle · hold fn to dictate")
        model.modelLine = StatusPanelModel.french(modelLine: "model: parakeet-ultra")
        let view = NSHostingView(rootView: StatusPanelView(model: model).environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(x: 0, y: 0, width: 360, height: view.fittingSize.height)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
