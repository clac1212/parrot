# Fork ADR-007 :: The built-in microphone over a Bluetooth one

Last updated: `2026.10.01`

> When the system's default input is a Bluetooth device (AirPods, a headset),
> Parrot records from the Mac's built-in microphone instead. Wired and USB
> microphones are kept; a Mac without a built-in microphone keeps Bluetooth.

## 1. Decision

- `InputDevice.defaultInputID()` (upstream, two lines) now returns
  `PreferredInput.choose(systemDefault)`: the built-in input device (transport
  `BuiltIn`, with input channels) in place of a `Bluetooth`/`BluetoothLE` one.
  Every reader of "the default input" goes through it — capture setup and
  `HALInput`'s route watcher — so connecting AirPods while the built-in
  microphone is in use is not a route change.
- The substitution is logged once when it starts: `input: <name> is
  Bluetooth; recording from <name>` (device names, no text).
- No setting.

## 2. Rationale

Corpus (fork-003), 59 dictations on 2026-10-01, leading digital silence
(exact zero samples) at the start of each recording:

| Input | Dictations | Leading zeros |
|---|---|---|
| 48 kHz (built-in microphone) | 31 | 0 ms, every one |
| 24 kHz (AirPods Pro, Bluetooth hands-free) | 28 | 509–653 ms in 27; 64 ms in one started 5 s after the previous |

The log agrees: on the 24 kHz input, `first sound` came 500–650 ms after
`first sample`; on 48 kHz they were equal. Speech in that half second was
lost: the two corpus corrections that added words at the start ("Sur la
partie…", "plusieurs…") are both on it. A test of three immediate "un, deux,
trois…" on the built-in microphone lost nothing. Opening a Bluetooth headset's
microphone also switches its playback to call quality, which the user heard
as media "going weird" during dictation.

| Option | Why not |
|---|---|
| Keep the Bluetooth microphone open between dictations | The headset would stay in call quality all the time. |
| Keep it, and ask the user to wait half a second | Silent data loss nobody remembers to avoid. |
| A microphone picker in Settings | A setting for a default that is right for nearly everyone (Superwhisper and Wispr Flow give the same advice for AirPods). |

## 3. Design Implications

- The built-in microphone hears more of the room than a headset's.
- A Bluetooth microphone the user wants on purpose (a dedicated Bluetooth
  mic) is replaced too; revisit if that comes up.
- `--capture engine` (AVAudioEngine, not the default since #52) follows the
  system default and doesn't apply this.

## 4. When to Revisit

- A Bluetooth microphone that starts without the half-second gap → measure
  it (corpus leading zeros) and keep those.
- The user dictates mostly away from the Mac with a headset.
