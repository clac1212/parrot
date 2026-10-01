# Fork ADR-002 :: Dictation indicator around the notch

Last updated: `2026.10.01`

> On a screen with a notch, the dictation indicator is a Dynamic Island–style
> shape around it, the same as quill's recording indicator (quill ADR-003): a
> pulsing dot and the elapsed time left of the notch, the live waveform right
> of it. On a screen without one, upstream's pill at the bottom stays.

## 1. Decision

- **`NotchOverlay`** (`Sources/ParrotCore/UI/NotchOverlay.swift`) replaces
  `RecordingOverlay` as the overlay `DictationObserver`. At each press it picks
  the screen the pill would use (`NSScreen.main`). If that screen has a notch,
  the notch shows the dictation. If not, it hands the state to an upstream
  `RecordingOverlay`, unchanged.
- **Compact notch while recording**: on the left, a red dot pulsing and the
  elapsed time (`m:ss`, truncated like a stopwatch). The time is kept for
  long dictations, at the user's request. On the right, the pill's
  `Waveform`, fed by the same levels (`OverlayModel`).
- **While transcribing**: the time stops and the dot turns still, in the
  waveform's blue. The waveform settles into dots, as in the pill.
- **Messages** (`UserFacingError`, such as a missing microphone) unfold
  under the notch for 4 s, as the pill shows them.
- **Click-through, no hover.** quill unfolds on hover with a Stop button.
  Dictation is push-to-talk: there is nothing to click. DynamicNotchKit's
  panel can become key, and a click on it would take the focus the text is
  about to be pasted into. So `hoverBehavior` is empty and the window is set
  to `ignoresMouseEvents` after each appearance.
- **No setting.** The screen decides; `--no-overlay` still turns off both.

## 2. Rationale

| Question | Choice | Why |
|---|---|---|
| Library or hand-made? | DynamicNotchKit 1.1.0 (MIT), pinned `exact` | The user asked for quill's animation: same library, same version, same spring. A hand-made shape over the notch (~150 lines) would have to redo that spring to look the same. Pinned because the code relies on the window being built at the start of a transition (see §3); an update could change the animation or that. |
| Replace the pill or add the notch? | Replace on notched screens, keep the pill otherwise | DynamicNotchKit shows nothing compact on a screen without a notch (an external display as main screen). Without a fallback, there would be no indicator there. |
| Waveform | Reuse upstream's `Waveform` | Same levels, same morph into dots while transcribing. The only edit is `private` → internal on it. |
| Upstream edits | 3, one line each | `Package.swift` (the dependency), `Daemon.swift` (the overlay's type), `RecordingOverlay.swift` (`Waveform` visibility). |

**Latency.** The overlay is a `DictationObserver`: `DictationController`
starts capture before notifying it, and the transcriber's work doesn't go
through it. The notch can't move the decoder, which is 88 % of release→text.
What it could slow is the main thread at the press (DynamicNotchKit builds a
new `NSHostingView` and panel each time it appears, where the pill reuses
one) and at the delivery.

Baseline, the official app's 50 dictations before the fork (pill):

| | median | p90 |
|---|---|---|
| release→text | 650 ms | 1742 ms |
| press→first sample | 94 ms | 118 ms |
| stop | 12 ms | 19 ms |
| deliver | 3 ms | 15 ms |

After (notch): **to measure** over about twenty dictations, same metrics.
release→text varies with what is said; press→first sample, stop and
deliver are the ones the overlay could move.

## 3. Design Implications

- DynamicNotchKit builds its window in the synchronous start of
  `compact()`/`expand()`. `NotchOverlay.show` relies on it: it sets
  `ignoresMouseEvents` in a main-queue block queued right after the
  transition. If an update moves the window creation behind a suspension
  point, the window would stay clickable. Check this before bumping the
  version.
- DynamicNotchKit rebuilds its window when screens change
  (`didChangeScreenParametersNotification`), without
  `ignoresMouseEvents`. A display plugged in during a dictation leaves that
  notch clickable until the next one.
- A press while an earlier dictation is still transcribing: that one's
  `dictationFinished` hides the indicator during the new recording, as it
  did with the pill (upstream behavior, kept).
- If the main screen changes between two states, the notch folds and the
  pill takes over, so a message never stays up without its timer.

## 4. When to Revisit

- The measurements after show a slower press or delivery → pre-build the
  window, or move to a hand-made shape that keeps one window.
- A dictation's text lands in the wrong place, or the notch takes a click →
  the click-through isn't holding (§3).
- Upstream changes `RecordingOverlay` → check that `NotchOverlay` still
  delegates the same states.
