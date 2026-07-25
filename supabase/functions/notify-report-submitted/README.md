# Parent "report submitted" push — setup runbook

Native APNs (no Firebase). Code is done; these are the config-only steps that
need your Apple account / Xcode / Supabase (I can't do them from outside).

## 1. Xcode (on the Mac)
- Open `ios/Runner.xcworkspace` → Runner target → **Signing & Capabilities**.
- Click **+ Capability → Push Notifications**. (This creates + wires the
  entitlement automatically — that's why there's no hand-made `.entitlements`.)
- Rebuild. The app already calls `registerForRemoteNotifications` via
  `AppDelegate.swift`.

## 2. Apple Developer — APNs Auth Key
- developer.apple.com → Certificates, IDs & Profiles → **Keys** → +.
- Enable **Apple Push Notifications service (APNs)**, download the `AuthKey_XXXX.p8`.
- Note the **Key ID** (10 chars) and your **Team ID**. Bundle ID = the app's.

## 3. Supabase
```bash
# a) table
supabase db push            # or run supabase/2026-07-24_device_tokens.sql

# b) function
supabase functions deploy notify-report-submitted

# c) secrets
supabase secrets set \
  APNS_KEY="$(cat AuthKey_XXXX.p8)" \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=YYYYYYYYYY \
  APNS_BUNDLE_ID=<the app bundle id> \
  APNS_HOST=api.push.apple.com
```
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected by
the platform — don't set those.

## 4. APNS_HOST gotcha
- **Debug build run from Xcode** → tokens are sandbox → use
  `api.sandbox.push.apple.com`.
- **TestFlight / App Store build** → `api.push.apple.com` (prod).
  Two envs, or flip the secret when testing.

## 5. Test
- Log in on two devices: one **owner** (parent), one **logger** (nanny) sharing
  the same baby.
- As the nanny, submit a weekly report → the parent's phone gets
  "Weekly report submitted 📋".
- Check the function logs (`supabase functions logs notify-report-submitted`) if
  nothing arrives — it returns `{sent, cleaned}` or a reason (`no tokens` means
  the parent's device hasn't registered yet; open the app once on that device).

## How it flows
app submit → `PushService.notifyReportSubmitted` → invoke this function →
looks up baby owners (excl. submitter) → their `device_tokens` → APNs.
Device tokens are captured in `AppDelegate` and stored by `PushService`.
