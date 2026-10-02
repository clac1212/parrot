# Fork ADR-010 :: A French panel from the menu bar

Last updated: `2026.10.01`

> Clicking the bird opens one panel under it, in French, as quill does: what
> Parrot is doing, every setting, Quit. Upstream's menu and its separate
> Settings window are no longer shown.

## 1. Decision

- **`StatusPopover`** (`UI/StatusPopover.swift`): an `NSPopover` (closes on a
  click elsewhere) attached to `MenuBarController`'s status item, which stops
  showing its menu. Content, top to bottom:
  - the state — `MenuBarController`'s status and model slots, read twice a
    second while open and put in French ("Prêt · maintiens fn pour dicter",
    "● Enregistrement…", "Parakeet Ultra · chargement de …"), and an
    *Autoriser…* button while a permission is missing (the menu's Grant
    Permissions…);
  - **Dictée**: Raccourci, Modèle, Langue (the model's languages), Dictionnaire
    (opens the file), Ouvrir au démarrage (in Parrot.app);
  - **Apprentissage** (fork-009): information only — words learned, last
    run (+added −removed), a link to the report; no switch, no list to
    review (an accept/refuse list existed for a day, dropped as a
    non-choice);
  - no scrolling: the panel is as tall as its content (the user found a
    460 pt scroll area too short);
  - Fichier de configuration, Quitter Parrot (and Mises à jour… if the updater
    runs, which it doesn't in the fork).
- **French UI** for the panel only; upstream's other strings (onboarding,
  notifications, overlay messages) stay English.
- Upstream edits: `MenuBarController.statusItem` loses `private` (one word),
  one line in `Daemon` installs the panel. `MenuBarController` keeps its menu
  items as the state the panel reads; `SettingsWindow` and its sections stay,
  unused, to keep the diff small.

## 2. Rationale

The user found a window opening for settings heavy, and liked quill's panel
(quill ADR-003). The settings are few; they fit in one panel.

| Option | Why not |
|---|---|
| Keep the menu and the Settings window | What the user asked to change. |
| Translate upstream's Settings sections in place | Edits every string of upstream files: costly rebases. The panel builds its own rows from the same settings instead. |
| Rewrite `MenuBarController` around the panel | Its slots are read and written all over (daemon, model switcher, onboarding, observers); keeping them as the panel's source of state is one word of upstream diff. |

## 3. Design Implications

- Spoken languages for Automatic (several languages) aren't editable in the
  panel; `settings.json` still holds them.
- The panel activates Parrot (an accessory app) so its controls take clicks.
- `StatusPanelSnapshot` (a test) renders the panel to a PNG when
  `PANEL_SNAPSHOT` is set, to check the layout without the app.

## 4. When to Revisit

- Upstream changes its menu or Settings → port what matters into the panel.
- A setting stops fitting the panel → reconsider a window.
