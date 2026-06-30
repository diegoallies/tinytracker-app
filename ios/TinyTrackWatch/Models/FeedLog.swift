import Foundation

/// A single feeding event. Mirrors the TinyTrack iPhone app's feed record.
/// `type` is kept as a raw String to match the phone's payload exactly
/// (see `FeedKind` for the typed UI helper).
struct FeedLog: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var type: String          // "bottle" | "breast_left" | "breast_right" | "solids"
    var amountMl: Int?        // nil for breast / solids where volume is not measured
    var loggedAt: Date

    init(id: String = UUID().uuidString, type: String, amountMl: Int? = nil, loggedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.amountMl = amountMl
        self.loggedAt = loggedAt
    }
}

/// Typed convenience over `FeedLog.type` for the UI (label + SF Symbol).
enum FeedKind: String, CaseIterable, Identifiable {
    case bottle, breastLeft = "breast_left", breastRight = "breast_right", solids

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bottle:      return "Bottle"
        case .breastLeft:  return "Breast (L)"
        case .breastRight: return "Breast (R)"
        case .solids:      return "Solids"
        }
    }

    var symbol: String {
        switch self {
        case .bottle:                       return "waterbottle.fill"
        case .breastLeft, .breastRight:     return "drop.fill"
        case .solids:                       return "fork.knife"
        }
    }

    /// Whether an amount (ml) makes sense for this feed kind.
    var usesAmount: Bool { self == .bottle }
}
