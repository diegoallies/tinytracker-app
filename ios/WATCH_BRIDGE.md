# Apple Watch bridge

How the SwiftUI Apple Watch app and this Flutter app talk to each other.

```
Apple Watch (SwiftUI)  ──WatchConnectivity──▶  iOS host (WatchSessionManager.swift)
                                                      │  MethodChannel "tinytrack/watch"
                                                      ▼
                                               Flutter (WatchBridge) ──▶ Supabase
                       ◀──updateApplicationContext──  (summary back to watch)
```

The watch NEVER talks to Supabase directly. It sends log events to the phone;
the phone writes them with the same action classes the UI uses (so offline
queueing + validation apply), then pushes a fresh summary back to the watch.

## Channel: `tinytrack/watch`

### Watch ➜ Phone  (native invokes Flutter method `onWatchEvent`)
The watch sends a `[String: Any]` via `WCSession.sendMessage` (falls back to
`transferUserInfo` when the phone is unreachable, so logs queue offline). The
host forwards it verbatim as the arguments of `onWatchEvent`:

| action       | extra keys                          | effect                         |
|--------------|-------------------------------------|--------------------------------|
| `logFeed`    | `type` (default `bottle`), `amountMl` (Int) | inserts a feeding       |
| `logDiaper`  | `type` = `wet` \| `dirty` \| `both` | inserts a diaper               |
| `sleepStart` | —                                   | starts a sleep session         |
| `sleepStop`  | —                                   | stops the active sleep session |
| `logMed`     | `name` (String)                     | logs a medication dose         |

Optional on any event: `loggedAt` (ISO-8601 string). Omit to use "now".

Example:
```swift
WCSession.default.sendMessage(
  ["action": "logFeed", "type": "bottle", "amountMl": 150],
  replyHandler: nil, errorHandler: nil)
```

### Phone ➜ Watch  (Flutter invokes native method `updateWatchContext`)
After every event (and on app launch) Flutter pushes the summary; the host
relays it via `updateApplicationContext`. Shape:
```json
{
  "nextFeedAt": "2026-06-29T15:22:00Z",   // ISO-8601, may be null
  "feedsToday": 5,
  "totalMlToday": 620,
  "sleepMinutesToday": 180,
  "diapersToday": 4,
  "scheduledMeds": ["Panado", "Vitamin D"]
}
```
The watch reads `applicationContext` to populate its home screen + complication.

## Manual Xcode steps (do these on the Mac)

1. The watch app must be a **target inside this Xcode workspace**
   (`ios/Runner.xcworkspace`) to ship to the App Store. Add it via
   *File ▸ New ▸ Target ▸ watchOS ▸ App* (or move the code from the
   `tinytracker-watch-app` repo in as a target). The companion relationship is
   set automatically.
2. `WatchSessionManager.swift` and the `SceneDelegate` change are already in
   `ios/Runner`. No entitlement is needed — `WatchConnectivity` works without a
   special capability.
3. Build & run on a paired iPhone + Watch (or the paired simulators). Tapping a
   log on the watch should insert the row in Supabase and the watch summary
   should refresh.
