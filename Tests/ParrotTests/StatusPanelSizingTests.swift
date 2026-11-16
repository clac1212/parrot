import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

/// The panel's height follows its content (fork-015): the popover reads the
/// hosting controller's `preferredContentSize`, so it must be finite, grow
/// when the history unfolds and shrink back when it folds.
final class StatusPanelSizingTests: XCTestCase {
    @MainActor
    func testThePopoverFollowsTheContentHeight() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sizing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let history = DictationHistory(file: dir.appendingPathComponent("history.json"))
        for minutes in 0..<6 { history.add("Dictée \(minutes), assez longue pour tenir sur deux lignes dans le panneau.", at: Date().addingTimeInterval(-Double(minutes) * 60)) }

        func height(expanded: Bool) -> CGFloat {
            let hosting = StatusPopover.hosting(
                HistorySection(history: history, expanded: .constant(expanded)).frame(width: 328).frame(maxHeight: .infinity, alignment: .top)
            )
            hosting.view.layoutSubtreeIfNeeded()
            return hosting.preferredContentSize.height
        }
        let folded = height(expanded: false)
        let unfolded = height(expanded: true)
        XCTAssertGreaterThan(folded, 0)
        XCTAssertLessThan(folded, 200, "folded: the header and one card")
        XCTAssertGreaterThan(unfolded, folded + 100, "unfolded: the list adds its rows")
        XCTAssertLessThan(unfolded, 400, "unfolded: the list scrolls instead of growing")
    }

    @MainActor
    func testTheWholePanelHasAFiniteHeight() throws {
        let store = SettingsStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("sizing-settings-\(UUID()).json"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sizing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = StatusPanelModel(store: store, history: DictationHistory(file: dir.appendingPathComponent("history.json")))
        let hosting = StatusPopover.hosting(StatusPanelView(model: model))
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.preferredContentSize
        XCTAssertEqual(size.width, 360, accuracy: 1)
        XCTAssertGreaterThan(size.height, 200)
        XCTAssertLessThan(size.height, 900, "a flexible frame must not make the panel as tall as the screen")
    }
}
