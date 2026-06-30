import Foundation

/// Snapshot of "today" that the iPhone pushes to the watch via `applicationContext`.
/// Decoded directly from the bridge's FLAT context shape:
///
/// ```json
/// { "nextFeedAt": "2026-06-29T15:22:00Z", "feedsToday": 5, "totalMlToday": 620,
///   "sleepMinutesToday": 180, "diapersToday": 4, "scheduledMeds": ["Panado","Vitamin D"] }
/// ```
///
/// (`scheduledMeds` is handled separately by `ConnectivityService`; the decoder ignores it here.)
struct WatchSummary: Codable, Hashable {
    var nextFeedAt: Date?
    var feedsToday: Int
    var totalMlToday: Int
    var sleepMinutesToday: Int
    var diapersToday: Int
    /// Optional baby profile, sent by the phone so the watch can show an avatar.
    var babyName: String?
    var babyPhotoUrl: String?
    /// When the baby's CURRENT sleep started (nil when awake). Pushed by the
    /// phone as the single source of truth so the watch carries the live timer
    /// and never starts a second session. Optional keeps decoding safe when the
    /// key is absent; `isSleeping` is derived from it.
    var sleepStartedAt: Date?

    init(nextFeedAt: Date? = nil,
         feedsToday: Int = 0,
         totalMlToday: Int = 0,
         sleepMinutesToday: Int = 0,
         diapersToday: Int = 0,
         babyName: String? = nil,
         babyPhotoUrl: String? = nil,
         sleepStartedAt: Date? = nil) {
        self.nextFeedAt = nextFeedAt
        self.feedsToday = feedsToday
        self.totalMlToday = totalMlToday
        self.sleepMinutesToday = sleepMinutesToday
        self.diapersToday = diapersToday
        self.babyName = babyName
        self.babyPhotoUrl = babyPhotoUrl
        self.sleepStartedAt = sleepStartedAt
    }

    /// True while a sleep session is running on the phone.
    var isSleeping: Bool { sleepStartedAt != nil }

    /// 1–2 letter monogram for the avatar fallback, e.g. "Mia" → "M".
    var babyInitials: String {
        guard let name = babyName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "" }
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Whole minutes until the next feed (nil if unknown / in the past).
    var minutesUntilNextFeed: Int? {
        guard let next = nextFeedAt else { return nil }
        let secs = next.timeIntervalSinceNow
        guard secs > 0 else { return 0 }
        return Int((secs / 60).rounded())
    }

    /// Short glanceable string, e.g. "in 42m" / "now" / "—".
    var nextFeedShort: String {
        guard let mins = minutesUntilNextFeed else { return "—" }
        if mins <= 0 { return "now" }
        if mins < 60 { return "in \(mins)m" }
        return "in \(mins / 60)h \(mins % 60)m"
    }

    var sleepTodayShort: String {
        let h = sleepMinutesToday / 60, m = sleepMinutesToday % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Sample data so every screen and the complication preview render without a phone.
    static let sample = WatchSummary(
        nextFeedAt: Date().addingTimeInterval(42 * 60),
        feedsToday: 5,
        totalMlToday: 620,
        sleepMinutesToday: 180,
        diapersToday: 4,
        babyName: "Mia"
    )
}
