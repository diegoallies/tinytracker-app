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

    init(nextFeedAt: Date? = nil,
         feedsToday: Int = 0,
         totalMlToday: Int = 0,
         sleepMinutesToday: Int = 0,
         diapersToday: Int = 0) {
        self.nextFeedAt = nextFeedAt
        self.feedsToday = feedsToday
        self.totalMlToday = totalMlToday
        self.sleepMinutesToday = sleepMinutesToday
        self.diapersToday = diapersToday
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
        diapersToday: 4
    )
}
