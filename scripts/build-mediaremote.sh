#!/usr/bin/env bash
# Builds the vendored MediaRemote adapter (fork-008) into
# ~/Library/Application Support/parrot/mediaremote, where Parrot looks for it
# to pause media while dictating. macOS 15.4+ lets only Apple-entitled
# binaries use MediaRemote, so Parrot runs the adapter through /usr/bin/perl,
# which loads this framework. Not linked into Parrot, not in its bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=vendor/mediaremote-adapter
DEST="$HOME/Library/Application Support/parrot/mediaremote"
BUILD=build/mediaremote/MediaRemoteAdapter.framework

mkdir -p "$BUILD"
clang -arch arm64 -dynamiclib -fobjc-arc -fvisibility=default -O2 -mmacosx-version-min=14.0 \
    -I"$SRC/include" -I"$SRC/src" \
    "$SRC"/src/adapter/{env,get,globals,keys,now_playing,repeat,seek,send,shuffle,speed,stream,test}.m \
    "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/{Debounce,helpers}.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
    -o "$BUILD/MediaRemoteAdapter"
# Ad-hoc: perl loads it with no library validation; arm64 needs a signature.
codesign --force --sign - "$BUILD/MediaRemoteAdapter"

mkdir -p "$DEST"
chmod 700 "$(dirname "$DEST")" "$DEST"
rm -rf "$DEST/MediaRemoteAdapter.framework"
cp -R "$BUILD" "$DEST/"
cp "$SRC/bin/mediaremote-adapter.pl" "$DEST/"
echo "→ media adapter installed in $DEST"
