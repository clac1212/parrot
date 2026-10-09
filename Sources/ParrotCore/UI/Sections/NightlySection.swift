import AppKit
import SwiftUI

/// Apprentissage (the panel, fork-010): what the daily review (fork-009) has
/// done — information, no controls. The loop needs nothing from the user.
struct NightlySection: View {
    @ObservedObject var store: SettingsStore
    @State private var state = NightlyReview.State.load()

    var body: some View {
        SettingsGroup("Apprentissage") {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.headline(state))
                    Text(Self.detail(state, corpus: store.current.corpus.enabled))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let report = state?.lastReport {
                    Button("Rapport") { NSWorkspace.shared.open(URL(fileURLWithPath: report)) }
                        .buttonStyle(.pill)
                }
            }
        }
        .onAppear { state = NightlyReview.State.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            state = NightlyReview.State.load()
        }
    }

    /// "Parrot apprend de tes dictées · 6 mots appris".
    private static func headline(_ state: NightlyReview.State?) -> String {
        guard let learned = state?.learned, learned > 0 else { return "Parrot apprend de tes dictées" }
        return "Parrot apprend de tes dictées · \(learned) mot\(learned > 1 ? "s" : "") appris"
    }

    /// When it last ran and what's next, in one line.
    private static func detail(_ state: NightlyReview.State?, corpus: Bool) -> String {
        guard corpus else { return "En pause : le corpus est désactivé dans le fichier de configuration." }
        let running = FileManager.default.fileExists(atPath: Paths.dream.appendingPathComponent(".lock").path)
        if running { return "Revue en cours…" }
        guard let state, let date = ISO8601DateFormatter().date(from: state.lastRun) else {
            return "Première revue la prochaine fois que le Mac sera sur secteur."
        }
        // A date, not "il y a 3 min": the panel isn't redrawn as time
        // passes, so a relative time would freeze where it was first drawn.
        let when = date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_FR")))
        var parts = ["Dernière revue le \(when)"]
        if let applied = state.applied, applied > 0 { parts.append("+\(applied)") }
        if let removed = state.removed, removed > 0 { parts.append("−\(removed)") }
        if state.judged == false { parts.append("juge indisponible, repris à la prochaine") }
        return parts.joined(separator: " · ")
    }
}
