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
   heavy model too slow to dictate with (Whisper large-v3-turbo): a silver
   reference for every dictation, edited or not.
2. **Compare** — align Parakeet's output, the re-transcription and the
   user's final text (fork-005); extract word-level substitutions.
3. **Find patterns** — count substitutions across days; keep those that recur
   and sound alike (phonetic similarity), and aren't common French words.
   Deterministic code, no LLM.
4. **Judge** — a language model gets the short list of candidates with their
   evidence (three versions of each passage) and answers per candidate:
   dictionary entry, or not (rewrite, grammar, one-off). Pluggable: Claude
   first (short excerpts leave the Mac, audio never does), a local model
   (~12B, runs on the M4 Pro) once its decisions agree with Claude's on the
   same candidates.
5. **Apply** — write accepted entries to `~/.config/parrot/dictionary`, with a
   backup and a changelog line per change, so any entry can be reverted.
   Uncertain ones go to the report as proposals.
6. **Report** — a short morning note: dictations edited by the user, recurring
   errors, entries added, the trend week over week.

Setup: one button in Settings that installs (or removes) the nightly task.

## 3. As built

- **`parrot dream prepare`** (`Dream/NightlyReview.swift`): re-transcribes
  each corpus WAV not yet seen with `whisper-large-v3-turbo` (WhisperKit,
  French forced; references kept in `dream/references/`, at most 200 a
  night), aligns pasted/final/reference word by word (`WordAlignment`: LCS,
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
- **Shadow judge**: Jev-Style (local, MLX) via `judge_jev.py` when its venv
  exists in `dream/jev/venv`; its verdicts are compared, never applied; the
  report tracks agreement night after night.
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

- 95 dictations re-transcribed with `whisper-large-v3-turbo` in ~7 min,
  model download included (1.6 GB); 11 candidates; Claude: 2 `dictionary`
  (nosamment → notamment, Durama → diorama, both proposed), 7 `one_off`,
  1 `grammar`, 1 `rewrite` — all sensible on reading. ~$0.10 per night.
- Jev-Style, tested by a sub-agent on 49 synthetic cases: the 0.8B is worse
  than plain rules (68–80 %); the 2B works only as two yes/no questions inside
  rules (93 % / 84 %, but rules alone give 93 % / 74 %). Kept as shadow (2B,
  MLX 8-bit, 1.9 GB weights + 490 MB venv in `dream/jev/`, 4.5 s a night).
  On the real candidates it agreed with Claude on **2 of 11** and called both
  dictionary entries `grammar`: not a replacement for now.

## 4. Open questions

- After the first week of proposals: are Claude's `dictionary` verdicts
  right? If so, turn on `autoApply`.
- Does Jev-Style agree with Claude often enough (≥ 95 %) to take over and
  keep everything on the Mac?
- The job runs Claude Code headless with the user's login, from launchd; a
  failed judge leaves candidates to the next night.

## 5. Later

- With a few hours of corrected audio, fine-tune Parakeet on the user's voice
  and vocabulary — the corpus being collected now makes it possible.
