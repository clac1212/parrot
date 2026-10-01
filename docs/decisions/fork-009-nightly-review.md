# Fork ADR-009 :: Learning at night ("dreaming")

Last updated: `2026.10.01` · Status: **built**, first week in proposals-only mode

> Parrot gets better from use, not from rules written in advance. Each night a
> job reviews the day's dictations — the audio, what was pasted, what the user
> kept — finds the errors that recur, and updates the dictionary. Real time
> stays fast and dumb; judgment happens when there is time for it.

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
- **`parrot dream apply`**: remembers verdicts (`dream/verdicts.json`); a
  `dictionary` verdict at ≥ 0.8 is proposed in the report (copy-ready lines),
  or with `"dream": {"autoApply": true}` written to the dictionary — a backup
  of the file per night in `dream/backups/` and a line in
  `dream/changelog.md` per change. Writes `dream/reports/<day>.md` (French,
  numbers and lists, no model writes it).
- **Schedule**: Settings → Learn Overnight → Turn On writes a launchd agent
  (`com.clac1212.parrot.dream`, 3:00, runs at wake if missed) that runs
  `dream/bin/run.sh`; Run Now and Open Report sit beside it. The scripts are
  installed by `scripts/install-dream.sh` from `fork-install.sh`. Needs the
  corpus on. Log: `~/Library/Logs/parrot/dream.log`.

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

- After the first week of proposals: are Claude's `dictionary` verdicts
  right? If so, turn on `autoApply`.
- A local judge to keep everything on the Mac: Jev-Style failed (§3);
  revisit with a stronger local model.
- The job runs Claude Code headless with the user's login, from launchd; a
  failed judge leaves candidates to the next night.

## 5. Later

- With a few hours of corrected audio, fine-tune Parakeet on the user's voice
  and vocabulary — the corpus being collected now makes it possible.
