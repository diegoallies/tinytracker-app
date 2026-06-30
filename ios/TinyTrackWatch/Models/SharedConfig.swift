import Foundation

/// Constants and codecs shared between the watch app and the complication extension.
/// Kept tiny and dependency-free so the whole bundle can move into a Flutter `ios/`
/// workspace later without dragging anything along.
enum SharedConfig {
    /// App Group used to hand the latest `WatchSummary` to the complication.
    /// NOTE: must be registered for your team for on-device builds (works as-is in the Simulator).
    static let appGroup = "group.com.diegoallies.TinyTrackWatch"

    /// UserDefaults key holding the JSON-encoded `WatchSummary`.
    static let summaryKey = "tinytrack.summary"

    /// ISO-8601 dates everywhere, matching the Flutter/iPhone side.
    static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
