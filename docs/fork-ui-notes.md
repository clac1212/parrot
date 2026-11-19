# SwiftUI in Parrot's AppKit shell — what to know before touching the UI

Parrot is an AppKit app (`NSApplication`, accessory policy) that hosts SwiftUI
views: the menu-bar panel (`MenuBarPanel`, a borderless glass window since
fork-017; an `NSPopover` before), the onboarding and
Settings windows (upstream), the notch (DynamicNotchKit, fork-002) and the
pill (`RecordingOverlay`, upstream). Most UI bugs come from the seam between
the two: **who decides a window's size, and who animates it**. Read this
before any UI change; add to it when you learn something the hard way.

## 1. Sizing a window from SwiftUI

`NSHostingController.sizingOptions` decides how the SwiftUI content sizes
its container ([Apple](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions)):

| Option | What it does | Use |
|---|---|---|
| `.standardBounds` (**default**) | min, intrinsic and max **Auto Layout constraints** in the window | Windows laid out by constraints. In a popover: the size changes through constraints, **at once, unanimated**; `preferredContentSize` stays **0**. |
| `.preferredContentSize` (macOS 13+) | publishes the content's **ideal size** (its size for an `.unspecified` proposal) as `preferredContentSize` ([Apple](https://developer.apple.com/documentation/swiftui/nshostingsizingoptions/preferredcontentsize)) | **Popovers.** `NSPopover` follows its controller's `preferredContentSize` and animates to it ([TomatoBar #3](https://github.com/cartfisk/TomatoBar/pull/3), [ClaudeUsageBar #36](https://github.com/Artzainnn/ClaudeUsageBar/pull/36)). |
| `[]` | no constraints | You size the window yourself. |

The panel: `StatusPopover.hosting` publishes the size, and `MenuBarPanel`'s
container controller gets it in `preferredContentSizeDidChange(for:)` (called
on the parent when a child's `preferredContentSize` changes, [Apple](https://developer.apple.com/documentation/appkit/nsviewcontroller/preferredcontentsizedidchange(for:)))
and resizes the window, top edge fixed. Rules:

- **Always `.preferredContentSize`.** Never size the window by
  hand, never measure `fittingSize` once: the panel's height changes (the
  history folds, the permissions button comes and goes).
- **The root view must have an ideal size**: a fixed width
  (`.frame(width: 360)`) and a height that comes from its content. A
  `ScrollView`'s ideal height is its content's, so cap lists with
  `.frame(maxHeight:)`.
- **Flexible frames**: `.frame(maxHeight: .infinity, alignment: .top)`
  reports its child's ideal height, so it is safe *with*
  `.preferredContentSize` and keeps the content at the top while the
  popover animates between two heights. *With* `.standardBounds` it turns
  into an infinite max-size constraint: the panel stopped shrinking
  (2026-11-16).
- A popover never grows past the screen: keep the panel short enough for a
  13" MacBook (no scrolling of the whole panel, fork-010).

## 2. Animating — measured, not guessed

Measured with `StatusPanelAnimationProbe` and `PopoverResizeProbe`
(2026-11-16, macOS 27.2), at 60 Hz, on a real popover:

- (Measured on the `NSPopover`; `MenuBarPanel` resizes the same way, at
  once, and the probe gives the same numbers: header fixed, window top
  fixed, bottom gliding 364 → 600 pt.)
- **`NSPopover` never animates its size.** A new `preferredContentSize` or
  `contentSize` is applied in one frame, top edge fixed (the arrow side).
  `NSWindow.setFrame(_:display:animate:)` animates but **blocks the main
  thread** for its duration, so SwiftUI can't animate alongside it. So the
  popover's edge always snaps; only what is inside can glide.
- **A `withAnimation` around the toggle animates the resize too**, and
  SwiftUI starts the whole panel from a position centred in the new height:
  the header slid down 116 pt (half the growth) and back up — "everything
  reloads". Same with an implicit `.animation(_:value:)` on a view that
  contains the header.
- **What works** (`StatusPanelView`):
  1. the toggle changes state **without** `withAnimation`;
  2. `.animation(_:value:)` on the block **under** the header (sections and
     footer), never on a view that contains the header;
  3. `.geometryGroup()` on that block, so its frame animates from where it
     was drawn — without it, the block still started 116 pt low;
  4. inside the history section, the rows that appear get
     `.transition(.move(edge: .top).combined(with: .opacity))` and the
     section `.clipped()`; the first card stays put.
  Result: header fixed to the point; the bottom glides 452 → 684 pt in
  ~0.2 s, and back.
- **Left as is**: the popover's bottom edge snaps. Unfolding, the space
  appears at once and the footer glides into it; folding, the footer is
  briefly below the edge and glides up. Avoiding it means a custom window
  instead of `NSPopover` — not worth it then. (fork-017 did move to a
  custom window, for the look; the edge still snaps.)

## 3. Liquid Glass (macOS 26+, fork-017)

- `glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)` /
  `.glassProminent` exist from macOS 26 ([Apple](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))).
  The package targets macOS 14: always behind `if #available(macOS 26, *)`
  with a fallback (`.panelButton()` in `PanelStyle.swift`).
- **Glass is for controls**, not content: buttons and menus get glass;
  cards get a faint fill and hairline. Never glass on glass — the window
  is already glass.
- **The window** (`MenuBarPanel`): a borderless `NSPanel`, transparent,
  whose content view is an `NSGlassEffectView` (AppKit, macOS 26) holding
  the SwiftUI view — what a SwiftUI `MenuBarExtra` in `.window` style looks
  like (RunCat Neo uses that; Parrot can't, it isn't a SwiftUI `App`). A
  borderless window refuses key status: override `canBecomeKey`. Closing:
  `hidesOnDeactivate` (click in another app), `didResignKey`, Escape
  (`cancelOperation`).
- **Corners are concentric**: inner radius = outer radius − inset (glass
  18 pt, cards 10 pt, 8 pt inside).
- **Can't be seen offscreen**: `cacheDisplay` snapshots draw glass buttons
  as bare dark text. `StatusPanelScreenshot` (`PANEL_SCREENSHOT=<dir>`)
  photographs the real panel with `screencapture`, but only if the
  terminal running it has Screen Recording; otherwise it writes nothing.

### Clicks in the notch without taking the keyboard (fork-019)

The corrections come out of DynamicNotchKit's window, which is a
non-activating `NSPanel` that can become key (`canBecomeKey` is forced
true in the library). Two settings make it clickable without stealing
focus from the field being edited:
- `ignoresMouseEvents = false` only while corrections show; the
  indicator stays click-through.
- `becomesKeyOnlyIfNeeded = true`: a click makes the panel key only if the
  clicked view asks for it (`needsPanelToBecomeKey`). SwiftUI buttons
  don't (probed 2026-11-19).

The library's `NSHostingView` returns false for `acceptsFirstMouse`, so
the buttons sit in a nested hosting view that returns true (`FirstClick`
in `NotchOffers.swift`). A nested hosting view doesn't inherit the
environment: pass the colour scheme in by hand.

The notch is black, so the content is set to the dark colour scheme. On a
screen without a notch it is DynamicNotchKit's floating card, a material:
use system colours there.

Offscreen snapshots draw nothing unless the view is in a window
(`CorrectionOfferTests.render`).

**Controls look inactive** in a window that is never key: a prominent
glass button turns grey, « Tout ajouter » dims. The notch's rows set
`.environment(\.appearsActive, true)` (settable, SwiftUI's interface
checked 2026-11-19), so they look as in the menu-bar panel.

### Animating the notch's size (fork-019, measured 2026-11-19)

DynamicNotchKit's black shape follows its content's ideal size
(`.fixedSize()` around the expanded view). Our rows sit in the nested
`FirstClick` hosting view, so the shape knew their size only through
`sizeThatFits` → `fittingSize`, and `withAnimation` around the change did
nothing: `NotchOfferProbe.testTheUnfoldGlides` (`NOTCH_PROBE=1`) saw the
height jump 37 → 124 pt between two 16 ms samples. What works:
1. the outer view (`NotchExpandedView`) owns the size as `@State` and
   frames the nested view with it, animated (`withAnimation(.smooth)`);
2. the nested hosting view reports its **`intrinsicContentSize`** after
   each `invalidateIntrinsicContentSize()` *and* each `layout()` — the
   invalidation alone can come before SwiftUI has the new size;
3. never `fittingSize` for that report: it follows the frame being
   animated and fed back into it (an endless ±0.4 pt wobble);
4. a change under 0.5 pt is ignored.
Result: 37 → 124 pt in ~0.35 s, eased, then still.

## 4. Checking a change — before telling the user it's done

1. **Sizing test** (`StatusPanelSizingTests`): `preferredContentSize` is
   finite, grows when the content grows, shrinks back. It failed with
   `.standardBounds` (height 0) — the bug it guards.
2. **Snapshot** of the panel, folded and unfolded:
   `PANEL_SNAPSHOT=$TMPDIR/panel.png swift test --filter ParrotTests.StatusPanelSnapshot`,
   then look at both PNGs (`panel.png`, `panel-history.png`).
3. **Animation**: `PANEL_ANIMATION=1 swift test --filter
   ParrotTests.StatusPanelAnimationProbe` shows the real panel in its window
   on screen, unfolds and folds it, and prints at 60 Hz the window's frame
   and the drawn layers' presentation frames (the header's `y`, the
   bottom-most edge). A header `y` that changes = the panel slides; a
   bottom that jumps = no animation. Then ask the user to look once — the
   probe sees positions, not taste.

## 5. History of mistakes (don't repeat)

| Date | What | Why it was wrong |
|---|---|---|
| 2026-11-16 | Animated the history with `withAnimation`, the popover sized by `.standardBounds` | The popover jumped to its new height while the content animated: "everything reloads". |
| 2026-11-16 | Removed `withAnimation` | Then nothing animated at all; the cause (sizing) was untouched. |
| 2026-11-16 | `.frame(maxHeight: .infinity)` on the root, still `.standardBounds` | Infinite max constraint: the panel stayed at its tallest. Fixed by `.preferredContentSize`. |
| 2026-11-19 | `withAnimation` around the notch's unfold, size from the nested hosting view | The black shape jumped in one frame (probed); see « Animating the notch's size ». |
| 2026-11-19 | Reported `fittingSize` to the animating parent | Fed back into itself: endless wobble around 37 pt. |
| 2026-11-16 | `.preferredContentSize` + `withAnimation` around the toggle | Header slid from 116 pt low (measured). Fixed by §2's recipe, found with the probe, not by trying on the user's screen. |
