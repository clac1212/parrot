import Foundation

/// The launchd job of the nightly review (fork-009), set up and removed from
/// the panel. launchd only wakes `run.sh` every 30 minutes (and at login);
/// the script decides whether to run: once per 20 h, when the Mac is on AC
/// power and idle for 10 minutes (on battery too past 48 h).
enum NightlyTask {
    static let label = "com.clac1212.parrot.dream"
    static var plist: URL { Paths.launchAgentPlist(label: label) }
    static var script: URL { Paths.dream.appendingPathComponent("bin/run.sh") }
    static var log: URL { Paths.logs.appendingPathComponent("dream.log") }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    static let checkInterval = 1800
    static var forceFile: URL { Paths.dream.appendingPathComponent("force") }

    /// The review is not a choice (fork-009): installed at launch whenever
    /// the corpus is on and the scripts are there, removed when the corpus
    /// is turned off. Also rewrites a job from an older build.
    static func sync(corpusEnabled: Bool) {
        guard isAvailable, corpusEnabled else {
            if isInstalled { remove() }
            return
        }
        let job = NSDictionary(contentsOf: plist)
        if job?["StartInterval"] as? Int != checkInterval { try? install() }
    }
    /// The scripts come with `scripts/fork-install.sh`.
    static var isAvailable: Bool { FileManager.default.fileExists(atPath: script.path) }

    static func install() throws {
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", script.path],
            "StartInterval": Self.checkInterval,
            "RunAtLoad": true,
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
        Log.info("dream: review checks every 30 minutes, runs once a day when the Mac is free")
    }

    static func remove() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plist)
        Log.info("dream: nightly review removed")
    }

    /// Runs the review now, in the background, whatever the conditions.
    static func runNow() {
        try? Data().write(to: forceFile)
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
