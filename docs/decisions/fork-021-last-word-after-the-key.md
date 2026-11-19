# Fork ADR-021 :: The last word after the key

Last updated: `2026.11.19` · Status: **built**, to be measured over a few days

> The user feels the end of a dictation is sometimes eaten when they let go
> of the key a little early. Parrot stopped the microphone at the release.
> Now, released while the voice is still on, it records on until 150 ms of
> silence, 400 ms at most. Released in silence, it stops at once, as before.

## 1. What the corpus says (2026-11-19)

2,930 recordings, each split into 20 ms frames, with a threshold halfway
between its quiet (10th percentile) and loud (90th) frames:

- **15.3 %** stay loud through their last 300 ms: the user is most likely
  still speaking at the release. Another 12.9 % are loud only in their last
  100 ms, which could be a word or the key's noise.
- **0.1 %** are loud in their first 60 ms: the start is fine. The
  microphone's first sample comes ~56 ms after the press.
- Not shown: that words are lost. In the dictations that end loud the user
  fixes the last two words by hand no more often (6.2 %) than in the others
  (5.5 %). A word cut at the end may be retyped beyond the watched span, or
  re-dictated. The user's impression is the evidence; the log will show how
  often the wait runs.

## 2. Decision

- **`Audio/SpeechTail.swift`** hears the level of every chunk the capture
  delivers (the `onLevel` the indicator already uses), since the press.
- **At release**, if the last 100 ms are louder on average than halfway
  between the recording's quiet and loud chunks, the recording goes on. It
  ends at the first 150 ms with no loud chunk, or 400 ms after the release.
- **No wait** for a recording under 1 s, or one whose quiet and loud chunks
  are less than 10 dB apart. There the room is as loud as the voice, so it
  can't tell them apart (the corpus's noisiest recordings are ~11 dB apart).
- **A press during the wait** ends the previous recording first, so
  dictations never overlap.
- **The latency log stays honest.** Release→text still counts from the key,
  so the wait is in it. `stop` is the capture's own stop, without the wait.
  A line says how long each wait ran: « voice on at release: recorded N ms
  more ».
- **Upstream files:** a defaulted `speechTail` parameter and a split of
  `release()` in `DictationController`, and the level callback set in
  `Daemon` even without an overlay.

## 3. Options considered

| Option | Why not |
|---|---|
| A fixed margin after every release (0.5–2 s) | Adds the margin to every dictation, 85 % of which don't need it; speed is the fork's first aim (release→text median 158 ms on the last 300). |
| Recording before the press (a rolling buffer) | The microphone would run all the time: the orange dot always on, AirPods held in call mode, and upstream's promise that the device doesn't run between presses (#52) broken. The start is fine anyway (§1). |
| A voice-activity model (Silero, FluidAudio's VAD) | The levels the capture already computes answer the one question asked here: is the voice still on. |
| A setting for the margin | Nobody would know what to put in it. |

FluidVoice's code (read 2026-11-19) defers a stop only until its
recording has started. A quick search found no margin after the release;
not checked further.

## 4. Measurements

Before (2026-11-19, the last 300 dictations): release→text median 158 ms,
p90 371 ms.

After: to fill in after a few days.

```sh
grep -h "voice on at release" ~/Library/Logs/parrot/parrot.*.log | wc -l
```

That gives the share of dictations that waited and the median wait, from
the log.

## 5. When to revisit

- It waits on far more than ~15 % of dictations (noise read as voice):
  raise `minimumSpread`, or require more of the last 100 ms.
- The user still finds the end eaten: lengthen `cap`, or look at the
  silence trim (`SilenceTrimmer`) and Parakeet's padding.
- The user feels the release is slower: shorten `quiet`.
