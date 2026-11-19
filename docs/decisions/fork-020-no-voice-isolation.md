# Fork ADR-020 :: No voice isolation before transcription

Last updated: `2026.11.19` · Status: **rejected after measurement**

> The user finds dictation worse with noise around and asked to try voice
> isolation. Measured on the corpus: the noisy recordings do have about 4×
> the errors, but Apple's voice isolation effect (`AUSoundIsolation`) makes Parakeet
> Ultra 3 to 5× worse, noisy or clean, in every setting tried. Not built. The
> other lever, the AirPods' closer microphone, was measured too (§5): no
> better on what the user says. fork-007 stays.

## 1. Is noise the problem? (2026-11-19)

2,378 corpus dictations, each given a signal-to-noise ratio: the 90th minus
the 10th percentile of its 20 ms frames' level. Words the user fixed by
hand, per 100 pasted, by fifth of SNR:

| SNR (dB) | 10.7–19.8 | 19.8–22.7 | 22.7–26.1 | 26.1–32.0 | 32.0–54.4 |
|---|---|---|---|---|---|
| words fixed / 100 | 0.71 | 0.36 | 0.40 | 0.33 | 0.25 |
| dictations edited | 23.5 % | ~18 % | ~18 % | ~18 % | ~18 % |

The noisiest fifth has about twice the hand fixes. Against the user's final
text (the bench below), its word error rate is 3.6 %, the cleanest fifth's
0.8 %.

## 2. Voice isolation, measured

`AUSoundIsolation` (`aufx vois appl`, macOS 13+) run offline, through
AVAudioEngine's manual rendering, over 250 random recordings from the noisiest
fifth and 100 from the cleanest. Each was then transcribed with
`parrot-bench transcription` and Parakeet Ultra. The reference is what the
user kept: the edited text when they edited it, otherwise the paste. All
local; the copies were deleted afterwards.

| | noisy: WER | noisy: 1st word | clean: WER | clean: 1st word |
|---|---|---|---|---|
| **as recorded** | **3.6 %** | **98 %** | **0.8 %** | **98 %** |
| isolated, standard model | 16.3 % | 67 % | 3.6 % | 92 % |
| + 1 s of pre-roll (warm start) | 14.9 % | 77 % | 4.0 % | 94 % |
| high-quality model (macOS 15) | 19.1 % | 73 % | 4.0 % | 89 % |
| standard model, 50 % wet | 10.2 % | 84 % | 3.6 % | 93 % |

"1st word" is the share of dictations whose first word came out right.

- The noise does go: the floor of one recording fell from −37 to −84 dBFS.
  But speech goes with it. The effect mutes the first ~250 ms (a cold start;
  pre-roll only half helps) and quiet words in the middle (a word at
  −41 dB came out at −89).
- Even half-mixed with the original it doubles the noisy error rate.
- Cost: 11 ms per second of audio, offline. The cost is not the problem.

A plausible reason, not checked: Parakeet was trained on noisy speech and
copes with noise, not with the gaps and artefacts that suppression leaves.

## 3. Decision

Nothing changes in the pipeline: the audio Parakeet hears is the
microphone's.

## 4. Options considered

| Option | Why not |
|---|---|
| `AUSoundIsolation`, any of the four settings above | Measured above: worse everywhere. |
| macOS voice processing (`setVoiceProcessingEnabled`, the FaceTime path: echo cancellation, noise suppression, AGC) | Same family of processing, so likely the same harm. It also ducks the Mac's other audio and changes the capture path Parrot opens at each press (#52). Not measured: it only runs live, not over files. |
| A third-party denoiser (RNNoise, DeepFilterNet) | Same family; a model to ship for a loss that §2 suggests. Not measured. |
| Mix both microphones throughout (the user's idea) | The far microphone adds the room's noise and reverberation back, and Bluetooth arrives 100–200 ms late, so the mix echoes. Rejected in discussion, 2026-11-19. |
| The AirPods' microphone when they are worn (fork-007 revisit) | Measured in §5: about the same errors, and a stitch to hide their silent start. |

## 5. The AirPods' microphone instead (2026-11-19)

fork-007 records the Mac's microphone when AirPods are connected, because
the AirPods lose the start. The user dictates farther from the Mac with
AirPods on, which is where the Mac's microphone hears the most noise. So a
scratch recorder captured both microphones at once (AudioQueue on each
device) while the user, AirPods on and at their usual distance, read a
fixed 69-word text: once in quiet, twice with some noise (the first noisy
take is scored on the part read only; the user talked before reading).

| take | SNR Mac / AirPods | errors, Mac / AirPods |
|---|---|---|
| quiet | 18 / 46 dB | 6 / 8 of 69 words |
| noise, take 1 (part read) | 19 / 25 dB | 14 / 11 of 64 |
| noise, take 2 | 19 / 32 dB | 2 / 3 of 69 on the text read (« 9h30 » counted right); the Mac's also wrote a sentence from a voice in the room, after the user stopped |

- The AirPods hear far less noise, but Parakeet makes about the same
  mistakes on both: it copes with the Mac's 18 dB.
- Their one clear advantage: they don't pick up another person speaking
  nearby. In a dictation that matters only if someone talks while the key
  is held.
- Their silent start was 0.58–0.78 s on macOS 27 (0.55 s in fork-007), so
  using them means stitching the Mac's first second to the AirPods' rest.

Not built: one recorder per microphone and a stitch, for no measured gain
on what the user said. fork-007 stays.

## 6. When to revisit

- Apple ships a voice isolation meant for speech recognition, or Parakeet a
  noise-robust variant: re-run §2. The bench is repeatable: select by SNR,
  render, `parrot-bench transcription <folder> --runs 1`.
- Other people's voices end up in dictations (the corpus would show words
  the user deletes at the end): the AirPods' microphone is the answer, §5.
- The "headset connected" diagnostic (fork-007 §5) shows AirPods
  dictations doing much worse than the rest.
