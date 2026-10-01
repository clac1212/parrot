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
- **Read-only Accessibility**: no attribute is ever set on the target app
  (OpenWhispr's `AXEnhancedUserInterface` took focus away from Claude's input,
  OpenWhispr #1116; VoiceInk sets `AXManualAccessibility` on Chromium apps).
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

## 3. Design Implications

- Text typed right after a dictation pasted at the end of a field joins the
  span; an alignment of `pasted` and `final` sees it as an insertion at the
  end.
- Apps that don't expose their text over Accessibility (terminals, some
  Chromium/Electron fields) give `unreadable` with `pasted` only — still a
  draft reference for the audio.
- Up to one Accessibility read per second for a minute after a dictation, on
  the main thread, each bounded by the 0.25 s messaging timeout.
- Edits are not all transcription errors (the user also rewrites); the data
  needs alignment and review before it feeds a dictionary or a WER.

## 4. When to Revisit

- A few hundred records → align `pasted`/`final`, classify edits (word
  substitutions, casing, punctuation, rewrites), and decide: dictionary
  suggestions to accept, references for the benchmark, or both.
- A target app misbehaves while watched → exclude it, or stop polling.
