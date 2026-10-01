# Fork ADR-004 :: Parakeet Ultra as the French engine

Last updated: `2026.10.01`

> The fork adds Parakeet Ultra (NVIDIA Parakeet TDT 0.6B v3 post-trained by
> Moondream) through FluidAudio, on the Neural Engine, as the `parakeet`
> engine upstream had planned, and the user runs it instead of
> `whisper-small`. Chosen on published numbers and one drift test; to be
> confirmed on the user's own dictations (fork-003, fork-005).

## 1. Decision

- **`ParakeetTranscriber`** (`Transcription/ParakeetTranscriber.swift`),
  FluidAudio **0.17.4 pinned `exact`**, model `parakeet-ultra` in the
  registry (603 MB, int8 encoder, Parakeet v3's 25 languages), weights in
  `~/Library/Application Support/parrot/fluidaudio/parakeet-ultra`.
- **Same audio as Whisper**: `WhisperTuning.standard.prepare` (silence trim,
  0.3 s padding each side), then padded with silence to at least 1 s, as
  FluidVoice does (FluidAudio refuses under 0.3 s).
- **Language passed when it is fixed** (Language setting, or a single spoken
  language): with `fr`, FluidAudio swaps English function words ("the",
  "and"…) for their best French candidate (FluidAudio #630/#847). With
  Automatic and several languages, nothing is passed and Parakeet chooses.
- **Warm-up**: load, then one pass on 1 s of silence, so the first dictation
  doesn't pay for the Neural Engine's first run.
- **Engine-neutral loading**: a `ModelTranscriber` protocol (`warmUp`,
  `unload`) and `Transcribers.make`/`isCached` replace the hard-coded
  WhisperKit transcriber in `Daemon`, `ModelSwitcher`, `Startup`,
  `ModelCommands` and the Settings window (one line each). A model change in
  Settings swaps engines live, as between Whisper models.
- `whisper-small` and the other Whisper models stay in the registry; upstream's
  recommended model is unchanged.

## 2. Rationale

| | whisper-small (before) | Parakeet Ultra |
|---|---|---|
| FLEURS-fr WER, same Mac (M5 Air, whispernotes) | 13.24 % | v3: 5.83 % |
| FLEURS-fr WER (Moondream) | – | 4.32 % (v3: 4.81 %) |
| Drift into English, 143 segments of a French meeting (fork-003) | 0 % of segments | 0 % |
| Same, median time per segment (1–60 s) | 495 ms | 63–65 ms |
| Cost grows with | words said (decoder, 8.4 ms/token, French 1.54 tokens/word) | audio length (RTFx ~125) |
| Release→text, 53 real dictations | median 650 ms, p90 1.5 s, max 6.5 s | to measure |

Drift test, share of segments with ≥ 2 English function words, same
detector as the 3,411 FluidVoice dictations: FluidVoice's own output
(Parakeet **v2**, English-only) 86 %; v3 without language 9.8 %; v3 with
`fr` 7.0 %; Ultra 0 % with or without `fr`; whisper-small 0 % (but 20 % fewer
words than Ultra). Far-field meeting with three voices, no reference text:
"0 %" means no English, not correct.

Options rejected for now:

| Option | Why not |
|---|---|
| Parakeet v3 | Same speed, drifts on 7–10 % of the meeting's segments; Ultra is a strict improvement (FLEURS 24 languages 11.67 vs 14.81 WER). |
| Stay on Whisper, larger model (large-v3-turbo) | ~2× fewer errors than small but 1.6–1.8× slower: latency still grows with words. |
| Cohere Transcribe (best open French WER, 4.02 avg) | ~2× real time in FluidAudio's Core ML port: seconds per dictation. |
| Nemotron 3.5 streaming (language-conditioned) | About twice Parakeet's French WER (FLEURS 9.9). |
| Apple SpeechTranscriber | FLEURS-fr 7.6, no custom vocabulary; worth a bench, not a switch. |
| FluidAudio custom vocabulary (CTC boosting) | Its CTC model is English; untested on French; known false substitutions (#967). |

## 3. Design Implications

- **No prompt**: the dictionary's example sentence (Whisper's prompt) is
  unused with Parakeet. Word replacements still apply after transcription.
- The `fr` hint degrades code-switching (English phrases said on purpose,
  FluidAudio #840: "this" → "dis"). Anglicisms are mostly nouns and verbs,
  which the list doesn't touch; the corpus will show if it matters.
- Licence: Parakeet Ultra weights are CC-BY-4.0 (attribution).
- The latency log's `tokens` is Parakeet's token count; `enc`/`dec` are
  FluidAudio's own timings; `fallbacks` is always 0.
- `parrot-bench transcription` is still Whisper-only.

## 4. When to Revisit

- Release→text after ~20 dictations (latency log) — fill in the table above.
- The corpus shows drift, homophone errors, or missing punctuation that
  Whisper didn't have → bench both on it (`parrot-bench` needs the Parakeet
  engine first) and decide again.
- Upstream adds its own Parakeet engine → take theirs, drop this one.
