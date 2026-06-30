import Flutter
import Foundation
import WatchConnectivity

/// Native half of the Apple Watch bridge.
///
/// - Receives one-tap log events from the watch over WatchConnectivity and
///   forwards them to Flutter via the `tinytrack/watch` MethodChannel
///   (`onWatchEvent`).
/// - Receives summary updates FROM Flutter (`updateWatchContext`) and ships
///   them to the watch via `updateApplicationContext` (drives the watch home
///   screen + complication).
///
/// `attach(messenger:)` is called from SceneDelegate once the Flutter engine's
/// binary messenger exists. Events that arrive before the channel is ready are
/// queued and flushed on attach.
final class WatchSessionManager: NSObject, WCSessionDelegate {
  static let shared = WatchSessionManager()

  private var channel: FlutterMethodChannel?
  private var pendingEvents: [[String: Any]] = []

  private override init() { super.init() }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "tinytrack/watch",
      binaryMessenger: messenger
    )
    self.channel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "updateWatchContext":
        if let dict = call.arguments as? [String: Any] {
          self?.sendContext(dict)
          result(true)
        } else {
          result(FlutterError(code: "bad_args", message: "expected a map", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Flush anything received before the channel was wired up.
    for event in pendingEvents {
      channel.invokeMethod("onWatchEvent", arguments: event)
    }
    pendingEvents.removeAll()

    activateSession()
  }

  private func activateSession() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  private func forward(_ message: [String: Any]) {
    if let channel = channel {
      DispatchQueue.main.async {
        channel.invokeMethod("onWatchEvent", arguments: message)
      }
    } else {
      pendingEvents.append(message)
    }
  }

  private func sendContext(_ dict: [String: Any]) {
    guard WCSession.isSupported() else {
      NSLog("WatchBridge[native]: WCSession unsupported"); return
    }
    guard WCSession.default.activationState == .activated else {
      NSLog("WatchBridge[native]: session not activated (state=\(WCSession.default.activationState.rawValue))")
      return
    }
    let clean = Self.plistSanitized(dict)
    do {
      try WCSession.default.updateApplicationContext(clean)
      NSLog("WatchBridge[native]: applicationContext SENT, keys=\(clean.keys.sorted()) "
        + "feedLog=\((clean["feedLog"] as? [Any])?.count ?? -1) "
        + "reachable=\(WCSession.default.isReachable)")
    } catch {
      NSLog("WatchBridge[native]: updateApplicationContext FAILED: \(error)")
    }
  }

  /// `updateApplicationContext` only accepts property-list types. Flutter encodes
  /// a Dart `null` as `NSNull`, which is NOT plist-compatible — a single null
  /// anywhere (e.g. `nextFeedAt`, `babyPhotoUrl`, a breast feed's `amountMl`)
  /// makes the call throw and drops the ENTIRE payload, so the watch shows
  /// nothing. Recursively remove nulls; the watch's Codable models already treat
  /// absent keys as `nil`.
  static func plistSanitized(_ dict: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in dict {
      if let clean = sanitize(value) { out[key] = clean }
    }
    return out
  }

  private static func sanitize(_ value: Any) -> Any? {
    if value is NSNull { return nil }
    if let dict = value as? [String: Any] { return plistSanitized(dict) }
    if let array = value as? [Any] { return array.compactMap { sanitize($0) } }
    return value
  }

  // MARK: - WCSessionDelegate

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    forward(message)
  }

  func session(_ session: WCSession,
               didReceiveMessage message: [String: Any],
               replyHandler: @escaping ([String: Any]) -> Void) {
    forward(message)
    replyHandler(["ok": true])
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    forward(userInfo)
  }

  func session(_ session: WCSession,
               activationDidCompleteWith activationState: WCSessionActivationState,
               error: Error?) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    // Reactivate so a switched paired watch keeps working.
    WCSession.default.activate()
  }
}
