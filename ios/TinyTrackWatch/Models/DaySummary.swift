import Foundation

/// One day's totals, pushed by the phone for the home page's left-scroll history.
/// `date` is the phone's LOCAL day key ("YYYY-MM-DD"). Newest day first.
struct DaySummary: Codable, Identifiable, Hashable {
    var date: String
    var feeds: Int
    var totalMl: Int
    var sleepMinutes: Int
    var diapers: Int

    var id: String { date }

    var sleepShort: String {
        let h = sleepMinutes / 60, m = sleepMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// "Today" / "Yesterday" / "Mon, Jun 24".
    var label: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let d = parser.date(from: date) else { return date }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
    }
}
