# Releasing TinyTrack (iOS) — Runbook

How to ship a new build to **TestFlight** and the **App Store**, the automated way,
plus the gotchas that will bite you on a fresh machine.

---

## TL;DR — the happy path

```bash
# 1. Bump the version in pubspec.yaml (the number after the +)
#    version: 1.1.3+6   ->   1.1.3+7
#    (bump 1.1.3 -> 1.1.4 only when it's a new user-facing version)

# 2. From the ios/ directory:
cd "ios"

fastlane beta       # build -> TestFlight (UAT / testing)
fastlane release    # build -> App Store, auto-submits for review
```

That's it. No Xcode, no clicking, no 2FA. Auth is via an App Store Connect API key.

After `fastlane beta`, the build shows in App Store Connect → TestFlight after
~5–15 min of "Processing". After `fastlane release`, it goes to App Store review
and auto-releases once Apple approves.

---

## What each lane does

Defined in `ios/fastlane/Fastfile`:

| Lane | Steps |
|------|-------|
| `beta` | `flutter pub get` → `flutter build ios --release --no-codesign` → `build_app` (archive + sign + export IPA via gym) → `upload_to_testflight` |
| `release` | same build → `upload_to_app_store` (skips screenshots/metadata, submits for review, auto-releases on approval) |

We build the IPA with **gym** (not `flutter build ipa`) because gym's export is more
robust with the embedded Apple Watch app.

---

## One-time setup (already done — here for a fresh machine)

### 1. Toolchain

```bash
brew install --cask flutter     # Flutter SDK + Dart
brew install fastlane
xcodebuild -downloadPlatform iOS       # Xcode ships without device SDKs
xcodebuild -downloadPlatform watchOS   # needed for the Watch companion target
```

Then sign into your Apple account in **Xcode → Settings → Accounts** (needed once so
automatic signing can fetch provisioning profiles).

### 2. App Store Connect API key (this is what makes it unattended)

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**
2. Generate a key with the **App Manager** role.
3. Save the downloaded `.p8` as **`ios/fastlane/AuthKey.p8`** (you can only download it once).
4. Put the Key ID and Issuer ID in **`ios/fastlane/.env.default`**:
   ```
   ASC_KEY_ID=XXXXXXXXXX
   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

⚠️ `AuthKey.p8` and `.env.default` are **gitignored** — they hold secrets, never commit them.

---

## Gotchas we hit (and how to fix them fast)

These all cost time once. If a build breaks on a fresh/reset machine, check these first.

### `exportArchive Copy failed` — the rsync trap ⚠️ MOST LIKELY

Xcode's IPA export shells out to `rsync`. If **Homebrew's rsync** (3.4.x) is on the
PATH ahead of Apple's `/usr/bin/rsync`, the export dies with a cryptic `Copy failed`
(real error buried in the logs: `rsync error: syntax or usage error at main.c(1806)`).

**Fix:**
```bash
brew unlink rsync      # makes `rsync` resolve to Apple's /usr/bin/rsync
```
Keep it unlinked for iOS release work. (`brew link rsync` to restore it for other uses,
but then exports break again.)

Verify: `which rsync` should print `/usr/bin/rsync`, and `rsync --version` should say
`openrsync` (not `3.4.x`).

### `Method not found: 'CupertinoPageTransitionsBuilder'`

Newer Flutter moved this class from the material library to the cupertino library.
Any file using it needs `import 'package:flutter/cupertino.dart';`.

### `iOS/watchOS 26.x is not installed` during archive

A fresh Xcode has no device SDKs. Run the `xcodebuild -downloadPlatform` commands above.

### `No Accounts` / `No profiles for '...' were found`

Xcode isn't signed in. Add your Apple ID in Xcode → Settings → Accounts, and make sure
both the `Runner` and `TinyTrackWatch` targets use **Automatically manage signing**
with the `Diego Allies` team.

---

## Project facts

- Bundle ID: `com.tinytrack.tinytrackApp` (watch: `.watchkitapp`)
- Team ID: `GLWG756ZM9`
- App Store Connect app ID: `6786685436`
- Version source of truth: `pubspec.yaml` `version:` — Xcode reads `FLUTTER_BUILD_NAME`
  / `FLUTTER_BUILD_NUMBER` from it, so you never edit versions in Xcode.
- Store copy / metadata: `docs/appstore_metadata.md`
- Screenshots: `docs/appstore/`
</content>
