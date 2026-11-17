import XCTest
@testable import ParrotCore

/// fork-018: which apps get their accessibility turned on — those built on
/// Chromium, told apart by their framework's `Helpers` folder.
final class BrowserAccessibilityTests: XCTestCase {
    private func bundle(_ frameworks: [String: Bool]) throws -> URL {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("chromium-\(UUID()).app")
        for (name, helpers) in frameworks {
            let framework = app.appendingPathComponent("Contents/Frameworks/\(name)")
            let path = helpers ? framework.appendingPathComponent("Versions/Current/Helpers") : framework
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        return app
    }

    func testAChromiumFrameworkWithHelpers() throws {
        XCTAssertTrue(BrowserAccessibility.isChromium(try bundle(["Chromium Framework.framework": true, "Sparkle.framework": false])))
    }

    func testOtherFrameworksAreNot() throws {
        XCTAssertFalse(BrowserAccessibility.isChromium(try bundle(["Sparkle.framework": false, "Chromium Embedded Framework.framework": false])))
        XCTAssertFalse(BrowserAccessibility.isChromium(try bundle([:])))
        XCTAssertFalse(BrowserAccessibility.isChromium(nil))
    }
}
