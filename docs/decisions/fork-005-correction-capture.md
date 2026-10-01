# Fork ADR-005 :: Capturing the user's corrections

Last updated: `2026.10.01`

> With the corpus on (fork-003), Parrot follows each pasted transcript in its
> text field until the user leaves it, and writes beside the recording what
> was pasted and what the span became. The corrections the user makes are the
> errors that matter to them, and future dictionary entries. Data first; how
> to use it comes later.

## 1. Decision

- **`CorrectionWatch`** (`Corpus/CorrectionWatch.swift`), started after each
  delivered transcript when the corpus is on:
  1. 0.4 s after delivery (the target app pastes asynchronously; the injector
     restores the clipboard at 0.25 s), read the focused field over
     Accessibility and find the pasted text: the occurrence ending closest to
     the cursor.
  2. Keep 16 characters on each side as anchors; every second, while focus
     stays in that field, read the field and take the text between the
     anchors (the before-anchor occurrence closest to the original position).
  3. Stop when focus leaves the field (the last look stands — a sent message
     clears the field), at the next release, or after 60 s (one last look).
- **Record** `<recording>.json` beside the WAV, owner-only:
  `model`, `app` (bundle id), `pasted`, `final`, `status`
  (`edited` / `unchanged` / `unreadable`), `watched` (seconds). Only the span,
  never the rest of the field. The log says the status, never text.
- **Accessibility reads, with one write for Electron.** An app that names no
  focused element is asked to set `AXManualAccessibility` (Electron's
  documented switch for assistive tools, what VoiceInk does), then looked at
  again for up to ~5.6 s while Chromium builds its tree. It stays on until
  Parrot quits (then turned off), and is left alone when it was already on.
  Never `AXEnhancedUserInterface`, which took focus away from Claude's input
  (OpenWhispr #1116).
- **The log names the failing step** for an unreadable field (no focused
  element, secure field, value unreadable with its AX code, pasted text not
  found with the field's length): sizes and codes, never text.
- **Transcript text on disk, deliberately.** Upstream's ADR-004 forbids it
  since 0.0.5 leaked dictations through a world-readable `/tmp` log. The user
  decided to keep it to analyse and improve recognition; it is limited to the
  opt-in corpus, in the same owner-only folder as the audio, which is as
  sensitive. Logs stay text-free.
- Upstream edit: one line in `DictationController` after a successful
  delivery; `RecordingCorpus.keep` now returns the recording's name.

## 2. Rationale

How others do it (sources read 2026-10-01):

| App | Detection | Stores | Use |
|---|---|---|---|
| OpenWhispr | AX observer on value changes, whole field compared to the paste, 30 s | the corrected word only, auto-added | Whisper prompt, LLM context |
| VoiceInk 2.20 | paste located from the cursor, one snapshot when focus leaves (60 s), 16-char anchors | pending fragments on disk; LLM decides a wrong→right pair | word replacements and vocabulary |
| Wispr Flow | undocumented (auto-learn exists) | – | dictionary |

Parrot follows VoiceInk's location and anchors (robust to the span's length
changing), but polls the field each second instead of one final snapshot,
because a sent chat message clears the field before focus moves. It stores
both sides of the correction rather than a learned word: OpenWhispr's
auto-added words polluted dictionaries and overflowed prompts (#358, #399),
and its English-only common-word filter would learn French homophone fixes
(ces→ses, a→à) as words.

First run (2026-10-01), one dictation each: Notes `unchanged`, watched 9 s;
bb (`dev.bb.desktop`) and Notion (`notion.id`), both Electron: `no focused
element`. Parrot has Accessibility (its hotkey only starts once
`AXIsProcessTrusted()`), so the apps, not the grant, were the cause; the same
dictations logged upstream's `before cursor: unknown`.

Second run: bb took the request (`AX 0`) but answered `-25212` (no value) to
both focused-element queries for ~2.75 s, while its focused window answered
at once; turning the attribute off after each watch made every dictation
wait again. Kept on, later dictations in bb were read at once.

Third run: `edited` records whose `final` was the dictation's first word.
Cause: alone in its field, a paste is followed only by the space `Spacing`
adds, so the after-anchor was " " and matched the first space inside the
span. Whitespace-only anchors now count as the field's ends, and an emptied
span (a sent message) keeps the last look instead of recording "". The four
affected records were rewritten as `unreadable`.

Fourth run: bb's emptied input reads as its placeholder ("Ask for a
follow-up. @ to mention files…", 71 units — also the "71 units, cursor 0"
of the second run), recorded as the final text. A value equal to the field's
`AXPlaceholderValue` now counts as empty. Of the two affected records, one
got its final text back from the message the user sent; the other became
`unreadable`.

## 3. Design Implications

- Text typed right after a dictation pasted at the end of a field joins the
  span; an alignment of `pasted` and `final` sees it as an insertion at the
  end.
- Apps that don't expose their text over Accessibility (terminals, some
  Chromium/Electron fields) give `unreadable` with `pasted` only — still a
  draft reference for the audio.
- While a watch runs in an Electron app, Chromium keeps its accessibility
  tree: a little CPU and memory in that app for up to a minute. The first
  dictation in an app may still be unreadable if the tree isn't ready in
  about 2 s.
- Up to one Accessibility read per second for a minute after a dictation, on
  the main thread, each bounded by the 0.25 s messaging timeout.
- Edits are not all transcription errors (the user also rewrites); the data
  needs alignment and review before it feeds a dictionary or a WER.

## 4. When to Revisit

- A few hundred records → align `pasted`/`final`, classify edits (word
  substitutions, casing, punctuation, rewrites), and decide: dictionary
  suggestions to accept, references for the benchmark, or both.
- A target app misbehaves while watched → exclude it, or stop polling.
