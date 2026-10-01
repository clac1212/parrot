#!/usr/bin/env python3
"""Local judge for the nightly job: classify candidate substitutions with a Jev-Style model.

Usage:
    JEV_VENV=~/Library/Application\ Support/parrot/dream/jev/venv  # the nightly job's copy (fork-009)
    $JEV_VENV/bin/python scripts/dream/judge_jev.py candidates.json decisions.json

Expects a venv with `pip install "jev-style[mlx]==0.3.0"` (Apple silicon, MLX backend; the 2B
runtime needs mlx-lm 0.31.3 exactly, which that extra pins). Runs fully on-device: the model is
downloaded once from the Hugging Face Hub into HF_HOME (default ~/.cache/huggingface) and reused
from the cache afterwards; set HF_HUB_OFFLINE=1 to forbid any network access. Needs Metal, so it
cannot run inside a sandbox that hides the GPU.

Environment:
    JEV_MODEL      Hub repo of the build (default chaoliangUNSW/Jev-Style-2B-Decision-v3-MLX;
                   chaoliangUNSW/Jev-Style-0.8B-Decision-v3-MLX for the 0.8B, measured much weaker)
    JEV_MODEL_DIR  optional local folder holding that build (skips the Hub entirely)
    JEV_PRECISION  MLX weights, "8bit" (default, 2.0 GB for the 2B) or "bf16" (3.8 GB)

Input  {"generated": ..., "candidates": [{"id", "wrong", "right", "count", "user_edits",
        "reference_hits", "phonetic", "wrong_is_french_word", "examples": [{"pasted", "final", "reference"}]}]}
Output {"judge": "jev-style-2b", "decisions": [{"id", "verdict", "probability", "reason"}]}

How a verdict is reached. A single five-way question was measured and rejected: the model never
picks "rewrite" and confuses one_off with dictionary. The model instead answers two narrow
questions it measurably can answer, and the structured fields decide the rest:

  1. user_edits == 0 and the user's final text kept `wrong`  -> unsure  (rule; the user saw it and
     left it, only the reference model disagrees)
  2. phonetic < 0.3 -> rewrite (rule: nothing to mishear)
  3. model: misheard vs reworded; reworded >= 0.5 and phonetic < 0.7 -> rewrite
  4. model: vocabulary (name, brand, technical term) vs grammar (homophone spelling), with
     vocabulary forced when the correction adds a capital letter -> grammar when vocabulary < 0.5
  5. vocabulary: count < 2 -> one_off; user_edits == 0 -> unsure; `wrong` is a French word and
     count < 4 -> one_off; otherwise -> dictionary

`probability` is the model's probability on the question that settled the verdict: P(reworded)
for rewrite, P(vocabulary) for dictionary / one_off / the unconfirmed unsure, 1 - P(vocabulary)
for grammar (0.5 when only the capital-letter rule made it vocabulary). It is 1.0 for rules 1
and 2, whose `reason` starts with "rule:". Rules alone never produce a dictionary verdict.
Measured on 49 synthetic cases (2B, 8-bit): every answer at P(vocabulary) >= 0.8 or
P(reworded) >= 0.7 was right; below that, 28 % (vocabulary) to 50 % (reworded) were wrong.
Treat a dictionary verdict under 0.8 as a suggestion to review, not an entry to apply.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

DEFAULT_MODEL = "chaoliangUNSW/Jev-Style-2B-Decision-v3-MLX"

REWORD_Q = {"type": "choice", "instructions": "Why does the corrected sentence differ from the transcript?",
            "criteria": {"misheard": "the speech recognizer wrote a word that sounds like what the speaker said",
                         "reworded": "the speaker changed their wording or meaning afterwards"}}
VOCAB_Q = {"type": "choice", "instructions": "What did the speech recognizer get wrong?",
           "criteria": {"vocabulary": "a name, brand or technical term it did not know",
                        "grammar": "French spelling or grammar between words that sound the same"}}

SOUND_ALIKE = 0.7      # phonetic score at or above which a change is a mishearing, never a rewrite
SOUNDS_DIFFERENT = 0.3  # below it, nothing the recognizer could have misheard: a rewrite
COMMON_WORD_MIN_COUNT = 4


def load_model():
    from jev_style import JevStyle
    repo = os.environ.get("JEV_MODEL", DEFAULT_MODEL)
    kw = {"precision": os.environ.get("JEV_PRECISION", "8bit")}
    if os.environ.get("JEV_MODEL_DIR"):
        kw["model_dir"] = os.environ["JEV_MODEL_DIR"]
    return JevStyle.from_pretrained(repo, **kw), judge_name(repo)


def judge_name(repo: str) -> str:
    tail = repo.rsplit("/", 1)[-1].lower()
    size = "2b" if "-2b-" in tail else "0.8b" if "-0.8b-" in tail else tail
    return f"jev-style-{size}"


def pairs(c: dict) -> str:
    """Each example as transcript / corrected text (the user's final text, else the reference)."""
    blocks = []
    for e in c["examples"]:
        after = e["final"] if e.get("final") is not None else e.get("reference")
        blocks.append(f"Transcript: {e['pasted']}\nCorrected: {after}")
    return "\n\n".join(blocks)


def adds_capital(c: dict) -> bool:
    """The correction introduces a capital letter: `right` is (or contains) a proper noun or acronym."""
    return sum(ch.isupper() for ch in c["right"]) > sum(ch.isupper() for ch in c["wrong"])


def user_kept_original(c: dict) -> bool:
    return c["user_edits"] == 0 and any(e.get("final") is not None and e["final"] == e["pasted"]
                                        for e in c["examples"])


def decide(js, c: dict) -> dict:
    def out(verdict, p, reason):
        return {"id": c["id"], "verdict": verdict, "probability": round(float(p), 3), "reason": reason}

    if user_kept_original(c):
        return out("unsure", 1.0, "rule: the user kept the original text; only the reference disagrees")

    if c["phonetic"] < SOUNDS_DIFFERENT:
        return out("rewrite", 1.0, "rule: sounds nothing alike, the user reworded")
    reworded = js.decide(pairs(c), {"q": REWORD_Q})["answers"]["q"]["probabilities"]["reworded"]
    if reworded >= 0.5 and c["phonetic"] < SOUND_ALIKE:
        return out("rewrite", reworded, "the user reworded; not a mishearing")

    state = f'Speech recognizer wrote: "{c["wrong"]}"\nCorrect: "{c["right"]}"\n\n{pairs(c)}'
    vocab = js.decide(state, {"q": VOCAB_Q})["answers"]["q"]["probabilities"]["vocabulary"]
    if adds_capital(c):     # French capitalises names: the model alone calls Lee, PIN, Lacour "grammar"
        vocab = max(vocab, 0.5)
    if vocab < 0.5:
        return out("grammar", 1.0 - vocab, "homophone or spelling fix")
    p = vocab
    if c["count"] < 2:
        return out("one_off", p, "seen once")
    if c["user_edits"] == 0:
        return out("unsure", p, "only the reference model proposes it; never confirmed by the user")
    if c["wrong_is_french_word"] and c["count"] < COMMON_WORD_MIN_COUNT:
        return out("one_off", p, f"'{c['wrong']}' is a common word; too few occurrences to replace it everywhere")
    return out("dictionary", p, "")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    candidates = json.loads(Path(argv[1]).read_text(encoding="utf-8"))["candidates"]
    js, name = load_model()
    decisions = [decide(js, c) for c in candidates]
    Path(argv[2]).write_text(json.dumps({"judge": name, "decisions": decisions}, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
