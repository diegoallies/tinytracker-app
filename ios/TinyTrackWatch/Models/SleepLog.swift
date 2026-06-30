import Foundation

/// A completed sleep session, pushed by the phone for the Sleep page's
/// left-scroll history. (Distinct from `SleepEvent`, which is a start/stop marker
/// sent the other way.)
struct SleepLog: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var durationMinutes: Int?
    var startedAt: Date
    var endedAt: Date?

    init(id: String = UUID().uuidString,
         durationMinutes: Int? = nil,
         startedAt: Date = Date(),
         endedAt: Date? = nil) {
        self.id = id
        self.durationMinutes = durationMinutes
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var durationShort: String {
        let m = durationMinutes ?? 0
        let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
    }
}
