import AppKit
import SwiftUI

/// Settings → Learn Overnight: one button that sets up or removes the nightly
/// review (fork-009), and what the last night did.
struct NightlySection: View {
    @ObservedObject var store: SettingsStore
    @State private var installed = NightlyTask.isInstalled
    @State private var state = NightlyReview.State.load()

    var body: some View {
        SettingsGroup("Learn Overnight") {
            Text("Each night at 3:00, Parrot reviews the day's dictations, finds the words it keeps getting wrong, and proposes dictionary entries. Claude judges short excerpts; audio never leaves the Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PillRow("Nightly review") {
                Button(installed ? "Turn Off" : "Turn On") {
                    if installed { NightlyTask.remove() } else { try? NightlyTask.install() }
                    installed = NightlyTask.isInstalled
                }
                .buttonStyle(installed ? .pill : .primaryPill)
                .disabled(!NightlyTask.isAvailable || !store.current.corpus.enabled)
            }
            if installed {
                PillRow(state.map { "Last night: \(Self.date($0.lastRun))" } ?? "Not run yet") {
                    HStack(spacing: 8) {
                        Button("Run Now") { NightlyTask.runNow() }
                            .buttonStyle(.pill)
                        if let report = state?.lastReport {
                            Button("Open Report") { NSWorkspace.shared.open(URL(fileURLWithPath: report)) }
                                .buttonStyle(.pill)
                        }
                    }
                }
            }
            if !store.current.corpus.enabled {
                Text("Needs the corpus: set \"corpus\": {\"enabled\": true} in the config file.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !NightlyTask.isAvailable {
                Text("Install the scripts with scripts/fork-install.sh first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if installed {
                Text(store.current.dream.autoApply
                     ? "Safe entries go straight into the dictionary; each change is backed up."
                     : "Proposals only: entries are listed in the report, not written. Set \"dream\": {\"autoApply\": true} to apply them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            installed = NightlyTask.isInstalled
            state = NightlyReview.State.load()
        }
    }

    private static func date(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
