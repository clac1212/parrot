# Fork ADR-014 :: The first letter follows the text before the cursor

Last updated: `2026.10.14` · Status: **built**, tested by the user

> Parakeet capitalizes every transcript as if it started a sentence. A
> dictation in the middle of one ("Bonjour, | Je voulais…") now starts with a
> small letter, and one after a sentence or at the start of a field with a
> capital. Automatic, no setting (the idea came from another app's
> "Adapt capitalization" switch).

## 1. Decision

- **`CapitalizationProcessor`** (`Pipeline/Capitalization.swift`), after the
  dictionary's processor (one line in `Daemon`). A processor, as upstream's
  architecture asks, so the corpus and `CorrectionWatch` record the text that
  was pasted.
- **The lead**: up to 16 UTF-16 units before the insertion point
  (`FocusedElement.textBefore`, one `AXStringForRange` read). Skipping
  spaces and what closes (`)`, `»`, `”`…): a newline, `.` `!` `?` `…`, or the
  start of the field → a capital; a letter, digit, `,` `;` `:` → a small
  letter; anything else, or an app that doesn't say → **nothing changes**.
  Dashes give nothing: one that starts a line is a list item.
- **Only safe changes**: a small letter only for a word written "Like
  this" — never "PR", "PostHog", "I", a word the user's dictionary spells
  with a capital (terms and replacement targets), or one NaturalLanguage
  names a person, place or organization. A capital only for a word with
  none ("diorama" → "Diorama", not "iPhone").
- Nothing changes while dictations wait on the clipboard (fork-013): the
  block is pasted first.

## 2. Measurements

The user's corpus, 778 dictations (2026-10-14):

- The user lowered a pasted first capital once ("De" → "de") — the gain
  shows little in what they bothered to correct.
- First words are almost always common: "Ok" 100, "Et" 82, "Je" 52… A proper
  name first came twice ("Sparrow", "Jay"): the only case where a small
  letter is wrong, and the dictionary or NaturalLanguage covers part of it.
- NaturalLanguage alone is not enough: on sentence starts it names
  "Claude" and "Marie", misses "Paris", "César", "Hatch", "Notion". The
  French spell checker accepts every lower-cased name: useless here.
- Latency, last 100 dictations before: `process` median 0 ms (max 1),
  `deliver` median 4 ms. After, the user's first 5 dictations: `process`
  median 2 ms (max 6), `deliver` median 2 ms (max 10) — a few ms, as
  expected. The user's test (mid-sentence, after a period, a name first)
  behaved as described.

## 3. Options considered

| Option | Why not |
|---|---|
| A setting, like the app that inspired it | Product rules: right for everyone, so on. |
| Read only the character before the cursor (as `Spacing` does) | After "Bonjour, " it is a space: the comma decides. |
| The spell checker to tell names from words | Accepts "claude", "paris", "hatch" in French. |
| Lower-case after a dash | A dash at the start of a line is a list item. |

## 4. Design Implications

- One more Accessibility read per dictation, bounded by the 0.25 s
  timeout; NaturalLanguage's tagger only when a capital would be lowered.
- A proper name neither the dictionary nor NaturalLanguage knows, said at
  the start of a dictation in mid-sentence, loses its capital (≈ 1 in 400
  dictations in the corpus). Adding it to the dictionary fixes it for good.
- Terminals report position 0 wherever the cursor is: there, as in any
  field whose text can't be read, nothing changes.

## 5. When to Revisit

- `process` time in the latency log above a few ms.
- The corpus shows capitals the user puts back.
