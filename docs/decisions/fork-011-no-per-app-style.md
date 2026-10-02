# Fork ADR-011 :: No per-app style — not now

Last updated: `2026.10.02` · Status: **rejected after research**

> The user wanted dictation formatted for the app it lands in — a Slack
> message in Slack, an email in Mail. Measured: today no local model restyles
> French reliably within the fork's latency, cloud means sending dictations
> out, and rules alone add little. Not built; revisit when local models are
> fast enough.

## 1. What was measured (2026-10-02)

**The market.** Wispr Flow's "Styles" only change casing, punctuation and
spacing ("Flow doesn't change your grammar, word choice, or phrasing"), in
English only, and went back from automatic to user-chosen per app category.
FluidVoice's automatic per-category routing is commented out in its code.
Superwhisper, VoiceInk, MacWhisper, Spokenly ask the user for a prompt per
app. The top complaint of LLM restyling, documented by the vendors: the
model answers the message instead of transcribing it.

**Local models on the M4 Pro** (20 French dictations × neutral, Slack, email,
Messenger; prefix KV cache warm; added latency for ~40 / ~80 words; outright
failures out of 80):

| Model | Added latency | Failures | Note |
|---|---|---|---|
| Qwen3.5-0.8B 4-bit | +0.18 / +0.40 s | 18 | answers the dictation, invents |
| Qwen3.5-2B 4-bit | +0.31 / +0.72 s | 10 | corrupts numbers (70 K → 60 K, 80 % → 48 %) |
| Gemma 4 E2B | +0.44 / +1.03 s | 1 | faithful, barely restyles |
| Apple Foundation Models | +0.96 / +1.81 s | 5 | inverted a meaning |
| Qwen3.5-4B 4-bit | +0.72 / +1.64 s | 2 | best style, still invents at times |

Parrot pastes 70–150 ms after release; the only convincing model multiplies
that by 5–10, growing with what is said. Speculative decoding doesn't run on
Qwen3.5 in mlx-lm yet. **Cloud**: Groq/Cerebras ~0.3–0.5 s from France,
still 3–5× today's latency, and dictations leave the Mac.

## 2. Options rejected

| Option | Why not |
|---|---|
| Deterministic rules per app category (no final period in chat, greeting on its own line…) | Can't see context — four dictations in a row into one email — and add little; the user found it weak. |
| Local model restyle, pasted raw then replaced in place ~1 s later (email only, fact guard) | Proposed; the user dropped the feature rather than ship a half-solution. |
| Cloud restyle | Latency still several times today's, and the text leaves the Mac. |
| Typing the model's output progressively (first token ~0.12 s) | A typed newline sends a Slack or iMessage message half-written; breaks the clipboard (fork-006) and correction capture (fork-005). |

## 3. When to Revisit

- A local model of Qwen3.5-4B's quality reaches ≥ 250 tok/s on Apple Silicon
  (speculative decoding or multi-token prediction in MLX for Qwen3.5, or a
  pure-attention 4B with a small draft model).
- Decision models (Jev, Kev — score given answers, no text generated) don't
  restyle, but could decide small things fast; see fork-009 for the judge.

Benchmark scripts and results (local only): `/tmp/claude-501/style/`, not kept.
