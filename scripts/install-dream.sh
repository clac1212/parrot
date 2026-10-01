#!/usr/bin/env bash
# Installs the nightly review's scripts (fork-009) into
# ~/Library/Application Support/parrot/dream/bin, where the launchd job set up
# from Settings runs them (docs/decisions/fork-009-nightly-review.md).
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="$HOME/Library/Application Support/parrot/dream/bin"
mkdir -p "$DEST"
chmod 700 "$HOME/Library/Application Support/parrot/dream"
cp scripts/dream/run.sh scripts/dream/judge_claude.sh scripts/dream/judge_prompt.md scripts/dream/judge_schema.json "$DEST/"
chmod +x "$DEST/run.sh" "$DEST/judge_claude.sh"
echo "→ nightly review scripts installed in $DEST"
