# Parent "report submitted" push — setup runbook

FCM (Firebase Cloud Messaging) for both iOS and Android. Firebase is only the
messaging sender + telemetry; Supabase stays the backend. Everything used here is
on the **Spark (free)** plan — FCM, Analytics and Crashlytics are all free at any
volume. Do **not** upgrade to Blaze.

Firebase project: **tinytrack** (`tinytrack-by-diego`)

| Platform | App ID | Bundle / package |
|---|---|---|
| iOS | `1:166640666899:ios:4ef2df13187e035431f2e6` | `com.tinytrack.tinytrackApp` |
| Android | `1:166640666899:android:c6ce5d66fb4dff9d31f2e6` | `com.tinytrack.tinytrack_app` |

There is also a `com.tinytrack.tinytrackApp.watchkitapp` iOS app registered by a
first `flutterfire configure` run that auto-detected the watch target. It's inert
and nothing references it — keep it only if you later add the native Firebase
watchOS SDK to the `TinyTrackWatch` target. **Don't attach the APNs key to it.**

## 1. Apple Developer — APNs Auth Key

Firebase talks to APNs on your behalf, so iOS still needs an Apple key.

- developer.apple.com → Certificates, IDs & Profiles → **Keys** → **+**
- Enable **Apple Push Notifications service (APNs)**, download `AuthKey_XXXX.p8`
- ⚠️ One-time download. This is **not** `ios/fastlane/AuthKey.p8`, which is an
  App Store Connect API key — different purpose, same extension.
- Note the **Key ID** (10 chars). Team ID is `GLWG756ZM9`.

## 2. Firebase Console — upload the key

Project settings → **Cloud Messaging** → Apple app configuration → pick the app
with bundle `com.tinytrack.tinytrackApp` → **APNs Authentication Key** → upload
the `.p8` + Key ID + Team ID.

Unlike the old raw-APNs setup there's no sandbox-vs-production host to juggle:
Firebase picks the right APNs environment from the token itself, so debug builds
and TestFlight builds both just work.

## 3. Xcode (on the Mac)

`ios/Runner.xcworkspace` → **Runner** target → **Signing & Capabilities** → **+ Capability**:

- **Push Notifications**
- **Background Modes** → tick **Remote notifications**

## 4. Supabase

```bash
# a) table
supabase db push            # or run supabase/2026-07-24_device_tokens.sql

# b) function
supabase functions deploy notify-report-submitted

# c) secret — the service-account JSON from
#    Firebase Console > Project settings > Service accounts > Generate new private key
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat ~/Downloads/tinytrack-by-diego-firebase-adminsdk-XXXXX.json)"
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform — don't set those.

⚠️ The service-account JSON can send push as your app. Never commit it; delete it
from `~/Downloads` once the secret is set. (`firebase_options.dart`,
`google-services.json` and `GoogleService-Info.plist` are *client* identifiers
and are safe to commit.)

## 5. Test

- Log in on two devices: one **owner** (parent), one **logger** (nanny), sharing
  the same baby.
- As the nanny, submit a weekly report → the parent's phone gets
  "Weekly report submitted 📋".
- `supabase functions logs notify-report-submitted` returns `{sent, cleaned}` or
  a reason. `no tokens` means that device hasn't registered yet — open the app
  once while logged in as the parent.

## How it flows

```
app submit
  → PushService.notifyReportSubmitted
  → invoke notify-report-submitted
  → verify caller is a member of the baby (their JWT)
  → look up baby owners, excluding the submitter (service role)
  → their device_tokens rows
  → FCM HTTP v1  ──→ APNs ──→ iOS
                 └─────────→ Android
```

Tokens are captured by `PushService` (FCM registration tokens; both platforms
share the table) and refreshed on `onTokenRefresh` and on sign-in. Sign-out
deletes the row so a shared device stops receiving the previous user's pushes.
Dead tokens are pruned when FCM reports `UNREGISTERED` / `INVALID_ARGUMENT`.

Tapping a push routes via `PushService._handleTap` using the payload's `type`
field — `weekly_report_submitted` deep-links to `/weekly-report`.

## Notes on coexisting with local notifications

`flutter_local_notifications` (feeding / sleep / medication / weekly reminders)
and `firebase_messaging` share the iOS notification delegate safely **as long as
`AppDelegate` never assigns `UNUserNotificationCenter.current().delegate`
itself**. `FlutterAppDelegate` conforms to `FlutterAppLifeCycleProvider`, which
firebase_messaging detects and then defers to the plugin chain rather than
seizing the delegate. Don't "fix" this by setting the delegate manually — that
breaks the scheduled reminders.

On Android, background pushes are drawn by the OS using the channel named in
`AndroidManifest.xml` (`remote_updates`). That channel is created eagerly in
`NotificationService.initialize()`, because Android silently drops notifications
pointing at a channel that doesn't exist yet.
