# Fork ADR-019 :: Offering to learn a correction as the user makes it

Last updated: `2026.11.19` · Status: **built**, to be judged by the user over a few days

> The user fixes a word by hand in a pasted dictation ("pip" → "Peep"). Two
> seconds after they stop typing, the correction comes out of the notch:
> « ~~pip~~ → Peep · Ajouter · ✕ », over a bar that drains in 8 s. One click
> writes it to the dictionary, ✕ drops it for good. Left alone it goes back
> into the notch and waits. Resting the pointer on the notch shows every
> correction waiting, and so does the menu-bar panel, notch or not. The
> nightly review (fork-009) keeps running behind it. The user asked for this
> after looking at FluidVoice: "je suis nudgé au bon moment"; the notch, the
> bar and the list on hover are the user's design (2026-11-19).

## 1. Why

- **The nightly review misses most corrections.** The corpus on
  2026-11-19 holds 685 dictations the user edited, with 429 substitutions of
  one to three words, and 344 distinct pairs. Only 21 single-word pairs came
  back twice or more. The review wants two sightings and a prudent judge, so
  a correction made once is never learned.
- **The user knows what the judge can't.** The user added Peep, BB and Owl
  by hand "parce que ça me saoulait": they never say "bébé", so
  "bébé → BB" is safe for them. No rule or judge can know that.
- **The wrong side is often a real word.** Among the most frequent pairs:
  cloud → Claude, vert → verre, glace → glass, serait → soit, héros → hero.
  A dictionary entry is a rewrite, everywhere and every time: adding
  "vert → verre" silently would rewrite every real "vert". So Parrot asks
  first; it doesn't add on its own.

## 2. What the others do (read 2026-11-19)

| | FluidVoice 1.6.3 | OpenWhispr |
|---|---|---|
| Watch | AX observer, 30 s after the paste | native AX monitor, 30 s |
| Settled after | 3 s | 1.5 s |
| Kept | one word ↔ one word, ≥ 2 alphanumerics, ≤ 40 chars, English inflections rejected | word-level diff, corrected word ≥ 3 letters, ~130 common words skipped, > 50 % substituted = rewrite |
| What it learns | the pair, plus Parakeet vocabulary boosting | the corrected word, as a hotword (bias, no rewrite) |
| How | asks: "Learn this word?" panel, 10 s, Escape | adds at once, toast « Added · Undo » 6 s |
| Refused | 7-day cooldown; 3 refusals = silent until relaunch | — |

Sources: [FluidVoice 1.6.3](https://newreleases.io/project/github/altic-dev/FluidVoice/release/v1.6.3),
[OpenWhispr dictionary](https://docs.openwhispr.com/help/customise/custom-dictionary),
and both repositories' code.

OpenWhispr can add without asking because a hotword only nudges the model;
in Parrot a dictionary entry rewrites, so FluidVoice's ask-first is the
right model. The user chose it: « Oui, ça me va demander d'abord. »

## 3. Decision

- **`CorrectionWatch` (fork-005) feeds it.** The watch already follows the
  pasted span each second for up to 60 s. It now hands an edit to
  `onEdit` when the span has stayed the same for 2 s (`settledDelay`; a
  word half retyped is no correction), and when focus leaves the field (a
  message sent right after the fix). It reports each distinct edit once.
  It never reports while the next dictation is recorded: that release ends
  the watch without a report.
- **The watch runs with the corpus off too.** It compares in memory and
  writes nothing; the corpus record is written only when the corpus is on
  (on by default since fork-009).
- **`CorrectionOffer` (`Dictionary/CorrectionOffer.swift`) decides**, pure
  and tested. It offers every substitution from `WordAlignment` that meets
  all of these:
  - one to three words on each side;
  - at most 2 substitutions in the edit (more is a rewrite);
  - the wrong side has ≥ 3 letters (two-letter words are grammar: en → on,
    la → le, va → a — seen in the corpus);
  - the right side has ≥ 2 letters (bébé → BB);
  - each side is ≤ 40 characters;
  - the fix is not a prefix of the paste (a word being retyped);
  - the pair is not already in the dictionary;
  - the wrong side is not one of the user's own words;
  - the user has not closed the pair (✕).

  The right side takes the dictionary's spelling when it has the word
  (claude → Claude), and drops a capital that only started the sentence
  ("Vert" → "Verre" offers "verre", or every "verre" would gain a capital).
- **No phonetic filter.** `FrenchPhonetics` gives pip → Peep and all → owl,
  which the user wants, 0.33, the same as rewordings like je → tu. It can't
  tell them apart; the user can.
- **The queue (`Dictionary/PendingCorrections.swift`).** Every correction
  offered waits there until the user answers, newest first, one entry per
  pair (seen again, it moves up). It lives in memory only, at most 20, and
  each entry goes away by itself after 24 h, unanswered: the list never
  becomes a backlog. A first version (same day) offered only the first
  correction of an edit in a glass panel; a second fix in the same
  dictation was never offered, and a timed-out offer came back instead of
  the next one.
- **Out of the notch, live (`UI/NotchOffers.swift`).** The newest correction
  of the edit unfolds under the notch: the wrong word struck through, an
  arrow, the right word, « +2 » when others wait, a glass « Ajouter », a ✕,
  and under them a bar that drains in 8 s. The pointer over it holds the
  bar, and 3 s are left when it goes. Answered, the next correction of the
  same edit follows. Timed out, everything stays pending and the notch
  folds.
- **On hover, the list.** With nothing shown and something pending, the
  pointer resting 0.3 s on the notch unfolds the list (6 at most), each
  with ✓ and ✕. It folds 0.5 s after the pointer leaves, or once empty.
  A global mouse-moved monitor watches the notch's rectangle; mouse
  monitoring needs no permission. Nothing shows at rest: no badge.
- **In the menu-bar panel, for every Mac.** The pending corrections are
  rows under Dictionnaire in the Dictée card, each with ✓ and ✕ (5 at
  most). Without a notch there is nothing to hover, and an invisible zone
  in the menu bar would never be found; the panel is the place that works
  everywhere. The notch's hover is the shortcut.
- **Without a notch** (Mac without one, external screen): the live offer
  slides down as DynamicNotchKit's floating card at the top centre, with
  system colours instead of the notch's black. It goes to the screen of the
  frontmost window.
- **A dictation always wins.** Pressing the hotkey gives the notch back to
  the recording indicator; what was shown stays pending. Nothing comes out
  while dictating.
- **Clickable without stealing the keyboard.** The indicator stays
  click-through. For corrections the notch's window takes clicks
  (`ignoresMouseEvents = false`) but never becomes key, so the field being
  corrected keeps the keyboard and `CorrectionWatch` keeps watching.
  - `becomesKeyOnlyIfNeeded`: a SwiftUI button doesn't ask for key
    (`needsPanelToBecomeKey` false, probed 2026-11-19).
  - The buttons sit in a nested hosting view that accepts the first click
    (`FirstClick`); DynamicNotchKit's own returns false for
    `acceptsFirstMouse` (probed).
- **Ajouter** writes the pair with the review's `DictionaryEditor.add`: a
  Replaces item on the word's line, or a new line, with the day's backup in
  `dream/backups`. It is the user's entry, not the review's: not in
  `learned.json`, so the review's audit never removes it.
- **✕ is final.** It notes the pair in `dictionary-refusals.json`
  (Application Support, owner-only, pairs only). The pair is never offered
  again, and the nightly review stops proposing it (`buildCandidates` skips
  it): what the user declined, the judge must not add at night. A timeout
  is no answer: the correction stays pending. (The first version counted
  timeouts as refusals and dropped a pair after 2; the 3 recorded that way
  on 2026-11-19 were cleared when the meaning changed.)
- **No setting.** It is on for everyone. Its cost is a notch that folds
  back by itself.
- **Logs**: counts and the answer only (« 2 correction(s) offered, 3
  pending », « added by the user », « refused by the user »), never the
  words.

## 4. Options considered

| Option | Why not |
|---|---|
| Add at once with « Annuler » (OpenWhispr) | A rewrite of a real word (vert → verre) would take effect before the user sees it; OpenWhispr's hotwords are harmless, Parrot's entries aren't. |
| Lower the review's threshold to one sighting | Night-time only, and the judge can't know the user never says "bébé". |
| A phonetic or spell-check filter | Measured above: it rejects what the user wants. The 2 refusals do the filtering instead. |
| Escape to dismiss (FluidVoice's event tap) | A global key tap for one panel; the ✕ and the timeout are enough. |
| A glass panel under the menu bar (the first version) | Replaced by the notch at the user's request: the corrections come from where the dictation is shown. |
| A visible tab under the menu bar while corrections wait | A standing reminder to act: against « information over controls ». |
| An invisible hover zone in the menu bar on screens without a notch | Nobody would find it; the menu-bar panel lists them instead. |
| Our own notch-shaped window | Not needed: DynamicNotchKit's window takes clicks without becoming key once configured (above). |
| Parakeet vocabulary boosting (FluidVoice, OpenWhispr's idea) | FluidAudio 0.17.4 has it on its CTC path (`VocabularyBoostingSession`); not checked whether it applies to Parakeet Ultra in French. A lead, below. |

## 5. Expected load

The corpus shows 4–39 edited dictations a day (median ~19), and about half
contain a substitution. So expect around 5–15 offers a day at first. The
number should fall as accepted pairs enter the dictionary and refused ones
drop out.

## 6. When to revisit

- After a few days: count `offered`, `added by the user` and `refused by
  the user` in the log. If most are refused, the filters are too loose (look at which kinds); if
  almost all are added, consider adding without asking for non-words.
- The user finds it intrusive: lengthen the settled delay, or offer only
  pairs seen twice.
- Vocabulary boosting works for Parakeet Ultra: an accepted real-word pair
  (vert → verre) could become a bias instead of a rewrite.
- The notch's look can't be seen by the agent (offscreen snapshots don't
  draw glass buttons; no Screen Recording): the user's eye judges it, as
  fork-017. Snapshots: `OFFER_SNAPSHOT=<png> swift test --filter
  CorrectionOfferTests/testSnapshot`.
- A click on « Ajouter » must leave the cursor in the field: checked by the
  user, not by a test.
