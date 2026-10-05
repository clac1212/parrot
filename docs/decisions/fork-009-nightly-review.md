# Fork ADR-009 :: Learning at night ("dreaming")

Last updated: `2026.10.02` · Status: **built** — a self-correcting loop, nothing asked of the user

> Parrot gets better from use, not from rules written in advance, and the
> user does nothing. Once a day a job reviews the dictations — the audio, what
> was pasted, what the user kept — adds to the dictionary the mishearings it
> is sure of, checks whether what it added earlier did harm, and removes it if
> so. Real time stays fast and dumb; judgment happens when there is time.

## 1. The stance

Correcting in real time is the wrong place to be clever:

- At paste time Parrot can't tell a transcription error from a grammar fix or
  a rewrite; a user's edit means any of the three (fork-005).
- Anything in the path from release to text costs latency; the fork's first
  goal is speed.
- Text-only correctors measured on the user's data fix almost nothing that
  matters (grammar checkers: 0 of 6 real corrections; ~14 % of substantive
  errors are within reach of rules) and LLM rewriting breaks as much as it
  fixes (26 % of FluidVoice's LLM edits introduced errors; Apple's on-device
  model changed 9 of 13 dictations the user had left as they were).

At night the trade-offs flip: no latency budget, the audio is there, a heavy
model can re-listen, and recurrence separates a pattern from noise. So: keep
the live path to transcription plus deterministic rewrites (the dictionary,
a few fixed rules), and move learning to a nightly batch whose output is
plain, reviewable data — dictionary entries.

## 2. Proposed design

A nightly job, outside the app (Parrot only reads the dictionary it updates):

1. **Re-listen** — re-transcribe the day's corpus (fork-003) locally with a
   heavy model too slow to dictate with (Cohere Transcribe, see §3): a second
   opinion on every dictation, edited or not.
2. **Compare** — align Parakeet's output, the re-transcription and the
   user's final text (fork-005); extract word-level substitutions.
3. **Find patterns** — count substitutions across days; keep those that recur
   and sound alike (phonetic similarity), and aren't common French words.
   Deterministic code, no LLM.
4. **Judge** — a language model gets the short list of candidates with their
   evidence (three versions of each passage) and answers per candidate:
   dictionary entry, or not (rewrite, grammar, one-off). Claude (short
   excerpts leave the Mac, audio never does).
5. **Apply** — write accepted entries to `~/.config/parrot/dictionary`, with a
   backup and a changelog line per change, so any entry can be reverted.
   Uncertain ones go to the report as proposals.
6. **Report** — a short morning note: dictations edited by the user, recurring
   errors, entries added, the trend week over week.

Setup: one button in Settings that installs (or removes) the nightly task.

## 3. As built

- **`parrot dream prepare`** (`Dream/NightlyReview.swift`): re-transcribes
  each corpus WAV not yet seen with Cohere Transcribe (`CohereReference`:
  FluidAudio's Core ML port, 2.1 GB in `fluidaudio/cohere-transcribe/q8`,
  French forced, audio cut at silences into 4–9 s pieces because the Core ML
  decoder stops at 99 tokens and silently truncated anything past ~15 s, a
  lone "Merci." hallucination dropped; references kept in
  `dream/references/`, at most 200 a night), aligns pasted/final/reference word by word (`WordAlignment`: LCS,
  replaced runs of 1–3 words, plus casing into a canonical spelling like
  `PostHog`), tallies pairs over the whole corpus, keeps those corrected by
  the user at least once or re-heard differently at least twice, drops pairs
  the dictionary already maps or a judge already ruled on (asked again once
  seen twice as often), and writes up to 40 to `dream/candidates.json` with
  a French phonetic similarity (`FrenchPhonetics`), whether `wrong` is valid
  French (`NSSpellChecker`, French), and up to three short excerpts.
- **Judge**: `scripts/dream/judge_claude.sh` — `claude -p` (Sonnet), no
  tools, no MCP, no session kept, structured output against
  `judge_schema.json`; verdicts `dictionary | grammar | rewrite | one_off |
  unsure` with a probability. The prompt (`judge_prompt.md`) asks for
  conservatism: a wrong entry corrupts every future dictation.
- One re-listener, one judge: the user ruled out stacking models at night.
- **`parrot dream apply`** — the loop, with no review by the user:
  1. remembers the verdicts (`dream/verdicts.json`: pair, verdict,
     probability, count, an excerpt);
  2. **removes** learned entries that did harm: each run, `prepare` builds an
     *audit* for every entry the loop added (`dream/learned.json`) that fired
     in a dictation — known since corpus records keep Parakeet's text before
     the dictionary (`raw`) — where the user then changed the replaced word or
     Cohere heard something else; the judge answers keep or remove (≥ 0.7
     removes; with no judge, only "undone twice and never kept" does). A
     removed entry is marked `removed` and never comes back;
  3. **adds** every `dictionary` verdict with probability ≥ 0.85 **and** seen
     at least twice that the dictionary doesn't map yet — the two guards that
     replace the user's review;
  4. backs up the dictionary once a day (`dream/backups/`), logs each change
     (`dream/changelog.md`), and writes one report per run
     (`dream/reports/<day>_<HH-mm>.md`: what was learned and removed, the
     share of dictations the user corrected per day — the number the loop
     should bring down — the candidates and audits with their verdicts).
  It only ever touches entries it added, never the user's own.
- **Schedule — a daily catch-up, not a fixed hour** (since 2026-10-02):
  launchd (`com.clac1212.parrot.dream`, from the panel's Activer) only wakes
  `dream/bin/run.sh` every 30 minutes and at login; the script runs the
  review when the last successful one is ≥ 20 h old **and** the Mac is free:
  on AC power and idle (no keyboard or mouse) for 10 minutes — on battery
  too once nothing ran for 48 h. Otherwise it exits in a fraction of a
  second. Missed days are caught up naturally: prepare handles every
  dictation not yet re-listened to. `caffeinate -i` keeps the Mac awake for
  the run; a lock (`dream/.lock`, stale after 2 h) prevents two at once. The
  panel's Lancer leaves a `force` file that skips the checks.
- **Journal** `dream/runs.jsonl`: `started`, `done` (with candidates,
  proposed, applied; reason "no judge" when Claude didn't answer), `failed`
  (prepare, judge or apply), `skipped` (in use, on battery — written only
  when the reason changes). The panel shows the last run, its counts, and
  "prochaine : dès que le Mac sera libre". Log: `~/Library/Logs/parrot/dream.log`.
- **No setting, no switch** (2026-10-02): the launchd job is installed at
  launch whenever the corpus is on (the default) and removed when it's off;
  the panel's Apprentissage section only says what the loop did ("Parrot
  apprend de tes dictées · 4 mots appris", last run, +added −removed) and
  links the report. A first version listed proposals for the user to accept
  or refuse, with an `autoApply` setting and an on/off button: dropped as a
  "non-choice" that made the user do the loop's work (CLAUDE.md, Product
  rules). The cost of an error is bounded instead: a wrong entry lives until
  the next run's audit, under 24 h of use.
- The scripts are installed by `scripts/install-dream.sh` from
  `fork-install.sh`. Needs the corpus on.

### Why not 3:00 (2026-10-02)

The first scheduled night ran from 03:12 to 08:25: launchd started the
calendar job during one of macOS's 45-second maintenance wakes (lid closed,
on battery), the Mac went back to sleep, and the run advanced only in those
wakes until the user opened the lid. A shut-down Mac skips calendar jobs
entirely. Running at wake instead would compete with the first dictations for
the Neural Engine (Cohere and Parakeet both use it). A free Mac — plugged in,
untouched for 10 minutes — is when nobody waits on it.

### First run (2026-10-01, by hand)

- 95 dictations re-transcribed with `whisper-large-v3-turbo` (since replaced) in ~7 min,
  model download included (1.6 GB); 11 candidates; Claude: 2 `dictionary`
  (nosamment → notamment, Durama → diorama, both proposed), 7 `one_off`,
  1 `grammar`, 1 `rewrite` — all sensible on reading. ~$0.10 per night.
- Jev-Style, tested by a sub-agent on 49 synthetic cases: the 0.8B is worse
  than plain rules (68–80 %); the 2B works only as two yes/no questions inside
  rules (93 % / 84 %, but rules alone give 93 % / 74 %). Kept as shadow (2B,
  MLX 8-bit, 1.9 GB weights + 490 MB venv, 4.5 s a night) for one night:
  on the real candidates it agreed with Claude on **2 of 11** and called both
  dictionary entries `grammar`. Removed.

### Which model re-listens (2026-10-01)

Measured against the user's final text (lowercased, no punctuation) on the
corpus: 22 dictations the user corrected (47 wrong words), 52 left as they
were. "Flags" = a word of Parakeet's output the re-listener transcribes
differently.

| Re-listener | WER, corrected ones | Flags: recall / precision | False flags / 100 words |
|---|---|---|---|
| Parakeet Ultra (the transcript itself) | 8.6 % | — | — |
| Whisper large-v3-turbo | 18.9 % | 70 % / 33 % | 18.4 |
| Parakeet v3 (`.french`) | 14.9 % | 57 % / 30 % | 7.6 |
| **Cohere Transcribe, 9 s pieces** | 12.9 % | **77 % / 44 %** | 8.9 |
| Cohere, FluidAudio's default long call | 28.1 % | — | — (truncates 17 of 74 files) |

Whisper-turbo, first chosen because Parrot already had it, was the worst:
replaced by Cohere and deleted (1.6 GB). Cohere is no better transcript than
Parakeet — 56 % of its disagreements are its own errors — so it only flags;
recurrence and the judge decide. Requiring Cohere and Parakeet v3 to agree
would raise precision to 64 % but the user chose a single model at night.
Cohere runs ~6× real time plus ~2 min of Neural Engine compilation per run:
~4 min a night on this corpus. It never drifts out of French (it turned
Parakeet's Finnish-sounding drift "Voisi mennä tämän oon" back into French).

Side finding, not yet explained: Parakeet Ultra run directly on a corpus WAV
differs from what the app pasted on 15 of 22 corrected dictations (fixing 6
errors, adding others; 10.2 % vs 8.6 % WER) — the app's trim and padding
(`WhisperTuning.prepare`) and the dictionary are the suspects. Worth a bench.

## 4. Open questions

- Does the loop converge? The report's per-day share of corrected dictations
  should fall; learned entries that keep getting removed would say the
  thresholds are too loose.
- A local judge, to drop Claude (nothing leaves the Mac, no account, no
  cost, offline — the condition for "installs and works for 99 %"). Its only
  value is replacing Claude; it won't judge better. See §6.
- The job runs Claude Code headless with the user's login, from launchd; a
  failed judge leaves candidates to the next night.

## 6. Parked lead: a local decision model as the judge (2026-10-02)

Decision models score given answers instead of writing text, which is
exactly the judge's job (dictionary / grammar / rewrite / one-off; keep or
remove), with a probability.

- **Jev-Style** (community, 0.8B/2B): failed — 2 of 11 agreement with Claude
  on real candidates (§3).
- **Kev 1.0** (Jared Palmer, Apache-2.0, https://github.com/jaredpalmer/kev,
  Qwen3.5/3.8 bases 0.8B–27B, a pointer head with calibrated probabilities,
  Jev-compatible API, local server on MLX: `uv run --extra serve python -m
  kev.serve --run jaredpalmer/kev-4b`). On sources it never saw: Kev-4B 82 %
  accuracy, Kev-0.8B 65 %, Kev-27B 85 % (Jev 86 %). Kev-4B wants a 32 GB Mac;
  this one has 24 GB.
- **Not tested.** Claude has judged only 40 candidates, 6 of them
  `dictionary`: one disagreement would read as 83 % precision, so no test can
  show the ≥ 95 % needed to replace Claude. The user parked it: the models
  are first releases, and the loop will have more data in a few weeks.
- **How to test when revisiting:** have the local judge answer the cases
  Claude already judged (rebuild their evidence from the corpus), alone and
  combined with the deterministic signals (count, user edits, phonetic
  similarity, French-word check); pass if its `dictionary` verdicts agree
  with Claude's ≥ 95 % (precision) and find most of them (recall); or run it
  in shadow beside Claude for a few weeks.
- **Revisit when** Claude has judged a few dozen `dictionary` candidates, or a
  decision model that fits 24 GB scores clearly higher on new sources.

### Bonsai 2 27B, tested 2026-10-05 — now on trial

PrismML's Bonsai 2 27B (Qwen3.8-27B in ternary weights, Apache-2.0; MLX
2-bit pack, 8 GB on disk, `mlx-vlm` 0.7.2) is a generative model: it takes
Claude's exact prompt and schema, unlike a decision model. Tested on the 40
candidates Claude had judged (evidence rebuilt from the corpus) plus 10
adversarial cases:

| Setup | Dictionary additions (≥ 0.85, seen ≥ 2) matched | Additions Claude refused | Same verdict overall |
|---|---|---|---|
| Reasoning "medium", run 1 / run 2 | 3/3 · 3/3 | 0 · 0 | 68 % · 65 % |
| No reasoning, run 1 / run 2 | 0/3 · 1/3 | 0 · 1 ("over → hover") | 65 % · 65 % |

Adversarial cases 10/10 in both setups ("la paire → la PR" refused and
removed when learned; Vercelle, post hog, n huit n accepted; ses/ces, a/à
grammar). Most disagreements are between verdicts that change nothing
(one-off, rewrite, unsure). Reasoning is required: without it verdicts
change between runs. Cost: ~15 min for 40 candidates on a free Mac (12 tok/s
decode, 73 tok/s prefill), 17 GB peak of 24; 83 min with FluidVoice's own
model resident (swapping). Only 3 real additions: encouraging, not proof.

**Trial (the user chose it over switching now):** `run.sh` runs
`judge_bonsai.py` after Claude when `dream/bonsai/{venv,model}` exist;
`parrot dream apply --shadow` compares (`ShadowTrial`, totals in
`dream/shadow.json`) and the report gains "Essai : Bonsai face à Claude":
same verdicts, additions by both, Claude's that Bonsai misses, Bonsai's where
Claude agreed but below the threshold, and **Bonsai's that Claude judged
otherwise — the number that must stay at 0**. (Split on 2026-10-05: the first
trial run counted "seit → soit" — Claude dictionary 0.80, Bonsai 0.90 — as a
refusal, and the user found Bonsai's addition right.) Only Claude's
verdicts apply. Switch when that holds over a few dozen additions; then
Claude goes, nothing leaves the Mac. The same model also serves the user's
own chat: the PrismML kit in `~/Bonsai-demo` (`models/` links to Parrot's
copy, `.venv-vlm` is an APFS clone, Open WebUI in `.venv`, 2.2 GB).
- Shipping it to everyone would also mean running it from Swift (MLX Swift),
  not a Python server.

## 5. Later

- With a few hours of corrected audio, fine-tune Parakeet on the user's voice
  and vocabulary — the corpus being collected now makes it possible.
