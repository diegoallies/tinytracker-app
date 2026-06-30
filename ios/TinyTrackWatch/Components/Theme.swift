import SwiftUI

/// Soft, glanceable baby-app palette. One accent colour per category.
enum Theme {
    static let feed     = Color(red: 0.98, green: 0.64, blue: 0.40)   // warm peach
    static let diaper   = Color(red: 0.34, green: 0.78, blue: 0.62)   // mint
    static let sleep    = Color(red: 0.52, green: 0.56, blue: 0.92)   // soft indigo
    static let medicine = Color(red: 0.93, green: 0.49, blue: 0.66)   // soft pink
    static let today    = Color(red: 0.40, green: 0.74, blue: 0.95)   // sky blue
}

extension Date {
    /// "14:32" style short time, used across the glanceable screens.
    var shortTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: self)
    }
}
