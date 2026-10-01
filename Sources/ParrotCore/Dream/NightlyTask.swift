import Foundation

/// The launchd job that runs the nightly review (fork-009) at 3:00, set up
/// and removed from Settings. A calendar job missed while the Mac slept runs
/// at wake.
enum NightlyTask {
    static let label = "com.clac1212.parrot.dream"
    static var plist: URL { Paths.launchAgentPlist(label: label) }
    static var script: URL { Paths.dream.appendingPathComponent("bin/run.sh") }
    static var log: URL { Paths.logs.appendingPathComponent("dream.log") }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    /// The scripts come with `scripts/fork-install.sh`.
    static var isAvailable: Bool { FileManager.default.fileExists(atPath: script.path) }

    static func install() throws {
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", script.path],
            "StartCalendarInterval": ["Hour": 3, "Minute": 0],
            "StandardOutPath": log.path,
            "StandardErrorPath": log.path,
            "ProcessType": "Background",
            "LowPriorityIO": true,
        ]
        _ = try Paths.prepareDirectory(plist.deletingLastPathComponent())
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        try data.write(to: plist)
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        launchctl(["bootstrap", "gui/\(getuid())", plist.path])
        Log.info("dream: nightly review scheduled at 3:00")
    }

    static func remove() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plist)
        Log.info("dream: nightly review removed")
    }

    /// Runs the job now, in the background.
    static func runNow() {
        launchctl(["kickstart", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
