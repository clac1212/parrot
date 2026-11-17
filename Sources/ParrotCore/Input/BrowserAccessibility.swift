import AppKit
import ApplicationServices

/// Chromium apps build their Accessibility tree only when an assistive tool
/// asks (fork-018). Until then they name no focused element, and Parrot
/// can't tell a text field from a page: a dictation said over a page in
/// Ardia was pasted into nothing instead of waiting on the clipboard
/// (fork-013), and the capital letter (fork-014) never knew what came before.
///
/// At each recording start, if the frontmost app names no focused element
/// and is built on Chromium, ask it to turn its accessibility on: first
/// Electron's switch (`AXManualAccessibility`, documented, harmless), and if
/// the app refuses it — a Chromium browser such as Ardia or Chrome —
/// Chromium's own, `AXEnhancedUserInterface` (what VoiceOver sets). The tree
/// is built while the user speaks, so the delivery sees it. What Parrot
/// turned on, it turns off when it quits.
@MainActor
final class BrowserAccessibility: DictationObserver {
    /// Apps and the switch Parrot turned on in them.
    private var turnedOn: [pid_t: CFString] = [:]

    private static let electronSwitch = "AXManualAccessibility" as CFString
    private static let chromiumSwitch = "AXEnhancedUserInterface" as CFString

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        }
    }

    func dictationStarted() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        guard turnedOn[pid] == nil, Self.isChromium(app.bundleURL) else { return }
        let element = AXUIElementCreateApplication(pid)
        // Bounded like every other read on the hotkey's thread.
        AXUIElementSetMessagingTimeout(element, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .noValue else { return }
        for name in [Self.electronSwitch, Self.chromiumSwitch] where Self.turnOn(name, in: element) {
            turnedOn[pid] = name
            // The bundle id only: which apps needed it, never what they show.
            Log.info("  accessibility: turned on \(name) in \(app.bundleIdentifier ?? "?")")
            return
        }
    }

    /// Sets `name` and reads it back: Chromium answers "not implemented" to
    /// the set yet applies it (tested 2026-11-17 in Ardia). False when the
    /// app doesn't have the switch, or had it on already (another tool's,
    /// left alone).
    private static func turnOn(_ name: CFString, in element: AXUIElement) -> Bool {
        var current: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &current) == .success, (current as? Bool) != true else { return false }
        AXUIElementSetAttributeValue(element, name, kCFBooleanTrue)
        guard AXUIElementCopyAttributeValue(element, name, &current) == .success else { return false }
        return (current as? Bool) == true
    }

    private func restore() {
        for (pid, name) in turnedOn {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), name, kCFBooleanFalse)
        }
        turnedOn = [:]
    }

    /// Chromium and its forks (Chrome, Ardia, Dia, Electron apps) ship a
    /// framework with a `Helpers` folder for their helper processes; other
    /// apps don't (Spotify's CEF included). A filesystem check, no AX.
    nonisolated static func isChromium(_ bundle: URL?) -> Bool {
        guard let frameworks = bundle?.appendingPathComponent("Contents/Frameworks"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: frameworks.path) else { return false }
        return names.contains { name in
            name.hasSuffix(".framework") && FileManager.default.fileExists(
                atPath: frameworks.appendingPathComponent(name).appendingPathComponent("Versions/Current/Helpers").path
            )
        }
    }
}
