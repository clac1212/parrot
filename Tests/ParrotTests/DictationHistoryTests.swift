import XCTest
@testable import ParrotCore

final class DictationHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyTheLastDayNewestFirst() {
        let old = DictationHistory.Entry(date: now.addingTimeInterval(-25 * 3600), text: "vieille")
        let morning = DictationHistory.Entry(date: now.addingTimeInterval(-5 * 3600), text: "matin")
        let lastNight = DictationHistory.Entry(date: now.addingTimeInterval(-23 * 3600), text: "hier soir")
        let recent = DictationHistory.recent([lastNight, old, morning], now: now)
        XCTAssertEqual(recent.map(\.text), ["matin", "hier soir"])
    }

    func testLabelSaysYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12, minute: 0))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 5))!
        let lastNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23, minute: 58))!
        XCTAssertEqual(DictationHistory.label(earlier, now: noon, calendar: calendar), "09:05")
        XCTAssertEqual(DictationHistory.label(lastNight, now: noon, calendar: calendar), "hier 23:58")
    }

    @MainActor
    func testKeptAcrossLaunchesAndPrivate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")
        let history = DictationHistory(file: file)
        let today = Date()
        history.add("  première  ", at: today.addingTimeInterval(-60))
        history.add("", at: today)
        history.add("deuxième", at: today)
        XCTAssertEqual(history.entries.map(\.text), ["deuxième", "première"])
        // The write is queued: wait for it.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, (try? Data(contentsOf: file)).map({ String(decoding: $0, as: UTF8.self).contains("deuxi") }) != true {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(DictationHistory(file: file).entries, history.entries)
    }
}
