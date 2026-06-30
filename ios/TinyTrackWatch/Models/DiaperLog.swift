import Foundation

/// A diaper change. Mirrors the TinyTrack iPhone app's diaper record.
struct DiaperLog: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var type: String          // "wet" | "dirty" | "both"
    var loggedAt: Date

    init(id: String = UUID().uuidString, type: String, loggedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.loggedAt = loggedAt
    }
}

/// Typed convenience over `DiaperLog.type` for the UI.
enum DiaperKind: String, CaseIterable, Identifiable {
    case wet, dirty, both

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .wet:   return "drop.fill"
        case .dirty: return "smoke.fill"
        case .both:  return "exclamationmark.2"
        }
    }
}
