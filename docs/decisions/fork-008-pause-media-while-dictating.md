# Fork ADR-008 :: Pause media while dictating

Last updated: `2026.10.01`

> When a dictation starts while media plays (Spotify, Music, a browser
> video), Parrot pauses it, and resumes it when the key is released. Only what
> Parrot paused is resumed, and only if the same app is still the one playing.

## 1. Decision

- `MediaPause` (`Sources/ParrotCore/Media/MediaPause.swift`), a
  `DictationObserver`: pause at `dictationStarted`, resume at
  `dictationTranscribing` (the microphone is closed) or `dictationFailed` (a
  short tap, a capture that didn't start). One line in `Daemon.swift`.
- **MediaRemote through the vendored adapter.** Since macOS 15.4 only
  Apple-entitled binaries may read or control the now-playing app. The
  BSD-3 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
  (pinned commit in `vendor/mediaremote-adapter/VENDORED.md`) works around
  it: `/usr/bin/perl`, which is entitled, loads a small framework that talks
  to MediaRemote. Parrot keeps one `stream --no-diff` process running for the
  current state, and runs `send 1` (pause) / `send 0` (play) per dictation.
- **Built at install, outside the app bundle.**
  `scripts/build-mediaremote.sh` (run by `fork-install.sh`) compiles the
  framework with clang, signs it ad hoc, and installs it with the script in
  `~/Library/Application Support/parrot/mediaremote`. Not linked into
  Parrot, so Parrot's signature and upstream's `build-app.sh` are untouched.
  Without it, `MediaPause` logs once and stays off.
- No setting: on whenever the adapter is installed.

## 2. Rationale

Measured on macOS 27.0 (2026-10-01): `get` reports Spotify with its state
(365 ms per call, hence the long-lived stream instead of a lookup at each
press); `send` takes ~20 ms. The adapter's README lists macOS 27.0 as tested.

| Option | Why not |
|---|---|
| The media Play/Pause key (simulated) | A toggle: without knowing what plays, it would start music that was paused. |
| CoreAudio's per-process "running output" (macOS 14.2+, public) to know what plays | Apps keep output running while paused (browsers, calls): false "playing", then the key starts media. |
| AppleScript to Spotify/Music | One app at a time, an Automation prompt per app, nothing for browsers. |
| Lowering the volume instead (ducking) | Media keeps playing into the microphone and moves on while the user talks. |
| The Swift-package forks (Beingpax, ejbills) | Older than upstream's macOS 27 fixes, and a dynamic library plus a resource bundle to embed in the app. |

## 3. Design Implications

- A `perl` process runs alongside Parrot (terminated when Parrot quits;
  restarted up to five times if it exits).
- This relies on Apple not closing the perl loophole; the adapter's author
  tracks each macOS release. If it breaks, dictation is unaffected: nothing
  pauses.
- The pause lands ~20–50 ms after recording starts.
- Media is resumed at release, before the transcript is pasted.

## 4. When to Revisit

- A macOS update breaks the adapter → update the vendored copy, or drop the
  feature.
- Apple ships an entitlement or API for now-playing control.
