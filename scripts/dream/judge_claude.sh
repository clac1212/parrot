#!/bin/bash
# Claude as the judge of the nightly review (fork-009): candidates in, one
# verdict per candidate out (structured output). Short excerpts leave the Mac;
# audio never does. No tools, no MCP servers, no session kept.
set -euo pipefail
BIN="$(cd "$(dirname "$0")" && pwd)"
claude -p "$(cat "$BIN/judge_prompt.md")" \
    --model sonnet --output-format json --no-session-persistence --strict-mcp-config \
    --disallowedTools "Bash,Edit,Write,Read,NotebookEdit,WebFetch,WebSearch,Glob,Grep,Task,Agent" \
    --json-schema "$(cat "$BIN/judge_schema.json")" < "$1" > "$2"
