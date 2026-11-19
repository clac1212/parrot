# Fork ADR-019 :: Offering to learn a correction as the user makes it

Last updated: `2026.11.19` · Status: **built**, to be judged by the user over a few days

> The user fixes a word by hand in a pasted dictation ("pip" → "Peep"). Two
> seconds after they stop typing, a small glass panel appears at the top of
> the screen: « pip → Peep · Ajouter au dictionnaire ? ». One click writes it
> to the dictionary. Otherwise the panel leaves on its own after 8 s. The
> nightly review (fork-009) keeps running behind it. The user asked for this
> after looking at FluidVoice: "je suis nudgé au bon moment".

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
  and tested. It offers the first substitution from `WordAlignment` that
  meets all of these:
  - one to three words on each side;
  - at most 2 substitutions in the edit (more is a rewrite);
  - the wrong side has ≥ 3 letters (two-letter words are grammar: en → on,
    la → le, va → a — seen in the corpus);
  - the right side has ≥ 2 letters (bébé → BB);
  - each side is ≤ 40 characters;
  - the fix is not a prefix of the paste (a word being retyped);
  - the pair is not already in the dictionary;
  - the wrong side is not one of the user's own words;
  - the pair has not been let go twice.

  The right side takes the dictionary's spelling when it has the word
  (claude → Claude), and drops a capital that only started the sentence
  ("Vert" → "Verre" offers "verre", or every "verre" would gain a capital).
- **No phonetic filter.** `FrenchPhonetics` gives pip → Peep and all → owl,
  which the user wants, 0.33, the same as rewordings like je → tu. It can't
  tell them apart; the user can.
- **The panel (`UI/CorrectionOfferPanel.swift`).** Glass (`NSGlassEffectView`;
  material before macOS 26), centred under the menu bar, where the dictation
  indicator is. It shows the wrong word struck through, an arrow, the right
  word, « Ajouter au dictionnaire ? », a glass « Ajouter » and a ✕.
  - It never takes the keyboard: it is a non-activating panel that doesn't
    become key, so the field keeps focus and the watch keeps going.
  - Its buttons answer the first click (`acceptsFirstMouse`).
  - It stays 8 s, held while the pointer is over it, then 3 s more after
    the pointer leaves.
  - A new offer replaces one still up.
- **Ajouter** writes the pair with the review's `DictionaryEditor.add`: a
  Replaces item on the word's line, or a new line, with the day's backup in
  `dream/backups`. It is the user's entry, not the review's: not in
  `learned.json`, so the review's audit never removes it.
- **✕ or the timeout** counts the pair once in `dictionary-refusals.json`
  (Application Support, owner-only, pairs only). After 2, the panel never
  offers the pair again, and the nightly review stops proposing it
  (`buildCandidates` skips it): if the user said no twice, the judge must not
  add it at night.
- **No setting.** It is on for everyone. Its cost is a panel that goes away
  by itself.
- **Logs**: word counts and the answer only (« offered a correction (1 → 1
  words) », « added by the user », « let go »), never the words.

## 4. Options considered

| Option | Why not |
|---|---|
| Add at once with « Annuler » (OpenWhispr) | A rewrite of a real word (vert → verre) would take effect before the user sees it; OpenWhispr's hotwords are harmless, Parrot's entries aren't. |
| Lower the review's threshold to one sighting | Night-time only, and the judge can't know the user never says "bébé". |
| A phonetic or spell-check filter | Measured above: it rejects what the user wants. The 2 refusals do the filtering instead. |
| Escape to dismiss (FluidVoice's event tap) | A global key tap for one panel; the ✕ and the timeout are enough. |
| The notch as the panel | DynamicNotchKit's window ignores the mouse (fork-002); a click there would need hover handling in a vendored library. |
| Parakeet vocabulary boosting (FluidVoice, OpenWhispr's idea) | FluidAudio 0.17.4 has it on its CTC path (`VocabularyBoostingSession`); not checked whether it applies to Parakeet Ultra in French. A lead, below. |

## 5. Expected load

The corpus shows 4–39 edited dictations a day (median ~19), and about half
contain a substitution. So expect around 5–15 offers a day at first. The
number should fall as accepted pairs enter the dictionary and refused ones
drop out.

## 6. When to revisit

- After a few days: count `offered` vs `added by the user` in the log. If
  most are let go, the filters are too loose (look at which kinds); if
  almost all are added, consider adding without asking for non-words.
- The user finds it intrusive: lengthen the settled delay, or offer only
  pairs seen twice.
- Vocabulary boosting works for Parakeet Ultra: an accepted real-word pair
  (vert → verre) could become a bias instead of a rewrite.
- The panel can't be seen by the agent (glass, Screen Recording): the
  user's eye judges it, as fork-017.
