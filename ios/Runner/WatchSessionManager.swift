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
    guard WCSession.isSupported(),
          WCSession.default.activationState == .activated else { return }
    do {
      try WCSession.default.updateApplicationContext(dict)
    } catch {
      NSLog("WatchSessionManager: updateApplicationContext failed: \(error)")
    }
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
