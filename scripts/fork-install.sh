#!/usr/bin/env bash
# Fork-only: build, sign with the keychain's Apple Development identity, and
# install Parrot.app over the official one. See docs/decisions/fork-001-local-signing.md.
#   scripts/fork-install.sh
#
# Wraps scripts/dev-install.sh, which signs with a Developer ID by default:
# this fork has none, and an ad-hoc signature would lose the Microphone and
# Accessibility grants on every build. An Apple Development certificate
# (free, from an Apple ID in Xcode → Settings → Accounts) carries a Team ID,
# which the hardened runtime needs to load the embedded Sparkle.framework,
# and keeps one designated requirement across builds.
#
#   PARROT_SIGN_IDENTITY  overrides the identity (default: the first Apple Development one)
#   PARROT_LINK_DIR       passed through (default /usr/local/bin; empty skips the link)
#
# The review scripts and the media adapter are built into the app
# (scripts/fork-resources.sh) and installed by it at launch (fork-012).

set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${PARROT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"

if [ -z "$IDENTITY" ]; then
    echo "no Apple Development identity in the keychain." >&2
    echo "  Xcode → Settings → Accounts: add an Apple ID, then Manage Certificates… → + → Apple Development." >&2
    echo "  If Xcode shows one but this still fails, install Apple's WWDR G3 intermediate:" >&2
    echo "  https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer" >&2
    exit 1
fi

PARROT_SIGN_IDENTITY="$IDENTITY" exec scripts/dev-install.sh
