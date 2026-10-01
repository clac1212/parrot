import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The bird in the menu bar opens one French panel under it, as in quill
/// (fork-010): what Parrot is doing, then every setting, then Quit — instead
/// of upstream's menu and its separate Settings window, which stay in the code
/// unused. `MenuBarController` keeps driving its slots (status, model,
/// permissions); the panel reads them while it is open.
@MainActor
final class StatusPopover: NSObject {
    private let popover = NSPopover()
    private let model: StatusPanelModel
    private weak var menuBar: MenuBarController?
    private var refresh: Timer?
    /// The status button holds its target weakly: this keeps the panel.
    private static var installed: StatusPopover?

    /// Takes over `menuBar`'s status item: a click opens the panel.
    @discardableResult
    static func install(on menuBar: MenuBarController, store: SettingsStore) -> StatusPopover {
        let panel = StatusPopover(menuBar: menuBar, store: store)
        menuBar.statusItem.menu = nil
        menuBar.statusItem.button?.target = panel
        menuBar.statusItem.button?.action = #selector(toggle)
        installed = panel
        return panel
    }

    private init(menuBar: MenuBarController, store: SettingsStore) {
        self.menuBar = menuBar
        model = StatusPanelModel(store: store)
        super.init()
        model.onGrantPermissions = { [weak menuBar] in menuBar?.onGrantPermissions?() }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: StatusPanelView(model: model))
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = menuBar?.statusItem.button else { return }
        read()
        // Twice a second while open, so recording and loading show live.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.popover.isShown { self.read() } else { self.refresh?.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh = timer
        // An accessory app: activate it so the panel's controls take clicks
        // and the panel closes on a click elsewhere.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func read() {
        guard let menuBar else { return }
        model.status = StatusPanelModel.french(status: menuBar.statusLine.title)
        model.modelLine = StatusPanelModel.french(modelLine: menuBar.modelLine.title)
        model.needsPermissions = !menuBar.grantPermissionsItem.isHidden
    }
}

@MainActor
final class StatusPanelModel: ObservableObject {
    let store: SettingsStore
    @Published var status = ""
    @Published var modelLine = ""
    @Published var needsPermissions = false
    var onGrantPermissions: () -> Void = {}

    init(store: SettingsStore) {
        self.store = store
    }

    /// The menu's status slot, in French. Pure, so it is tested.
    nonisolated static func french(status: String) -> String {
        if status.hasPrefix("idle · hold "), status.hasSuffix(" to dictate") {
            let key = status.dropFirst("idle · hold ".count).dropLast(" to dictate".count)
            return "Prêt · maintiens \(key) pour dicter"
        }
        let known = [
            "● recording": "● Enregistrement…",
            "transcribing…": "Transcription…",
            "hotkey unavailable, secure input active": "Raccourci indisponible : saisie sécurisée active",
            "hotkey tap disabled": "Raccourci désactivé par macOS",
            "grant Accessibility to start": "Autorise l'Accessibilité pour démarrer",
            "loading model…": "Chargement du modèle…",
            "couldn't load the model, retrying": "Impossible de charger le modèle, nouvel essai…",
        ]
        return known[status] ?? status
    }

    /// "model: parakeet-ultra · loading whisper-small…" → "Parakeet Ultra ·
    /// chargement de Whisper Small…". Pure, so it is tested.
    nonisolated static func french(modelLine: String) -> String {
        let line = modelLine.hasPrefix("model: ") ? String(modelLine.dropFirst("model: ".count)) : modelLine
        let parts = line.components(separatedBy: " · ")
        func name(_ id: String) -> String { ModelRegistry.find(id)?.displayName ?? id }
        var out = name(parts[0])
        if parts.count > 1 {
            let state = parts[1]
            for (english, french) in [("downloading ", "téléchargement de "), ("loading ", "chargement de "), ("couldn't load ", "impossible de charger ")]
            where state.hasPrefix(english) {
                let rest = state.dropFirst(english.count)
                let id = rest.prefix { $0 != "…" && $0 != " " }
                out += " · " + french + name(String(id)) + rest.dropFirst(id.count)
                return out
            }
            out += " · " + state
        }
        return out
    }
}

struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel
    @ObservedObject private var store: SettingsStore

    init(model: StatusPanelModel) {
        self.model = model
        self.store = model.store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            // No scrolling: the panel is as tall as its content, which fits
            // a MacBook screen.
            VStack(alignment: .leading, spacing: 18) {
                dictation
                Divider()
                NightlySection(store: store)
            }
            .padding(16)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BirdBadge(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status).font(.headline)
                Text(model.modelLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.needsPermissions {
                Button("Autoriser…") { model.onGrantPermissions() }
                    .buttonStyle(.primaryPill)
            }
        }
    }

    private var selectedModel: TranscriptionModel? {
        store.current.model.id.flatMap(ModelRegistry.find) ?? ModelRegistry.recommended()
    }

    private var dictation: some View {
        SettingsGroup("Dictée") {
            PillRow("Raccourci") {
                PillMenu(title: store.current.hotkey.key.displayName) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Toggle(key.displayName, isOn: Binding(
                            get: { store.current.hotkey.key == key },
                            set: { on in if on { store.update { $0.hotkey.key = key } } }
                        ))
                    }
                }
            }
            PillRow("Modèle") {
                PillMenu(title: selectedModel?.displayName ?? "Aucun") {
                    modelGroup("Multilingue", ModelRegistry.shared.filter(\.isMultilingual))
                    modelGroup("Anglais seulement", ModelRegistry.shared.filter { !$0.isMultilingual })
                }
            }
            languageRow
            PillRow("Dictionnaire") {
                Button("Ouvrir") { Self.openDictionary() }
                    .buttonStyle(.pill)
            }
            if LoginItem.isAvailable {
                LaunchAtLoginToggle()
            }
        }
    }

    @ViewBuilder
    private func modelGroup(_ title: String, _ models: [TranscriptionModel]) -> some View {
        Section(title) {
            ForEach(models.sorted { $0.sizeMB < $1.sizeMB }, id: \.id) { model in
                Toggle(isOn: Binding(
                    get: { selectedModel?.id == model.id },
                    set: { on in if on { store.update { $0.model.id = model.id } } }
                )) {
                    if Transcribers.isCached(model) {
                        Text(model.displayName)
                    } else {
                        Label(model.displayName, systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var languageRow: some View {
        let multilingual = selectedModel?.isMultilingual ?? false
        let supported = selectedModel?.supportedLanguages ?? []
        let code = store.current.language.code?.lowercased()
        let selected = code.flatMap { supported.contains($0) ? $0 : nil }
        PillRow("Langue") {
            PillMenu(title: selected.map { SpokenLanguage.displayName($0) } ?? "Automatique") {
                languageToggle("Automatique", nil, selected: selected)
                Divider()
                ForEach(
                    supported.map { (code: $0, name: SpokenLanguage.displayName($0)) }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    id: \.code
                ) { language in
                    languageToggle(language.name, language.code, selected: selected)
                }
            }
            .disabled(!multilingual)
        }
    }

    private func languageToggle(_ name: String, _ code: String?, selected: String?) -> some View {
        Toggle(name, isOn: Binding(
            get: { selected == code },
            set: { on in if on { store.update { $0.language.code = code } } }
        ))
    }

    private var footer: some View {
        HStack {
            Button("Fichier de configuration") {
                store.createIfMissing()
                NSWorkspace.shared.open(store.file)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            if Updater.isRunning {
                Button("Mises à jour…") { Updater.checkForUpdates() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button("Quitter Parrot") { NSApp.terminate(nil) }
                .buttonStyle(.pill)
        }
        .font(.callout)
    }

    /// Opens the dictionary in the default plain-text editor, creating it
    /// first if missing (as upstream's Settings window does).
    private static func openDictionary() {
        let file = Paths.dictionaryFile
        DictionaryStore(file: file).createIfMissing()
        let editor = NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText)
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Launch at login through `SMAppService`, read live.
private struct LaunchAtLoginToggle: View {
    @State private var isOn = LoginItem.isEnabled

    var body: some View {
        PillRow("Ouvrir au démarrage") {
            Toggle("Ouvrir au démarrage", isOn: Binding(
                get: { isOn },
                set: { on in
                    do {
                        try LoginItem.setEnabled(on)
                    } catch {
                        Log.warning("couldn't change launch at login: \(error)")
                    }
                    isOn = LoginItem.isEnabled
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}
