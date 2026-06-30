import Foundation
import Combine
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Singleton wrapper around `WCSession`, speaking the TinyTrack bridge's exact contract.
///
/// **Outbound** (`send(action:extra:)`): a `["action": ...]` dictionary delivered via
/// `sendMessage` when the phone is reachable, falling back to `transferUserInfo` when it is
/// not, so logs queue and deliver later (offline-safe). No keys are invented — only
/// `action`, the caller's `extra`, and an optional `loggedAt` (only if the caller supplies it;
/// omitting it means "now" on the phone side).
///
/// **Inbound**: the phone pushes a FLAT `applicationContext`; we decode `WatchSummary` from it
/// and pull `scheduledMeds` as a `[String]`. Both are `@Published` for live SwiftUI updates.
///
/// When `WatchConnectivity` is unavailable (previews) or no phone has connected, sample data is
/// seeded so the whole UI is testable in the Simulator.
final class ConnectivityService: NSObject, ObservableObject {

    static let shared = ConnectivityService()

    // MARK: Published state (drives the UI)
    @Published private(set) var summary: WatchSummary = .sample
    @Published private(set) var scheduledMeds: [String] = ["Panado", "Vitamin D"]
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var lastSendOK: Bool = true
    // Feat 1: previous days for the home left-scroll (newest first, includes today).
    @Published private(set) var daySummaries: [DaySummary] = []
    // Feat 2: recent per-type record logs for each page's left-scroll.
    @Published private(set) var feedLog: [FeedLog] = []
    @Published private(set) var diaperLog: [DiaperLog] = []
    @Published private(set) var sleepLog: [SleepLog] = []

    private override init() {
        super.init()
        SharedStore.save(summary)   // seed the complication
        #if targetEnvironment(simulator)
        seedSampleHistory()         // so the log pages are testable without a phone
        #endif
        activate()
    }

    #if targetEnvironment(simulator)
    /// Populate the history arrays with sample records so the Feed/Diaper/Sleep
    /// log pages and the home left-scroll render in the Simulator (no phone).
    /// Never compiled into device builds — real data comes from the phone.
    private func seedSampleHistory() {
        let now = Date()
        func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

        feedLog = [
            FeedLog(type: "bottle", amountMl: 150, loggedAt: ago(1)),
            FeedLog(type: "breast_left", amountMl: nil, loggedAt: ago(4)),
            FeedLog(type: "bottle", amountMl: 120, loggedAt: ago(7)),
            FeedLog(type: "solids", amountMl: nil, loggedAt: ago(26)),
        ]
        diaperLog = [
            DiaperLog(type: "wet", loggedAt: ago(2)),
            DiaperLog(type: "dirty", loggedAt: ago(5)),
            DiaperLog(type: "both", loggedAt: ago(28)),
        ]
        sleepLog = [
            SleepLog(durationMinutes: 95, startedAt: ago(3), endedAt: ago(1.4)),
            SleepLog(durationMinutes: 180, startedAt: ago(12), endedAt: ago(9)),
        ]
        daySummaries = [
            DaySummary(date: dayKey(now),       feeds: 5, totalMl: 620, sleepMinutes: 275, diapers: 4),
            DaySummary(date: dayKey(ago(24)),   feeds: 6, totalMl: 700, sleepMinutes: 300, diapers: 5),
            DaySummary(date: dayKey(ago(48)),   feeds: 4, totalMl: 540, sleepMinutes: 260, diapers: 3),
        ]
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    #endif

    // MARK: Activation

    private func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    // MARK: Sending

    /// Send an action to the phone. Returns immediately (the UI is optimistic).
    /// `extra` carries the action-specific keys (e.g. `["type": "bottle", "amountMl": 150]`).
    /// To stamp a specific time, pass `["loggedAt": ISO8601 string]` in `extra`; otherwise it is
    /// omitted and the phone treats the log as "now".
    func send(action: WatchAction, extra: [String: Any] = [:]) {
        var message = extra
        message["action"] = action.rawValue

        #if canImport(WatchConnectivity)
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                self?.queue(message)        // became unreachable mid-flight → don't lose it
            }
            DispatchQueue.main.async { self.lastSendOK = true }
        } else {
            queue(message)
        }
        #else
        DispatchQueue.main.async { self.lastSendOK = true }   // previews: pretend success
        #endif
    }

    /// Offline / unreachable fallback — guaranteed delivery once the phone reconnects.
    private func queue(_ message: [String: Any]) {
        #if canImport(WatchConnectivity)
        WCSession.default.transferUserInfo(message)
        #endif
        DispatchQueue.main.async { self.lastSendOK = true }
    }

    // MARK: Applying inbound context (FLAT shape)

    private func apply(context: [String: Any]) {
        guard !context.isEmpty else { return }

        // Summary decodes straight from the flat context (ignores `scheduledMeds`).
        if let data = try? JSONSerialization.data(withJSONObject: context),
           let s = try? SharedConfig.jsonDecoder.decode(WatchSummary.self, from: data) {
            DispatchQueue.main.async {
                self.summary = s
                SharedStore.save(s)
            }
        }

        // Scheduled meds are a plain array of names.
        if let meds = context["scheduledMeds"] as? [String] {
            DispatchQueue.main.async { self.scheduledMeds = meds }
        }

        // History arrays (Feats 1 & 2). Each is a JSON array under its own key.
        if let days: [DaySummary] = decodeArray(context["dailySummaries"]) {
            DispatchQueue.main.async { self.daySummaries = days }
        }
        if let feeds: [FeedLog] = decodeArray(context["feedLog"]) {
            DispatchQueue.main.async { self.feedLog = feeds }
        }
        if let diapers: [DiaperLog] = decodeArray(context["diaperLog"]) {
            DispatchQueue.main.async { self.diaperLog = diapers }
        }
        if let sleeps: [SleepLog] = decodeArray(context["sleepLog"]) {
            DispatchQueue.main.async { self.sleepLog = sleeps }
        }
    }

    /// Decode a `[T]` from a raw JSON-array value pulled out of the context.
    private func decodeArray<T: Decodable>(_ raw: Any?) -> [T]? {
        guard let raw,
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? SharedConfig.jsonDecoder.decode([T].self, from: data)
        else { return nil }
        return decoded
    }
}

// MARK: - WCSessionDelegate

#if canImport(WatchConnectivity)
extension ConnectivityService: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
        apply(context: session.receivedApplicationContext)   // pick up the last context
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(context: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(context: message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        apply(context: userInfo)
    }
}
#endif
