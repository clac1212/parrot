#!/usr/bin/env bash
# Fork-only (fork-012): puts in Parrot.app what the fork's features run
# outside the app, so one app is the whole install. Called by build-app.sh
# before it signs the app; Parrot copies them out at each launch
# (ForkResources.swift).
#   scripts/fork-resources.sh <Parrot.app> <signing identity, or - for ad-hoc>
#
#   Contents/Resources/fork/dream        the daily review's scripts (fork-009)
#   Contents/Resources/fork/mediaremote  the MediaRemote adapter (fork-008):
#       macOS 15.4+ lets only Apple-entitled binaries use MediaRemote, so
#       Parrot runs the adapter through /usr/bin/perl, which loads this
#       framework. Not linked into Parrot.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: scripts/fork-resources.sh <Parrot.app> <identity>}"
IDENTITY="${2:?usage: scripts/fork-resources.sh <Parrot.app> <identity>}"
FORK="$APP/Contents/Resources/fork"
SRC=vendor/mediaremote-adapter
FRAMEWORK="$FORK/mediaremote/MediaRemoteAdapter.framework"

rm -rf "$FORK"
mkdir -p "$FORK/dream" "$FRAMEWORK"

cp scripts/dream/run.sh scripts/dream/judge_claude.sh scripts/dream/judge_bonsai.py \
    scripts/dream/judge_prompt.md scripts/dream/judge_schema.json "$FORK/dream/"
chmod +x "$FORK/dream/run.sh" "$FORK/dream/judge_claude.sh"

clang -arch arm64 -dynamiclib -fobjc-arc -fvisibility=default -O2 -mmacosx-version-min=14.0 \
    -I"$SRC/include" -I"$SRC/src" \
    "$SRC"/src/adapter/{env,get,globals,keys,now_playing,repeat,seek,send,shuffle,speed,stream,test}.m \
    "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/{Debounce,helpers}.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
    -o "$FRAMEWORK/MediaRemoteAdapter"
cp "$SRC/bin/mediaremote-adapter.pl" "$FORK/mediaremote/"
# Signed like the app, so its seal covers it; perl loads it with no library
# validation, so any signature would do.
codesign --force --timestamp=none --sign "$IDENTITY" "$FRAMEWORK/MediaRemoteAdapter"
echo "→ review scripts and media adapter in $FORK"
