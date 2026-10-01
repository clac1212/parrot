# Fork ADR-006 :: The transcript stays on the clipboard

Last updated: `2026.10.01`

> In paste mode, Parrot writes the transcript to the clipboard for good and
> posts ⌘V, instead of borrowing the clipboard for 0.25 s and restoring it.
> A dictation released where no text field had focus is no longer lost: it
> is one ⌘V away.

## 1. Decision

- `TextInjector.inject` in paste mode calls `PasteboardSession.copy` (the
  path upstream already uses when focus moved during a dictation) then posts
  ⌘V. No restore is scheduled. One line in an upstream file.
- The item keeps upstream's `org.nspasteboard.ConcealedType` marker, as the
  focus-moved fallback does: clipboard managers keep it out of their history.
- `type-unicode` mode is unchanged and leaves the clipboard alone.

## 2. Rationale

The user dictates, sometimes without a text field focused, and had to
dictate again: with focus unchanged between press and delivery, Parrot sent
⌘V into nothing and then restored the old clipboard.

| Option | Why not |
|---|---|
| Keep upstream's restore | The case above loses the dictation. |
| Detect "no text field" and copy instead of paste | Unreliable: Electron apps (bb, Notion) name no focused element until asked (fork-005), so Parrot would copy instead of paste in the user's main apps. |
| A "paste last dictation" shortcut and menu item (Wispr Flow's way) | A new feature to learn; the user wanted no new feature, just the clipboard. |

## 3. Design Implications

- Each dictation replaces whatever the user had copied before (text, image,
  files). That is the trade the user chose.
- The clipboard holds the text as pasted, with the trailing space (and a
  leading one when needed) that `Spacing` adds.
- Upstream's `PasteboardSession.paste` and its restore logic stay in the code,
  unused by the app, to keep the upstream diff small.

## 4. When to Revisit

- The user misses their previous clipboard content → a "paste last dictation"
  shortcut instead.
- Upstream changes delivery (`TextInjector`, `TextDelivery`) → re-apply the
  one line.
