# Fork ADR-003 :: A corpus of the user's own dictations

Last updated: `2026.10.01`

> With `"corpus": {"enabled": true}` in `settings.json`, Parrot keeps every
> dictation's audio as a WAV in `~/Library/Application Support/parrot/corpus`.
> It builds the benchmark on which the fork chooses its French engine: public
> benchmarks don't measure spontaneous French dictation, and the failure
> being fixed (French drifting into English) only shows on real speech.

## 1. Decision

- **Opt-in, off by default, no switch in the Settings window.** It is a
  measurement tool, set by hand while the corpus is built. It is read at each
  release, so it applies without a restart.
- **Audio only, as captured**: 16 kHz mono 16-bit WAV, before the silence
  trim, which is what `parrot-bench transcription` replays through the same
  preparation as the app. One file per dictation, named by local date and time
  (`2026-10-01_10-12-03.wav`), owner-only (0600 in a 0700 directory).
- **Audio here; text since fork-005.** This ADR first kept upstream's rule
  (ADR-004, no transcript text on disk). fork-005 drops it for the corpus:
  what was pasted and how the user corrected it go beside each WAV as
  `.json`. Reference text for `parrot-bench` is a `.txt` beside the WAV.
- **Written off the main actor**, so keeping a recording doesn't delay the
  transcription.
- Code: `Sources/ParrotCore/Corpus/RecordingCorpus.swift` (the setting, the
  path as a `Paths` extension, the writer). Upstream edits are one line each
  in `Settings.swift` (field and decode), `DictationController.release`
  (the call, next to `--dump-wav`), and `Daemon.swift` (the setting).

## 2. Rationale

The data at hand when this was decided (2026-10-01):

- **FluidVoice's history** (3,411 dictations, 162,539 words, 2026-07-03 →
  09-30, Parakeet TDT v3 raw output): 5.0 % of dictations hold at least two
  English function words ("the", "and", "it's"…), 3.6 % at least five. These
  are whole clauses rewritten into English, which change the meaning, not
  anglicisms. The English sits early in the dictation: 715 hits in the first
  third, 656 in the second, 396 in the last; 78 of the 170 affected dictations
  have English in their first five words. FluidVoice keeps text only, no
  audio, so it can't be replayed through another engine.
- **One FluidVoice meeting** (47 min, in person) kept its audio: FluidVoice
  labeled it English, 127 of 207 segments drift. It is used as a drift stress
  test, but it is far-field, several voices: not dictation.
- **Public benchmarks** (FLEURS, MLS, Common Voice) are read speech;
  conversational French scores 4–5× worse (Qwen3-ASR: FLEURS-fr 4.75 vs
  MLC-SLM-fr 20.75), and the drift measured on Parakeet goes from 0 % on
  scripted speech to 31 % on a spontaneous interview (Thoth, 2026-05-19).

Options rejected:

| Option | Why not |
|---|---|
| Upstream's `--dump-wav` | One file, overwritten at each dictation, and a CLI flag: the app started at login never gets it. |
| A `Transcriber` decorator (no edit to the controller) | `ModelSwitcher` replaces the transcriber on a model change, which would silently drop the decorator. |
| Saving the transcript beside the audio | Rejected at first (upstream's rule); adopted in fork-005, with the user's corrections. |
| Re-dictating FluidVoice's drifted sentences | Read speech, the case where models don't drift. |
| A switch in the Settings window | A measurement tool for the fork, not a feature: few settings, good defaults. |

## 3. Design Implications

- The folder grows by about 32 KB per second of dictation (a 30 s dictation
  is ~1 MB) and is never pruned. Delete it, or set `enabled` back to false,
  when the corpus is done.
- It holds the user's voice: whatever was dictated, including private text,
  can be recovered from it. It stays local, outside the git repository, in
  the same owner-only location as the models.
- Two dictations within the same second share a name; the second overwrites
  the first.
- The log says `corpus: kept <file name>`, never the content.

## 4. When to Revisit

- The engine choice is made and measured → turn it off and delete the corpus,
  or keep it as a regression set for the next engine change.
- `parrot-bench` needs metadata per recording (the model and timings the app
  had) → add a sidecar with numbers only, never text.
