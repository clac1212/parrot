# Fork ADR-012 :: One app to give to a friend

Last updated: `2026.10.07` · Status: **built**, first DMG untested on another Mac

> The fork can be given to someone as one DMG: the app carries everything
> the fork runs outside it, installs it at launch, and starts on Parakeet
> Ultra. Signed with the free Apple Development certificate, not notarized:
> the friend clicks "Ouvrir quand même" once, and gets no updates.

## 1. Decision

- **Parakeet Ultra is the recommended model** (`ModelRegistry`, two flags).
  A new user used to get Whisper Base (English), and onboarding switched
  anyone ticking another language to `whisper-small`. Parakeet Ultra is
  multilingual, so onboarding now keeps it for everyone.
- **The app carries what ran outside it.** `scripts/fork-resources.sh`,
  called by `build-app.sh` before signing (one line there), puts in
  `Contents/Resources/fork`:
  - `dream/` — the daily review's scripts (fork-009), Bonsai's included
    (it only runs when its model is installed, fork-009 §6);
  - `mediaremote/` — the MediaRemote adapter (fork-008), compiled there and
    signed with the app's identity.
  `ForkResources.install()`, one line in `Daemon` before the panel, copies
  them at each launch to `dream/bin` and `mediaremote` in Application
  Support, where `run.sh`, launchd and perl already looked: paths unchanged,
  and an update brings its scripts along. It replaces
  `build-mediaremote.sh` and `install-dream.sh`, which installed them from
  the source tree.
- **Quarantine is removed from the copies.** An app copied out of a
  downloaded DMG is quarantined, and so is what it copies. Tested
  2026-10-07: perl refuses a quarantined adapter ("Failed to load
  framework") and loads it once the attribute is gone.
- **Claude Code found where it is.** `run.sh` adds `~/.claude/local` (the
  older installer) to its PATH and, when `claude` is still missing, asks the
  user's own shell (`zsh -lic 'command -v claude'`), which covers nvm and the
  like. The Claude desktop app has no `claude` command: without Claude Code
  the review runs with "no judge" and adds nothing.
- **`scripts/fork-dmg.sh`** builds `build/Parrot-fr-<version>.dmg`: the app
  signed with the Apple Development identity, an Applications shortcut, and
  a French `Lisez-moi.txt` (`packaging/fork-Lisez-moi.txt`: install, the two
  grants, what is kept, Claude Code optional, no updates). Refuses
  uncommitted changes, so each DMG is a commit. The version is
  `git describe`, never a bare tag, so Sparkle stays off (fork-001).
- **Bonsai is not in the DMG**: 8 GB of model, ~15 GB of memory at peak (too
  much for a 16 GB Mac), and only on trial. If it replaces Claude, it is
  downloaded at the first review, on Macs with the memory for it.

## 2. Options considered

| Option | Why not |
|---|---|
| Developer ID + notarization + own appcast | The right way to distribute (opens normally, updates). Needs the paid Apple Developer Program (99 $/year): not worth it for one friend. Upstream's `make-dmg.sh` already does it given the certificate. |
| Upstream's `make-dmg.sh` with `PARROT_NOTARIZE=0` | Requires a Developer ID identity even when not notarizing. |
| The friend builds from source | Xcode, an Apple ID, the terminal: simple only for a developer. |
| Point `MediaPause` and launchd straight into the bundle | Two code paths (app vs. `swift run`), and launchd's job would break when the app moves; copying keeps one. |
| Copy only when the version changes | A dev build edited without a commit keeps its version and would keep stale scripts; the copy is a few files. |
| Bundle Bonsai | See above. |

## 3. Design Implications

- **Untested: an Apple Development–signed app on another Mac.** It should
  run once "Ouvrir quand même" is clicked (a valid signature with a Team ID,
  no restricted entitlement), but that is a hypothesis until the first
  friend opens it.
- The app keeps upstream's bundle ID (fork-001): it replaces an official
  Parrot already installed.
- The corpus is on by default (fork-003): the friend's dictations, audio and
  text, stay on their Mac; the Lisez-moi says so. With Claude Code, short
  excerpts go to Anthropic under their account.
- No updates: a new version is a new DMG.
- First launch downloads Parakeet (603 MB); the first review downloads
  Cohere (2.1 GB).

## 4. When to Revisit

- The first friend's install — note here whether "Ouvrir quand même" was
  enough.
- More than a couple of people → Developer ID, notarization, own bundle ID
  and appcast (fork-001 §4).
