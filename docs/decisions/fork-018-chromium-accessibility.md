# Fork ADR-018 :: Ask Chromium apps to show what has focus

Last updated: `2026.11.17` · Status: **built**, to be confirmed on the
user's next dictations in Ardia

> Since the user moved from Dia to Ardia (November: 555 dictations in
> Ardia, 1 in Dia), dictations said over a page stopped gathering on the
> clipboard (fork-013): Ardia names no focused element, so Parrot took it
> for a field and pasted into nothing. Chromium builds its Accessibility
> tree only when an assistive tool asks; Parrot now asks, at each recording
> start, in a Chromium app that names nothing.

## 1. Decision

- **`Input/BrowserAccessibility.swift`**, a `DictationObserver`
  (`dictationStarted`). If the frontmost app's focused-element query says
  "no value" (-25212) and the app is built on Chromium, it turns on, in
  order:
  1. `AXManualAccessibility` — Electron's documented switch;
  2. if the app refuses it (Ardia: -25205), `AXEnhancedUserInterface` —
     what VoiceOver sets, and what Chromium browsers listen to.
  It reads the switch back: Ardia answers "not implemented" (-25208) to the
  set and applies it. A switch already on (another tool's) is left alone.
  What Parrot turned on, it turns off when it quits.
- **"Built on Chromium"**: a framework in `Contents/Frameworks` with a
  `Versions/Current/Helpers` folder — Ardia (`Chromium Framework`), Chrome,
  Dia (`ArcCore`), Electron apps; not Spotify (CEF, no `Helpers`), not
  native apps. A filesystem check, no AX.
- The tree is built while the user speaks, so the delivery's focus read
  finds the element. Only the first dictation in an app can still miss it.
- The log says which switch, in which app (bundle id), never content.

## 2. Measurements (2026-11-17, Ardia, by hand)

- Before: focused element -25212; `AXManualAccessibility` -25205.
- `AXEnhancedUserInterface` on, 1 s later: a page reports `AXWebArea`,
  value not settable → fork-013's "nowhere" (gathers on the clipboard);
  Ardia's text inputs report `AXTextArea` → a field (pasted).
- Ardia's CPU, 5 samples over 10 s: 4.0 % with the switch on, 6.9 % off —
  noise, no visible cost at rest.

## 3. Options considered

| Option | Why not |
|---|---|
| Take "no focused element" in a browser as "no field" | Ardia says nothing in its fields either: every dictation into a field would be held back. |
| Paste and also gather, when unsure | Rejected in fork-013: the next ⌘V would paste the dictation twice. |
| Ask Ardia through its CLI (`ardia browse`) whether the page's active element is a field | Ardia only, and a process call per dictation. Plan B if the switch misbehaves. |
| An Input Method (macOS wakes it only in text fields, in every app) | The user would have to add it as an input source; it sits in all typing. |
| `--force-renderer-accessibility` on Ardia's command line | A manual step, for one user. |
| `AXEnhancedUserInterface` in Electron apps | Took focus from Claude's input (OpenWhispr #1116): Electron gets its own switch first, and only Chromium apps that refuse it get this one. |

## 4. When to Revisit

- `accessibility: turned on` lines in the log, and fork-013's
  `nowhere to paste (AXWebArea)` coming back in Ardia.
- Any report of focus jumping, slow window animations, or a heavy page
  slower in a browser while Parrot runs: the known side effects of
  `AXEnhancedUserInterface` in Chromium.
