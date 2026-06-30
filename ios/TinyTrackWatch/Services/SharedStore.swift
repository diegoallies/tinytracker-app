import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Persists the latest `WatchSummary` into the shared App Group so the watch-face
/// complication can read it. Written by the app, read by the complication.
enum SharedStore {

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedConfig.appGroup) ?? .standard
    }

    /// Save the latest summary and ask WidgetKit to refresh the complication.
    static func save(_ summary: WatchSummary) {
        if let data = try? SharedConfig.jsonEncoder.encode(summary) {
            defaults.set(data, forKey: SharedConfig.summaryKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Read the latest summary the app last stored (used by the complication).
    static func load() -> WatchSummary? {
        guard let data = defaults.data(forKey: SharedConfig.summaryKey) else { return nil }
        return try? SharedConfig.jsonDecoder.decode(WatchSummary.self, from: data)
    }
}
