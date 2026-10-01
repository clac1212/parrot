#!/bin/bash
# The nightly review (fork-009), run by launchd at 3:00 (or at wake).
# prepare → judge (Claude; Jev-Style in shadow when installed) → apply.
set -uo pipefail
DREAM="$HOME/Library/Application Support/parrot/dream"
BIN="$DREAM/bin"
PARROT=/Applications/Parrot.app/Contents/MacOS/parrot
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd "$DREAM" || exit 1
echo "== $(date '+%F %T') nightly review"

"$PARROT" dream prepare || { echo "prepare failed"; exit 1; }

rm -f decisions-claude.json decisions-jev.json
if grep -q '"id"' candidates.json 2>/dev/null; then
    "$BIN/judge_claude.sh" candidates.json decisions-claude.json || echo "Claude judge failed"
    if [ -x "$DREAM/jev/venv/bin/python" ] && [ -f "$BIN/judge_jev.py" ]; then
        HF_HOME="$DREAM/jev/hf" HF_HUB_OFFLINE=1 \
            "$DREAM/jev/venv/bin/python" "$BIN/judge_jev.py" candidates.json decisions-jev.json || echo "Jev-Style judge failed"
    fi
fi

"$PARROT" dream apply --judge decisions-claude.json --shadow decisions-jev.json
echo "== $(date '+%F %T') done"
