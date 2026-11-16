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
        let history = DictationHistory(file: FileManager.default.temporaryDirectory.appendingPathComponent("panel-history-\(UUID())/history.json"))
        for (minutes, text) in (0..<6).map { (400 + $0 * 60, "Dictée plus ancienne numéro \($0), assez longue pour tenir sur deux lignes dans le panneau.") } + [(300, "Salut, je te renvoie le lien du doc demain matin."), (120, "Ok pour moi, on se cale un point jeudi à 14 h pour en parler avec toute l'équipe et valider la suite."), (2, "Test parrot.")] {
            history.add(text, at: Date().addingTimeInterval(-Double(minutes) * 60))
        }
        let model = StatusPanelModel(store: store, history: history)
        model.status = StatusPanelModel.french(status: "idle · hold fn to dictate")
        model.modelLine = StatusPanelModel.french(modelLine: "model: parakeet-ultra")
        let view = NSHostingView(rootView: StatusPanelView(model: model).environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(x: 0, y: 0, width: 360, height: view.fittingSize.height)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))

        // The history section unfolded, beside it.
        let unfolded = NSHostingView(rootView: HistorySection(history: history, expanded: .constant(true)).padding(16).frame(width: 360).environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
        unfolded.appearance = NSAppearance(named: .darkAqua)
        unfolded.frame = NSRect(x: 0, y: 0, width: 360, height: unfolded.fittingSize.height)
        unfolded.layoutSubtreeIfNeeded()
        let rep2 = try XCTUnwrap(unfolded.bitmapImageRepForCachingDisplay(in: unfolded.bounds))
        unfolded.cacheDisplay(in: unfolded.bounds, to: rep2)
        try XCTUnwrap(rep2.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-history.png")))
    }
}
