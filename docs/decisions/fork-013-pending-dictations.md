# Fork ADR-013 :: Dictations with nowhere to go wait on the clipboard

Last updated: `2026.10.09` · Status: **built**, tested by the user (second version)

> A dictation said where there is no text field — over a web page being
> reviewed, a button — is not pasted into nothing: it joins the dictations
> before it on the clipboard, a paragraph each, and the notch says
> "3 dictées en attente · ⌘V pour coller". ⌘V in any field (Claude's input,
> say) pastes the whole block, to rework there and send; or a dictation in a
> field brings the block along. No mode, no window, no gesture.

## 1. Decision

- **Where:** `TextDelivery`, when it would paste (one switch, ~10 lines in
  an upstream file), asks `PendingDictations.route` (`Input/PendingDictations.swift`).
  If the focused element is not a text field, the block is copied to the
  clipboard instead of pasted; else the dictation pastes as before, after
  the waiting block if any.
- **"Not a text field"** — only when the element says so: its role is one
  that holds no text (`AXWebArea`, `AXButton`, `AXLink`, lists, tables…)
  **and** its value can't be set. Seen in the log as the focus of pastes
  that found no field: Dia's `AXWebArea` and `AXButton` (6 times in the
  corpus). An element that says nothing (Electron still building its tree),
  or an `AXGroup`, counts as a field: a dictation is never held back from a
  field on a guess.
- **The block** joins dictations with a blank line; each is trimmed, no
  `Spacing`. It leaves in one of two ways, then starts over:
  - **a dictation in a field** pastes the block first, then itself (the
    user's first test expected it; the first version dropped the block);
  - **⌘V**: while a block waits, Parrot reads the focused field once a
    second (`FocusSnapshot` + `AXValue`, skipped in secure fields) and
    clears the block when the field holds the first dictation's first 40
    characters. Nothing is logged but "waiting dictations pasted".
  With neither, it starts over after 10 minutes without a new dictation.
- **The notch** shows the count after each such dictation
  (`NotchOverlay.dictationFinished`, or the pill on a screen without a
  notch). The log says the role and the count, never text.
- The corpus records the dictation as usual; `CorrectionWatch` finds no
  field and marks it `unreadable`.

## 2. Options considered

| Option | Why not |
|---|---|
| Double-tap the dictation key to open a scratch pad under the notch (the user's first idea) | A mode to remember; the pad takes the keyboard from the page being read; it must guess where to send the text back; DynamicNotchKit shows, it doesn't edit text. Kept for later if reworking before pasting turns out to matter. |
| Watch keystrokes for ⌘V | Needs keyDown events in the key tap; upstream deliberately listens to modifiers only, so no keystroke ever reaches Parrot. |
| Put the block on the clipboard as a promise (`NSPasteboardItemDataProvider`), and take the request for its data as the paste | Tested 2026-10-09: macOS asked for the data 0.1 s after it was written, before any paste (Dia frontmost; Universal Clipboard or Dia itself reads every change), and two pastes after that asked nothing. The request says nothing about a paste. |
| Only the 10-minute expiry for ⌘V | The user's first test: paste the block, dictate over the page again, and the new dictation joined the old block. |
| Paste anyway (⌘V) and also gather | ⌘V on a focused button or list can do things in some apps; and if the guess were wrong, a field would get the whole block twice over. |
| A setting for the delay or the separator | Product rules: one default. |

## 3. Design Implications

- **Tested 2026-10-09** in Dia (pages report `AXWebArea`) and bb: blocks of
  1–3 dictations, ⌘V detected ("waiting dictations pasted") and the block
  carried along by a dictation in a field; no field dictation held back.
  The role an app reports is still the whole bet elsewhere. An app that reports a non-text role while a field is
  focused would keep its dictations on the clipboard — visible at once in
  the notch, nothing lost, ⌘V pastes it. The log line names the role to fix
  the list.
- A field that doesn't expose its text (some terminals and Electron
  fields) hides the ⌘V: the block then lasts until a dictation reaches a
  field or 10 minutes pass. The notch count shows it ("4 dictées" where 1
  was expected).
- A very short first dictation ("ok.") could be "found" in an unrelated
  field and clear the block early; the block stays on the clipboard, only
  the next dictation starts a new one.
- One Accessibility read of the focused field per second while a block
  waits, 10 minutes at most, each bounded by the 0.25 s timeout.
- Two AX reads more per delivery (role, settable), each bounded by the
  0.25 s messaging timeout; to watch in the latency log's `deliver`.

## 4. When to Revisit

- A week of use: grep `nowhere to paste` for roles, and false positives.
- The 10 minutes feel wrong (blocks lost too early, or stale ones joined).
- Reworking before pasting is missed → the notch scratch pad.
