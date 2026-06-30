import Foundation

/// The set of actions the watch can send to the iPhone app.
/// The raw values are the wire-format `"action"` strings in every message.
enum WatchAction: String, Codable {
    case logFeed
    case logDiaper
    case sleepStart
    case sleepStop
    case logMed
}
