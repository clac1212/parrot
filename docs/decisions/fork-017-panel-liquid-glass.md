# Fork ADR-017 :: The panel in today's macOS look

Last updated: `2026.11.24` · Status: **built**, to be judged by the user

> The menu-bar panel (fork-010) looked like 2015: big bold titles, full-width
> dividers, home-made pill buttons, no icons, an opaque popover with an
> arrow. The user showed RunCat Neo as the reference. It is now a slab of
> Liquid Glass hung under the menu-bar icon, with no arrow, darker cards on
> it, small grey section titles, an SF Symbol per row and glass buttons.
> Looks only: nothing it does changed.

## 1. Decision

- **The window — `UI/MenuBarPanel.swift`** (new): a borderless `NSPanel`
  whose content is an `NSGlassEffectView` (AppKit, macOS 26; radius 18 pt)
  holding the SwiftUI view; a blurred `NSVisualEffectView` before macOS 26.
  It hangs 5 pt under the status item, its left edge on the item's, kept on
  the screen. Its height follows the content's `preferredContentSize`
  through `preferredContentSizeDidChange(for:)`, top edge fixed. A click in
  another app (`hidesOnDeactivate`), losing key status, Escape or the icon
  close it; it fades in in 0.12 s.
- **Why not `NSPopover`** (first version of this ADR): its arrow, and its
  opaque background on macOS 27 — the user's first verdict, screenshots
  side by side: "rien de liquid glass… pointer l'icône vers le haut c'est
  moche". RunCat Neo is a SwiftUI `MenuBarExtra` in `.window` style (its
  binary imports `WindowMenuBarExtraStyle`); Parrot is an AppKit app, so
  `MenuBarPanel` builds the same thing by hand.
- **`UI/PanelStyle.swift`** (new): `PanelCard` (rounded group; fill black
  22 % in dark mode, white 55 % in light, so the glass shows as a rim
  around it; hairline), `PanelSectionTitle` (small, semibold, secondary),
  `PanelRow` (icon · label · control), `PanelIcon`, `PanelDivider` (starts
  after the icon column), `PanelMenu`, and `.panelButton()` — `.glass` /
  `.glassProminent` on macOS 26+, upstream's pill before. Upstream's
  `Pill.swift` is untouched (onboarding, Settings window).
- **Layout**: on the glass, a light header (bird 22 pt, status, model in
  grey); then three cards 8 pt from the glass's edge, corners of 10 pt
  (concentric: 18 − 8) — Dernières dictées, Dictée (Raccourci ⌨,
  Dictionnaire 📖, Ouvrir au démarrage ⏻), Apprentissage ✦; on the glass
  again, a footer with the configuration link and a glass « Quitter ».
- **Glass for controls and the slab**, not the cards: cards are content
  (Apple: Liquid Glass is the controls layer; glass on glass muddies).
- **History** (fork-015): one card; the latest dictation on top, the
  others under hairlines; hover highlights a row in a rounded inset.
- **Older macOS** (14–25): same layout on a blurred material, pills
  instead of glass.
- **The corners, 2026-11-24.** The user saw a dark 1 pt rim past the glass:
  square at the bottom corners, a smaller curve than the glass's at the
  top. Only the glass was rounded, not the window, so the window server
  drew the shadow and its rim on a plain window's shape. Found in quill,
  which shares this window, by photographing it with `screencapture -l`
  with and without its shadow (`-o`): without, the corners were clean.
  The window's content is now a container clipped to the glass's corners
  (18 pt, continuous), and `show` recomputes the shadow once on screen
  (`fit` already did on every resize). Parrot's own probe
  (`StatusPanelScreenshot`, now photographing with the shadow too) showed
  clean corners before the fix as well: the defect needs the real app's
  window; the user's eye confirms it.
- The fold animation keeps fork-015's measured recipe (docs/fork-ui-notes.md
  §2); re-measured in the new window: header fixed at 18 pt, window top
  fixed, window 376 → 612 pt at once, bottom of the content gliding
  364 → 600 pt and back.

## 2. Options considered

| Option | Why not |
|---|---|
| Keep `NSPopover` with the new cards (first version) | The user: no glass to see, the arrow is ugly. |
| SwiftUI `MenuBarExtra(.window)`, as RunCat Neo | Needs a SwiftUI `App` lifecycle; Parrot's is AppKit (upstream's `Daemon`). Rewriting it touches upstream's core. |
| Glass on every card (`glassEffect` in a `GlassEffectContainer`) | Glass on glass muddies contrast; Apple reserves glass for controls. |
| Keep upstream's pills and only add icons | The dated look came as much from the titles and dividers. |

## 3. Design Implications

- ~120 lines of window behaviour (`MenuBarPanel`) that the popover gave for
  free: placement, closing, sizing. Ours, not upstream's: rebases unaffected.
- `PopoverResizeProbe` is gone with the popover; its findings stay in
  docs/fork-ui-notes.md §2.
- **Not verifiable by the agent**: offscreen snapshots don't draw Liquid
  Glass (the window server does), and `screencapture` needs Screen
  Recording for the terminal, which it doesn't have. Layout is checked by
  snapshot, motion by the probe; the glass by the user's eye.

## 4. When to Revisit

- The user's verdict on the glass and the card contrast, light and dark.
- A click on the icon while the panel is open must close it, not reopen
  it: checked by the user, not by a test.
- Upstream moves to a SwiftUI `App`: use `MenuBarExtra(.window)` and drop
  `MenuBarPanel`.
