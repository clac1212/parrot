# parrot — fr-fast fork

Fork of [humanitas-labs/parrot](https://github.com/humanitas-labs/parrot),
on-device push-to-talk dictation for macOS. This fork aims at, in order:

1. **Speed** — less time between releasing the key and the text at the cursor.
2. **French** — better and faster French dictation.
3. **A friendlier UI** — still minimal and opinionated: few settings, good defaults.

Architecture: `docs/architecture.md` (upstream's, read it first: it says where
each kind of change belongs). User docs: `README.md`.

## Product rules — opinionated software

Parrot should install, work, and be the best version for 99 % of people who
never open a setting. The user builds it step by step and understands each
step, so they won't feel complexity creep: **it's your job to push back.**

- **No new setting, toggle, or choice for the user without a fight.** First
  find the default that is right for nearly everyone, measure it, ship it.
  A setting is a decision we failed to make.
- **The software improves itself; the user does nothing.** Prefer a loop that
  learns from use and corrects its own mistakes (fork-009) over asking the
  user to review, accept, or configure. Self-correction is the safety net,
  not a confirmation dialog.
- **Before adding a feature, ask:** does it remove a step for the user, or
  add one? Is it for 99 % of people or for one case? Can it be automatic?
  If it adds UI, what UI does it remove?
- **Say so when a request drifts** toward a complex, configurable tool —
  even a reasonable-sounding one — and propose the simpler, automatic
  version. Then let the user decide.
- Information over controls: the UI may show what Parrot did (a status, a
  report); it should rarely ask the user to act.

## Fork rules

- **Document everything, as you go.** Every decision lands in
  `docs/decisions/fork-NNN-*.md` in the same change: what was decided, the
  options considered and rejected and why, the measurements behind it, and
  when to revisit. The `fork-` prefix keeps our numbers from colliding with
  upstream's ADRs on rebase. A change without its documentation isn't done.
- Branch `fr-fast`, rebased on `upstream/master`. **Never move or rename
  upstream files**; put new code in new files and keep edits to upstream files
  small, so rebases stay cheap.
- Follow upstream's rules (`docs/architecture.md` §8): no transcript text in
  logs, disk, or stats (exception: the opt-in corpus, fork-005); paths from
  `Paths`; preferences in `Settings`; new behaviour after transcription is a
  `TranscriptProcessor` or a `DictationObserver`.
- **Measure before and after** any performance change, on the latency log
  (below). A speedup without numbers isn't one.
- Fork ADRs:
  - [fork-001](docs/decisions/fork-001-local-signing.md) — local signing, installed over the official app, updates off
  - [fork-002](docs/decisions/fork-002-notch-overlay.md) — dictation indicator around the notch (DynamicNotchKit), pill as fallback
  - [fork-003](docs/decisions/fork-003-recording-corpus.md) — opt-in corpus of the user's dictations (audio; text since fork-005), for the French benchmark
  - [fork-004](docs/decisions/fork-004-parakeet-ultra.md) — Parakeet Ultra through FluidAudio as the French engine
  - [fork-005](docs/decisions/fork-005-correction-capture.md) — capture of the user's corrections after paste, in the corpus (text on disk, deliberately)
  - [fork-006](docs/decisions/fork-006-transcript-stays-on-clipboard.md) — the transcript stays on the clipboard after the paste
  - [fork-007](docs/decisions/fork-007-built-in-mic-over-bluetooth.md) — the built-in microphone instead of a Bluetooth one (AirPods lose the first ~0.55 s)
  - [fork-008](docs/decisions/fork-008-pause-media-while-dictating.md) — pause media while dictating, via the vendored MediaRemote adapter
  - [fork-009](docs/decisions/fork-009-nightly-review.md) — learn from the day's dictations ("dreaming"), once a day when the Mac is free: re-listen, find recurring errors, propose dictionary entries
  - [fork-010](docs/decisions/fork-010-menu-bar-panel.md) — a French panel from the menu bar instead of the menu and Settings window

## Commands

Run from the repo root. Give the user commands alone in a code block — they
copy-paste, and trailing punctuation has broken commands before.

```sh
swift build -c release && swift test   # build and unit tests (Xcode required for XCTest)
scripts/fork-install.sh                # build, sign with Apple Development, install over /Applications/Parrot.app, restart it
tail -50 ~/Library/Logs/parrot/parrot.err.log   # app log: timings, never text
```

Always install with `scripts/fork-install.sh`, never `dev-install.sh` alone:
without the Apple Development identity the build is ad-hoc signed and loses
the Microphone and Accessibility grants (fork-001). A self-signed identity
doesn't work: no Team ID, so the hardened runtime refuses Sparkle.framework
and the app dies at launch. After switching between the
official app and the fork, macOS asks for both grants again.

## Measuring

Every dictation logs one line (`App/LatencyLog.swift`):

```
⏱ 650 ms release→text · 5.7 s audio · … · enc 97 · dec 486 · … · lang fr · 48 tokens · …
```

```sh
grep -h "⏱" ~/Library/Logs/parrot/parrot.*.log | tail -20
```

`parrot-bench` (`swift run -c release parrot-bench transcription|capture …`)
replays audio through the pipeline for repeatable numbers.

Baseline, the official app's log on 2026-10-01 (49 dictations, mostly
`whisper-small` in French): 140 ms–6.5 s release→text; the decoder is 88 %
of it, 9.1 ms per token, so time grows with what you say.
