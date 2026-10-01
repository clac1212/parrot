import AppKit
import SwiftUI

/// Apprentissage nocturne (the panel, fork-010; Settings → Learn Overnight before): one button that sets up or removes the nightly
/// review (fork-009), and what the last night did.
struct NightlySection: View {
    @ObservedObject var store: SettingsStore
    @State private var installed = NightlyTask.isInstalled
    @State private var state = NightlyReview.State.load()

    var body: some View {
        SettingsGroup("Apprentissage nocturne") {
            Text("Chaque nuit à 3 h, Parrot relit les dictées du jour, repère les mots qu'il rate souvent et propose des entrées de dictionnaire. Claude juge de courts extraits ; l'audio ne quitte jamais le Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PillRow("Revue de nuit") {
                Button(installed ? "Désactiver" : "Activer") {
                    if installed { NightlyTask.remove() } else { try? NightlyTask.install() }
                    installed = NightlyTask.isInstalled
                }
                .buttonStyle(installed ? .pill : .primaryPill)
                .disabled(!NightlyTask.isAvailable || !store.current.corpus.enabled)
            }
            if installed {
                PillRow(state.map { "Dernière nuit : \(Self.date($0.lastRun))" } ?? "Pas encore lancée") {
                    HStack(spacing: 8) {
                        Button("Lancer") { NightlyTask.runNow() }
                            .buttonStyle(.pill)
                        if let report = state?.lastReport {
                            Button("Rapport") { NSWorkspace.shared.open(URL(fileURLWithPath: report)) }
                                .buttonStyle(.pill)
                        }
                    }
                }
            }
            if !store.current.corpus.enabled {
                Text("Nécessite le corpus : mets \"corpus\": {\"enabled\": true} dans le fichier de configuration.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !NightlyTask.isAvailable {
                Text("Installe d'abord les scripts avec scripts/fork-install.sh.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if installed {
                Text(store.current.dream.autoApply
                     ? "Les entrées sûres vont directement dans le dictionnaire ; chaque changement est sauvegardé."
                     : "Propositions seulement : les entrées sont listées dans le rapport, pas écrites. Mets \"dream\": {\"autoApply\": true} pour les appliquer.")
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
