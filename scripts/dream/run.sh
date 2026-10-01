#!/bin/bash
# The nightly review (fork-009), run by launchd at 3:00 (or at wake).
# prepare (Cohere re-listens) → judge (Claude) → apply.
set -uo pipefail
DREAM="$HOME/Library/Application Support/parrot/dream"
BIN="$DREAM/bin"
PARROT=/Applications/Parrot.app/Contents/MacOS/parrot
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd "$DREAM" || exit 1
echo "== $(date '+%F %T') nightly review"

"$PARROT" dream prepare || { echo "prepare failed"; exit 1; }

rm -f decisions-claude.json
if grep -q '"id"' candidates.json 2>/dev/null; then
    "$BIN/judge_claude.sh" candidates.json decisions-claude.json || echo "Claude judge failed"
fi

"$PARROT" dream apply --judge decisions-claude.json
echo "== $(date '+%F %T') done"
