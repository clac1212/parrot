# Fork ADR-001 :: Local signing, installed over the official app

Last updated: `2026.10.01`

> The fork builds `Parrot.app` with upstream's bundle ID `com.humanitas.parrot`, signs it with the user's free Apple Development certificate, and installs it over the official app in `/Applications`. Sparkle updates stay off, so a release never replaces the fork.

## 1. Decision

- **Apple Development identity**, from an Apple ID signed into Xcode (Settings → Accounts → Manage Certificates… → Apple Development). `scripts/fork-install.sh` picks the first one in the keychain and passes it to upstream's `dev-install.sh` through `PARROT_SIGN_IDENTITY`. The designated requirement names the bundle ID and the certificate's common name, so it is the same on every build, and TCC keeps the Microphone and Accessibility grants across rebuilds. The hardened runtime and upstream's entitlements are unchanged.
- **Upstream's bundle ID kept.** The fork replaces the official install instead of running beside it.
- **No Sparkle updates.** `Updater.configurationProblem` turns updates off when `CFBundleVersion` isn't purely numeric. `dev-install.sh` versions builds with `git describe`, and `fr-fast` always carries fork commits on top of an upstream tag, so the version looks like `0.2.3-4-gabc1234` and the log says `updates off: development build`.

## 2. Rationale

The fork has no Developer ID certificate. Without one, `build-app.sh` signs ad-hoc: every build is a new identity, and the grants silently stop applying (upstream ADR-005).

**A self-signed certificate was tried first and rejected.** It gives a stable designated requirement, but no Team ID. Under the hardened runtime, dyld only loads a framework signed by the same team, so the app died at launch: `Library not loaded: @rpath/Sparkle.framework … mapping process and mapped file (non-platform) have different Team IDs`. Turning library validation off (`com.apple.security.cs.disable-library-validation`) would have fixed it, but it weakens the app's protection for nothing, since a free Apple Development certificate has a Team ID.

The Apple Development certificate is issued by Apple's WWDR **G3** intermediate. A keychain holding only the old WWDR intermediate (expired 2023) lists the identity as invalid (`0 valid identities found`) and `codesign` fails with `unable to build chain to self-signed root` / `errSecInternalComponent`. Importing [AppleWWDRCAG3.cer](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer) into the login keychain fixes it.

A separate bundle ID (`com.clac1212.parrot`) was rejected: two apps would listen for the same hotkey, and it would mean an edit to upstream's `packaging/Info.plist` for no gain. Settings and the dictionary live in `~/.config/parrot` either way.

Sparkle accepts an update signed by a different Apple certificate as long as its EdDSA signature checks out (Sparkle docs, "Rotating signing keys"). If updates were on, the next upstream release would replace the fork. They are off because the version is never a bare tag.

## 3. Design Implications

- Switching between the official app and the fork changes the code identity: macOS asks for both grants again. If a grant shows as on but dictation pastes nothing, reset it: `tccutil reset Accessibility com.humanitas.parrot`.
- The Apple Development certificate expires after a year (this one on 2027-10-01). Renew it in Xcode. The common name stays the same, so the grants should survive; check the designated requirement printed by `build-app.sh`.
- Never build the fork from a commit that is exactly an upstream tag: the version would be numeric and Sparkle would turn on.

## 4. When to Revisit

- The fork gets distributed to other people: it then needs a Developer ID, notarization, its own bundle ID, and its own appcast.
- Upstream changes how `dev-install.sh` picks the version or how `Updater` decides a build is a release.
