# Fork ADR-019 :: Offering to learn a correction as the user makes it

Last updated: `2026.11.19` · Status: **built**, to be judged by the user over a few days

> The user fixes a word by hand in a pasted dictation ("pip" → "Peep"). Two
> seconds after they stop typing, the correction comes out of the notch:
> « ~~pip~~ → Peep · Ajouter · ✕ », over a bar that drains in 5 s. One click
> writes it to the dictionary, ✕ drops it for good. Left alone it goes back
> into the notch and waits 2 minutes; unanswered by then, it is refused, as
> if by ✕. The pointer on it, or resting on the notch,
> unfolds every correction waiting, with « Tout ajouter » and « Tout
> refuser »; so does the menu-bar panel, notch or not. The
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
- **A dictation pasted by hand is watched too** (2026-11-19). When Parrot
  leaves the text on the clipboard instead of pasting it — focus moved
  during the dictation (upstream copies it then), or no text field
  (fork-013's block) — `Corpus/ClipboardPasteWatch.swift` reads the
  focused field twice a second for its opening 40 characters, and hands
  it to `CorrectionWatch` once found, as if Parrot had pasted it. It
  stops when the clipboard changes (something else copied), at the next
  dictation, or after 10 minutes. Seen in the log the same day: a 31 s
  dictation whose focus moved went to the clipboard, the user pasted it
  and fixed « Lark », and nothing was offered. A block of several
  dictations is watched for offers only: no one corpus record holds its
  text. Twice a second rather than fork-013's once, so an edit made right
  after the paste isn't missed (the watch must find the text as pasted).
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
  In return the replacement puts the capital back where the word it
  replaces started a sentence (`Dictionary/SentenceStart.swift`, one call
  in upstream's `DictionaryReplacer`): "C'est bon. Vert d'eau." gives
  "C'est bon. Verre d'eau.", not "verre" as before 2026-11-19. Elsewhere
  the user's spelling stands.
- **No phonetic filter.** `FrenchPhonetics` gives pip → Peep and all → owl,
  which the user wants, 0.33, the same as rewordings like je → tu. It can't
  tell them apart; the user can.
- **The queue (`Dictionary/PendingCorrections.swift`).** Every correction
  offered waits there until the user answers, newest first, one entry per
  pair (seen again, it moves up). It lives in memory only, at most 20.
  **Unanswered for 2 minutes, a correction is refused**, recorded as a ✕
  would be. The user, 2026-11-19: « ne pas répondre, c'est égal à
  refuser, ça m'évite un clic »; the 24 h of the first version left a list
  that was in the way. A timer prunes it when the oldest runs out; a list
  shown on the notch folds once emptied that way. A first version (same day) offered only the first
  correction of an edit in a glass panel; a second fix in the same
  dictation was never offered, and a timed-out offer came back instead of
  the next one.
- **Out of the notch, live (`UI/NotchOffers.swift`).** The newest correction
  of the edit unfolds under the notch as one row: the wrong word struck
  through, an arrow, the right word, « +2 » when others wait, a glass
  « Ajouter », a ✕, and under them a bar that drains in 5 s (8 s at first;
  the user found it long). Answered, the next correction of the same edit
  follows. Timed out, everything stays pending and the notch folds.
- **Everything at once, on hover.** The pointer on the live row or on the
  notch above it, or resting 0.3 s on the notch when nothing is shown,
  unfolds every pending correction (6 at most) under that first row, which
  stays where it was, each with Ajouter and ✕, and « Tout ajouter » /
  « Tout refuser » when there are several. No countdown then; it folds
  0.5 s after the pointer has left both the notch and the rows, or once
  empty. The user wanted an overview rather than one at a time
  (2026-11-19). While something is shown, one test says where the pointer
  is: the notch and the rows as one rectangle, read every 50 ms. When
  nothing is shown, a global mouse-moved monitor watches the notch's
  rectangle; mouse monitoring needs no permission. Nothing shows at rest:
  no badge.
  - The first version had two tests: SwiftUI's hover on the rows, and the
    notch monitor only while nothing was shown. The pointer on the notch
    did nothing during a live offer, then unfolded the list the moment the
    offer timed out, and then the list vanished (seen by the user,
    2026-11-19; not proven, but the only path that folded it unanswered
    was the pointer leaving the rows). The log now says what unfolds
    and folds the notch, and why: « list unfolded (pointer on the offer) »,
    « corrections folded (timed out | pointer left | answered | dictation) ».
- **The look** (2026-11-19, the user's eye): the rows glide in and out as
  the notch grows and shrinks (0.55 s, eased: 0.3 s was found quick), the
  rows under the first coming in one after another, 70 ms apart; opened
  from the notch at rest, the first row comes out with the notch and the
  others follow (how, in `docs/fork-ui-notes.md`), the buttons are drawn as in an active window
  (the notch never becomes key, and inactive controls turn grey), and ✕ is
  a small round glass button, as everywhere in the panel.
- **In the menu-bar panel, for every Mac.** The pending corrections are
  rows under Dictionnaire in the Dictée card, each with Ajouter and ✕ (5
  at most), and « Tout ajouter » / « Tout refuser », which answer all of
  them. Without a notch there is nothing to hover, and an invisible zone
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
  it): what the user declined, the judge must not add at night. The live
  offer's 5 s running out is no answer: the correction stays pending, 2
  minutes from when it was offered; then silence is a refusal, final like
  ✕. (The first version counted each 5 s timeout as a refusal and dropped a
  pair after 2; the user then wanted no answer to mean wait, and later,
  the same day, 2 minutes of no answer to mean no.)
  - The risk: a correction made while the user looks elsewhere is lost
    for good, the nightly review included. Revisit if a pair the user
    wanted never comes back.
- **No setting.** It is on for everyone. Its cost is a notch that folds
  back by itself.
- **Logs**: counts and the answer only (« 2 correction(s) offered, 3
  pending », « added by the user », « refused by the user », « 1
  correction(s) unanswered for 2 min, refused »), never the words.

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
