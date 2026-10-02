#!/bin/bash
# The nightly review (fork-009), checked by launchd every 30 minutes.
# Runs at most once per 20 h, when the Mac is free: on AC power and idle for
# 10 minutes — or on battery too once nothing ran for 48 h. "Run Now" in the
# panel leaves a `force` file that skips the checks.
# prepare (Cohere re-listens) → judge (Claude) → apply. Journal: runs.jsonl.
set -uo pipefail
DREAM="$HOME/Library/Application Support/parrot/dream"
BIN="$DREAM/bin"
PARROT=/Applications/Parrot.app/Contents/MacOS/parrot
JOURNAL="$DREAM/runs.jsonl"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$DREAM" || exit 1

# Overridable for testing.
DUE_HOURS=${DREAM_DUE_HOURS:-20}
OVERDUE_HOURS=${DREAM_OVERDUE_HOURS:-48}
IDLE_SECONDS=${DREAM_IDLE_SECONDS:-600}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
journal() { printf '{"at":"%s","result":"%s","reason":"%s"}\n' "$(now)" "$1" "$2" >> "$JOURNAL"; }
# Logs a skip only when its reason changed, so a blocked evening doesn't add 20 lines.
skip() {
    last=$(tail -1 "$JOURNAL" 2>/dev/null | sed -n 's/.*"reason":"\([^"]*\)".*/\1/p')
    [ "$last" = "$1" ] || journal skipped "$1"
    exit 0
}

hours_since_last_run() {
    last=$(sed -n 's/.*"lastRun" *: *"\([^"]*\)".*/\1/p' state.json 2>/dev/null)
    [ -z "$last" ] && { echo 9999; return; }
    then=$(date -j -u -f %Y-%m-%dT%H:%M:%SZ "$last" +%s 2>/dev/null) || { echo 9999; return; }
    echo $(( ($(date +%s) - then) / 3600 ))
}

if [ -f force ]; then
    rm -f force
else
    hours=$(hours_since_last_run)
    [ "$hours" -lt "$DUE_HOURS" ] && exit 0
    idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
    [ "${idle:-0}" -lt "$IDLE_SECONDS" ] && skip "in use"
    if ! pmset -g batt | head -1 | grep -q "AC Power" && [ "$hours" -lt "$OVERDUE_HOURS" ]; then
        skip "on battery"
    fi
fi

# One run at a time; a lock older than 2 h is a crashed run.
if ! mkdir .lock 2>/dev/null; then
    [ -n "$(find .lock -maxdepth 0 -mmin +120 2>/dev/null)" ] || exit 0
    rm -rf .lock && mkdir .lock
fi
trap 'rm -rf .lock' EXIT
# Keep the Mac awake while it runs: a sleeping Mac stretched one run over 5 h.
caffeinate -i -w $$ &

echo "== $(date '+%F %T') review"
journal started ""
"$PARROT" dream prepare || { journal failed "prepare"; exit 1; }

rm -f decisions-claude.json
if grep -q '"id"' candidates.json 2>/dev/null; then
    "$BIN/judge_claude.sh" candidates.json decisions-claude.json || journal failed "judge"
fi

# Writes the report, state.json and the "done" line of the journal.
"$PARROT" dream apply --judge decisions-claude.json || { journal failed "apply"; exit 1; }
echo "== $(date '+%F %T') done"
