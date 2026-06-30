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
        // The phone (Dart `toIso8601String()`) always emits fractional seconds and
        // a `Z`, e.g. "2026-06-29T15:22:00.000Z" or with microseconds
        // "…00.123456Z". The default `.iso8601` strategy uses only
        // `[.withInternetDateTime]` (NO fractional seconds) and FAILS to parse
        // those — and because JSONDecoder fails the whole array on one bad date,
        // every feed/diaper/sleep log came back empty. Parse robustly instead.
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = SharedConfig.parseISO8601(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Unparseable ISO-8601 date: \(raw)"))
            }
            return date
        }
        return d
    }()

    /// Tolerant ISO-8601 parser: tries fractional seconds, then plain, then
    /// strips any fractional component (handles 1–9 digit microseconds) and
    /// retries. Covers every shape Dart's `toIso8601String()` can emit.
    static func parseISO8601(_ string: String) -> Date? {
        if let d = isoFractional.date(from: string) { return d }
        if let d = iso8601.date(from: string) { return d }
        let stripped = string.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return iso8601.date(from: stripped)
    }

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
