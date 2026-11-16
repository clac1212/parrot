# Fork ADR-016 :: One model, no language to pick

Last updated: `2026.11.16` · Status: **built**

> Parrot runs Parakeet Ultra, full stop, in the Mac's languages. The panel
> no longer offers a model or a language menu; the model's name stays under the status, as information (loading,
> downloading). The user asked for it: opinionated software.

## 1. Decision

- **The panel** (fork-010): the « Modèle » row and its menu are gone. The
  header still names the model and shows its loading or download.
- **Startup** (`Daemon`): the model is `ModelRegistry.recommended()` —
  Parakeet Ultra since fork-012 — whatever `settings.json` holds. A
  `whisper-small` left there by an older version, or a hand edit, changes
  nothing.
- **Live switching**: a change of `model` in `settings.json` no longer swaps
  engines (the `settings.observe` branch is removed). `ModelSwitcher` stays,
  idle: removing it would touch upstream files for nothing.
- **Kept for us**: `--model` on the command line (benches, tests), the other
  models in the registry, the `model` key in `settings.json` (upstream's
  schema; ignored). The upstream Settings window, unused since fork-010,
  keeps its picker.
- **No « Langue » row either** (same day, after the user tried
  Automatique): the `language.code` setting is ignored, and Parrot follows
  the Mac's languages (`SpokenLanguage.plan`): one supported language → it is
  passed to Parakeet (a French-only Mac gets `fr`, as the user always had:
  the log shows `lang fr` under Automatique); several → Parakeet chooses.
  The languages ticked at onboarding (`language.spoken`) still count.

## 2. Options considered

| Option | Why not |
|---|---|
| Keep the menu, Parakeet Ultra by default (fork-012) | A choice nobody needs: the other models are slower (Whisper) or English-only. A setting is a decision we failed to make. |
| Remove the other models from the registry and the code | Many upstream files (registry, onboarding, Settings window, CLI, tests): costly rebases for no change the user sees. |
| Honour a model set by hand in `settings.json` | A hidden setting is still a setting. |
| Keep « Langue » for bilingual Macs | The Mac's languages already say it; a bilingual Mac lets Parakeet choose, which fork-004 measured as safe (no drift into English). |

## 3. Design Implications

- Parakeet Ultra knows 25 European languages: someone dictating in
  Japanese or Chinese isn't covered. Accepted: the fork is for French
  speakers and their friends.
- Whisper models downloaded before stay on disk until removed by hand
  (`parrot models`).
- Upstream's onboarding still writes `whisper-small` for a non-English
  speaker on an English-only model; with Parakeet Ultra as the default it
  never does, and the value would be ignored anyway.

## 4. When to Revisit

- A better French model, measured on the user's corpus (e.g. Fluid Speech
  Pro, 2026-11-13: same base, not yet compared): swap the default, still no
  menu.
- A friend who needs a language Parakeet doesn't have.
- A bilingual Mac (French + English) whose French dictations come out in
  English: then pass the Mac's first language.
