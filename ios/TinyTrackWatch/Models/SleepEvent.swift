import Foundation

/// A sleep start/stop marker. The phone reconstructs sessions from these events.
struct SleepEvent: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var action: String        // "start" | "stop"
    var at: Date

    init(id: String = UUID().uuidString, action: String, at: Date = Date()) {
        self.id = id
        self.action = action
        self.at = at
    }
}
