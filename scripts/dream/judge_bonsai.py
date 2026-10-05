"""Bonsai 2 27B as a shadow judge of the daily review (fork-009 §6).

    python judge_bonsai.py candidates.json decisions-bonsai.json

Same instructions and schema as Claude (judge_prompt.md, judge_schema.json),
local only (MLX, offline). Reasoning effort "medium" and output constrained
to the schema: the setup that matched Claude on every dictionary addition in
the 2026-10-05 test; without reasoning, verdicts changed from run to run.
The model and its venv live in ~/Library/Application Support/parrot/dream/bonsai.
"""
import json, os, sys, time
from pathlib import Path

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import warnings
warnings.filterwarnings("ignore")

HERE = Path(__file__).resolve().parent
MODEL = Path.home() / "Library/Application Support/parrot/dream/bonsai/model"
PROMPT = (HERE / "judge_prompt.md").read_text()
SCHEMA = json.loads((HERE / "judge_schema.json").read_text())


def main(src, dst):
    payload = json.loads(Path(src).read_text())
    n = len(payload.get("candidates", [])) + len(payload.get("audits") or [])
    if n == 0:
        Path(dst).write_text(json.dumps({"judge": "bonsai", "decisions": [], "audits": []}))
        return

    import mlx.core as mx
    mx.set_default_device(mx.gpu)
    from mlx_vlm import generate, load
    from mlx_vlm.structured import build_json_schema_logits_processor, ThinkingAwareLogitsProcessor

    t0 = time.time()
    model, processor = load(str(MODEL))
    tok = processor.tokenizer if hasattr(processor, "tokenizer") else processor
    user = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    messages = [{"role": "system", "content": PROMPT}, {"role": "user", "content": user}]
    prompt = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True,
                                     enable_thinking=True, reasoning_effort="medium")
    constrain = ThinkingAwareLogitsProcessor(processor=build_json_schema_logits_processor(tok, SCHEMA),
                                             tokenizer=tok, enable_thinking=True)
    out = generate(model, processor, prompt, None, max_tokens=120 * n + 12400,
                   logits_processors=[constrain], temperature=1.0, top_p=0.95, top_k=20,
                   seed=0, verbose=False)
    text = out if isinstance(out, str) else out.text
    if "</think>" in text:
        text = text.rsplit("</think>", 1)[1]
    start = text.find("{")
    if start < 0:
        sys.exit("bonsai: no JSON in the answer")
    result, _ = json.JSONDecoder().raw_decode(text[start:])
    result["judge"] = "bonsai"
    Path(dst).write_text(json.dumps(result, ensure_ascii=False))
    print(f"bonsai: {n} items in {time.time() - t0:.0f} s, peak {mx.get_peak_memory() / 1e9:.1f} GB",
          file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
