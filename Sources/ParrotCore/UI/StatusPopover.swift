import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The bird in the menu bar opens one French panel under it, as in quill
/// (fork-010): what Parrot is doing, then every setting, then Quit — instead
/// of upstream's menu and its separate Settings window, which stay in the code
/// unused. `MenuBarController` keeps driving its slots (status, model,
/// permissions); the panel reads them while it is open. Since fork-017 the
/// panel is a `MenuBarPanel` (glass, no arrow), no longer an `NSPopover`.
@MainActor
final class StatusPopover: NSObject {
    private var panel: MenuBarPanel!
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
        NightlyTask.sync(corpusEnabled: store.current.corpus.enabled)
        return panel
    }

    private init(menuBar: MenuBarController, store: SettingsStore) {
        self.menuBar = menuBar
        model = StatusPanelModel(store: store, history: .shared)
        super.init()
        model.onGrantPermissions = { [weak menuBar] in menuBar?.onGrantPermissions?() }
        panel = MenuBarPanel(content: Self.hosting(StatusPanelView(model: model)))
    }

    /// The panel's SwiftUI view, sized by its ideal size: with
    /// `.preferredContentSize` the hosting controller publishes that size as
    /// its `preferredContentSize`, which `MenuBarPanel` follows. The default
    /// (`.standardBounds`) sizes the window through Auto Layout constraints
    /// instead (fork-015, docs/fork-ui-notes.md).
    static func hosting<Content: View>(_ view: Content) -> NSHostingController<Content> {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }

    @objc private func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard let anchor = menuBar?.statusItem.button?.window?.frame else { return }
        read()
        model.history.prune()
        // Twice a second while open, so recording and loading show live.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.panel.isVisible { self.read() } else { self.refresh?.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh = timer
        // An accessory app: activate it so the panel's controls take clicks
        // and the panel closes on a click elsewhere.
        NSApp.activate(ignoringOtherApps: true)
        panel.show(under: anchor)
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
    let history: DictationHistory
    @Published var status = ""
    @Published var modelLine = ""
    @Published var needsPermissions = false
    /// Whether « Dernières dictées » is unfolded (fork-015).
    @Published var historyExpanded = false
    var onGrantPermissions: () -> Void = {}

    init(store: SettingsStore, history: DictationHistory) {
        self.store = store
        self.history = history
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
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 14) {
                // No scrolling: the panel is as tall as its content, which
                // fits a MacBook screen. Cards, not dividers (fork-017).
                HistorySection(history: model.history, expanded: $model.historyExpanded)  // fork-015
                dictation
                NightlySection(store: store)
                footer
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            .padding(.horizontal, PanelStyle.inset)
            .padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)
            // Folding the history moves what is below it. Animated here,
            // under the header: an animation that reaches the header also
            // animates the window's resize and slides the whole panel
            // (measured, docs/fork-ui-notes.md).
            .animation(.easeInOut(duration: 0.25), value: model.historyExpanded)
            // Its own geometry, animated from where it was drawn: without it
            // the block started 116 pt low, from a centred position, when
            // the window grew (measured).
            .geometryGroup()
        }
        .frame(width: 360)
        // When the window changes height, its view is briefly taller or
        // shorter than the content: keep the content at the top rather
        // than centred in it. Its ideal height is unchanged (a
        // flexible frame reports its child's ideal size), which is all
        // `.preferredContentSize` reads.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BirdBadge(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.status).font(.system(size: 13, weight: .semibold))
                Text(model.modelLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.needsPermissions {
                Button("Autoriser…") { model.onGrantPermissions() }
                    .panelButton(prominent: true)
            }
        }
    }

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle("Dictée")
            PanelCard {
            PanelRow("Raccourci", icon: "keyboard") {
                PanelMenu(title: store.current.hotkey.key.displayName) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Toggle(key.displayName, isOn: Binding(
                            get: { store.current.hotkey.key == key },
                            set: { on in if on { store.update { $0.hotkey.key = key } } }
                        ))
                    }
                }
            }
            PanelDivider()
            PanelRow("Dictionnaire", icon: "character.book.closed") {
                Button("Ouvrir") { Self.openDictionary() }
                    .panelButton()
            }
            if LoginItem.isAvailable {
                PanelDivider()
                LaunchAtLoginToggle()
            }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Fichier de configuration") {
                store.createIfMissing()
                NSWorkspace.shared.open(store.file)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            if Updater.isRunning {
                Button("Mises à jour…") { Updater.checkForUpdates() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
                .panelButton()
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
        PanelRow("Ouvrir au démarrage", icon: "power") {
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
            .controlSize(.small)
            .labelsHidden()
        }
    }
}
