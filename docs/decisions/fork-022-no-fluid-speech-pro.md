# Fork ADR-022 :: Fluid Speech Pro, measured, not taken

Last updated: `2026.11.24` · Status: **rejected**

> The user heard that FluidVoice's models are very good in noise and small,
> and asked whether Parrot should use them. FluidVoice published two in
> November 2026, both post-trainings of Parakeet Ultra, the model Parrot
> already runs (fork-004). Mini is English only. Pro, multilingual, was run
> against Ultra on the user's own dictations: it made about twice the errors,
> noisy or clean. Parrot keeps Parakeet Ultra.

## 1. The models (as published, 2026-11-24)

| | Fluid Speech Pro | Fluid Speech Mini |
|---|---|---|
| Base | Parakeet Ultra (HF metadata), plus one small block in the encoder | Parakeet Ultra, weights at ~3 bits |
| Core ML | 652 MB (Ultra: 603 MB), int8 encoder | 253 MB |
| Languages | 25, French included | English only: French "not trained or measured" |
| Licence | CC BY 4.0 | CC BY 4.0 |

- **The noise claims are English.** Pro: URGENT 2024, 9.83 % against
  Parakeet v3's 11.52 % (Ultra not listed). Mini: Google SVQ with another
  voice in the room, 10.9 % against Ultra's 14.3 %.
- **French, published**: FLEURS fr, Pro 4.65 % against v3 4.75 %, its
  smallest gain of 24 languages (−2 %, against −20 % on average). Moondream
  gives Ultra 4.32 % against v3 4.81 % on the same set. The two harnesses
  disagree on v3 (Greek: 21 % and 36 %), so this hinted, didn't decide.
- **Loading**: Pro's Core ML files have Ultra's names, inputs and outputs,
  except the joint network: `JointDecision` without `top_k_ids` /
  `top_k_logits`. FluidAudio 0.17.4 loads it as `.ultra` once the joint is
  named `JointDecisionv3`; without the top-K, the French filter (fork-004:
  English function words swapped for French ones when the language is
  fixed) does nothing. FluidVoice's own loader is a FluidAudio fork
  (`altic-dev/FluidAudio`, `.fluidParakeetPro`).

Sources: [FluidVoice's announcement](https://fluidvoice.com/fluid/blog/fluidspeech-pro),
[Pro, ONNX card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-onnx),
[Pro, Core ML](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml),
[Mini, Core ML](https://huggingface.co/FluidVoice-Labs/fluid-speech-mini-coreml),
[Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra).

## 2. Measured on the user's dictations (2026-11-24)

From the corpus (2,816 recordings with the text the user kept), split by
signal-to-noise ratio as in fork-020 (90th minus 10th percentile of 20 ms
frame levels), random with a fixed seed:

- **noisy**: 250 from the noisiest fifth (SNR 10.3–19.3 dB, 41 min);
- **clean**: 100 from the cleanest fifth (33.1 dB and up, 20 min);
- **edited**: 250 the user had corrected by hand (51 min).

`parrot-bench transcription <set> --runs 1`, Pro through
`--parakeet-dir` (added for this). The reference is what the user kept.
Everything local; the copies and Pro's files were deleted afterwards.

| | Ultra | Pro |
|---|---|---|
| noisy: WER | **4.7 %** | 9.0 % |
| noisy, language not fixed (`--spoken fr,en`): WER | **5.2 %** | 9.0 % |
| noisy: first word right | **98.0 %** | 92.4 % |
| clean: WER | **2.0 %** | 3.9 % |
| edited: WER | **12.8 %** | 15.8 % |
| transcription, median / p90 (noisy) | 55 / 160 ms | 52 / 151 ms |

- **Pro errs about twice as often, in noise as in quiet.** The missing
  French filter explains half a point: without it on either model (second
  row), Ultra is still at 5.2 %.
- **The reference leans towards Ultra**: where the user didn't correct, the
  kept text is Ultra's, wrong words included. For Pro to be truly better,
  its ~380 extra differences on the noisy set (4 % of the words) would have
  to be Ultra's unnoticed errors, twice Ultra's whole error rate on clean
  audio. On the edited set, where the user did read and fix, Pro is worse
  too. With FluidVoice's own French numbers, the direction is clear.
- **Speed**: the same, 5–15 % faster, inside the noise of a 50 ms stage.

## 3. Decision

Parrot keeps Parakeet Ultra. No setting, no second model (fork-016).
`--parakeet-dir` stays in `parrot-bench` to measure the next one in minutes:
a folder named `parakeet-ultra` holding the build's files under Ultra's
names.

## 4. When to revisit

- FluidVoice (or Moondream, or NVIDIA) publishes a French or noisy-French
  gain over Ultra, or a Pro build with the top-K joint: rerun §2.
- The user's noisy dictations get worse (fork-020's SNR fifths, the
  `headset connected` diagnostic): the noise is what this was about.
