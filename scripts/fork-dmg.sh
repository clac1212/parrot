#!/usr/bin/env bash
# Fork-only (fork-012): a DMG of the fork to give to a friend — the app,
# signed with the keychain's Apple Development identity (fork-001), an
# Applications shortcut and a French Lisez-moi. Not notarized: that needs a
# Developer ID, so macOS asks once for "Ouvrir quand même". No updates
# (Sparkle stays off, fork-001): send a new DMG.
#   scripts/fork-dmg.sh   → build/Parrot-fr-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
    echo "uncommitted changes: commit first, so the DMG is a version you can find again." >&2
    exit 1
fi

IDENTITY="${PARROT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "no Apple Development identity in the keychain (see scripts/fork-install.sh)." >&2; exit 1; }

# Never a bare tag: a numeric version would turn Sparkle on (fork-001).
VERSION="$(git describe --tags --always)"
VERSION="${VERSION#v}"
BUILD="${PARROT_BUILD_DIR:-build}"
STAGE="$BUILD/dmg-stage"
DMG="$BUILD/Parrot-fr-$VERSION.dmg"

PARROT_SIGN_IDENTITY="$IDENTITY" PARROT_TIMESTAMP=none PARROT_BUILD_DIR="$BUILD" \
    scripts/build-app.sh "$VERSION"

echo "→ packaging $DMG"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$BUILD/Parrot.app" "$STAGE/Parrot.app"
ln -s /Applications "$STAGE/Applications"
cp packaging/fork-Lisez-moi.txt "$STAGE/Lisez-moi.txt"
rm -f "$DMG"
hdiutil create -volname "Parrot" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp=none "$DMG"
echo "$DMG ($(du -h "$DMG" | cut -f1))"
