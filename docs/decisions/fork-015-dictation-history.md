# Fork ADR-015 :: The last day's dictations, to copy again

Last updated: `2026.11.16` · Status: **built**, to be tested by the user

> The panel (fork-010) opens on « Dernières dictées »: the last 24 hours'
> dictations, newest first, each with its time and a button that copies it.
> A paste that landed nowhere, a field cleared by mistake, a crash: the user
> copies the dictation back instead of saying it again. Nothing to set.

## 1. Decision

- **`DictationHistory`** (`Pipeline/DictationHistory.swift`) holds the
  entries (date, text); **`HistoryProcessor`**, the last processor (one line
  in `Daemon`), adds the text as it is about to be pasted — dictionary and
  capitalization applied — and returns it unchanged.
- **Recorded before delivery**, so the case that matters most is covered: a
  failed paste (`DictationController` returns before the corpus records
  anything), and dictations gathered on the clipboard (fork-013), one entry
  each.
- **24 hours, rolling**, not "today": a dictation at 23:58 doesn't vanish at
  midnight. Older entries are dropped at each new dictation and each time
  the panel opens. Times read « 14:32 », or « hier 23:58 ».
- **On disk**, `~/Library/Application Support/parrot/history.json`, 0600,
  rewritten off the main thread after each dictation: it survives a crash or
  a restart. A file cut short by a crash is dropped (logged), not fatal.
- **The panel**: a section first, above the settings — what the user opens
  it for. **Folded** (the default), it shows the latest dictation on one
  line; the title's chevron and count unfold the rest. **Unfolded**, each
  dictation is a soft card, two lines, its time on the right; on hover the
  time becomes a copy icon, a click anywhere on the card copies and shows a
  check. The list scrolls past about five and fades at its edges, so the
  panel still fits a MacBook screen. Unfolding slides the others in under
  the latest card, which stays put, while the popover animates its height:
  the panel's hosting controller publishes its ideal size
  (`sizingOptions = .preferredContentSize`), which `NSPopover` follows and
  animates. Three tries before that, all wrong: see docs/fork-ui-notes.md.
  Folded or not is remembered while
  Parrot runs, not saved: not a setting. (First version, 2026-11-16: always
  unfolded, a hard-cut scrolling list with a copy button per row — the user
  found it ugly.)
  Copy is a plain `NSPasteboard` write: the user asked for it, so clipboard
  managers may see it (unlike the paste's concealed marker, fork-006).
- **Independent of the corpus**: a user who turns the corpus off still gets
  it. The corpus is for the benchmark and the review; this is 24 hours.

## 2. Options considered

| Option | Why not |
|---|---|
| Read the history from the corpus (fork-003/005), which already keeps the text | Written only after a pasted dictation's correction watch ends (up to 60 s, lost in a crash), never after a failed paste, and off for anyone who turns the corpus off. |
| Memory only | Lost exactly when Parrot crashes or restarts — one of the cases the user named. |
| Calendar day ("today") | Late-evening dictations vanish at midnight. |
| Search, delete, pin, a longer history, a window of its own | Not asked; each a control. Revisit if the user looks for something older. |
| A setting to turn it off | Product rules. The file holds a day; the corpus beside it holds far more. |

## 3. Design Implications

- **Transcript text on disk**, against upstream's ADR-004, as in fork-005:
  owner-only, a day at most, in the same folder as the corpus. Logs stay
  text-free (errors only).
- `process` gains one array insert and a queued write; `deliver` is
  untouched. To check in the latency log's `process` field.
- A dictation that was pasted, then corrected by the user, shows as pasted,
  not as corrected.

## 4. When to Revisit

- The user reaches for a dictation older than a day.
- `process` above a few ms in the latency log.
