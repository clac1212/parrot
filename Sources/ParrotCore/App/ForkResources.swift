import Foundation

/// What `Parrot.app` carries for the fork's features that run outside it
/// (fork-012): the daily review's scripts (fork-009) and the MediaRemote
/// adapter (fork-008), in `Contents/Resources/fork`. Copied at each launch to
/// where those features look for them, so an app installed from a DMG is
/// complete on its own and an update brings its scripts along.
enum ForkResources {
    static func install() {
        // A binary run outside the app (`swift run`) carries nothing.
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("fork", isDirectory: true),
              FileManager.default.fileExists(atPath: bundled.path)
        else { return }
        do {
            _ = try Paths.prepareDirectory(Paths.dream)
            try copy(bundled.appendingPathComponent("dream"), into: Paths.dream.appendingPathComponent("bin"))
            try copy(bundled.appendingPathComponent("mediaremote"), into: Paths.mediaRemote)
            Log.info("fork: review scripts and media adapter installed")
        } catch {
            Log.error("fork: could not install the app's review scripts and media adapter: \(error)")
        }
    }

    /// Replaces each item of `source` in `destination`. Removed first, so a
    /// script bash is still reading keeps its old file.
    private static func copy(_ source: URL, into destination: URL) throws {
        let fm = FileManager.default
        _ = try Paths.prepareDirectory(destination)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: item, to: target)
            removeQuarantine(target)
        }
    }

    /// An app copied from a downloaded DMG passes its quarantine to what it
    /// copies, and perl then refuses the adapter ("Failed to load framework",
    /// checked 2026-10-07).
    private static func removeQuarantine(_ url: URL) {
        var paths = [url.path]
        if let walk = FileManager.default.enumerator(atPath: url.path) {
            paths += walk.compactMap { ($0 as? String).map { url.appendingPathComponent($0).path } }
        }
        for path in paths { removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }
}
