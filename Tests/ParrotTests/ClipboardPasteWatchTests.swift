import XCTest
@testable import ParrotCore

/// fork-019: a dictation left on the clipboard is watched once pasted.
@MainActor
final class ClipboardPasteWatchTests: XCTestCase {
    private var count = 1
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var field: String?
    private var watched: [(String, URL?)] = []

    private func make() -> ClipboardPasteWatch {
        ClipboardPasteWatch(
            changeCount: { [unowned self] in count }, now: { [unowned self] in clock },
            focusedText: { [unowned self] in field }, watch: { [unowned self] text, _, file, _ in watched.append((text, file)) }
        )
    }

    private let text = "On lance Lark demain matin, avant la réunion d'équipe."
    private let file = URL(fileURLWithPath: "/tmp/x.json")

    func testWatchedOnceTheFieldHoldsIt() {
        let paste = make()
        paste.expect(text, raw: nil, file: file, model: "m")
        field = "Salut,"
        paste.look()
        XCTAssertTrue(watched.isEmpty)
        field = "Salut, " + text
        paste.look()
        XCTAssertEqual(watched.map(\.0), [text])
        XCTAssertEqual(watched.map(\.1), [file])
        XCTAssertFalse(paste.isWaiting, "once")
    }

    func testGivesUpWhenTheClipboardChanges() {
        let paste = make()
        paste.expect(text, raw: nil, file: nil, model: "m")
        count += 1
        field = text
        paste.look()
        XCTAssertTrue(watched.isEmpty)
        XCTAssertFalse(paste.isWaiting)
    }

    func testGivesUpAfterTheExpiry() {
        let paste = make()
        paste.expect(text, raw: nil, file: nil, model: "m")
        clock += PendingDictations.expiry + 1
        field = text
        paste.look()
        XCTAssertTrue(watched.isEmpty)
        XCTAssertFalse(paste.isWaiting)
    }

    func testAnUnreadableFieldKeepsWaiting() {
        let paste = make()
        paste.expect(text, raw: nil, file: nil, model: "m")
        paste.look()
        XCTAssertTrue(paste.isWaiting)
        paste.cancel()
        XCTAssertFalse(paste.isWaiting)
    }
}
