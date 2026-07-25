import Flutter
import UIKit

// Push is handled by firebase_messaging, which registers itself through the
// Flutter plugin registrar and hands FCM tokens to Dart — the old
// `tinytrack/push` MethodChannel and manual APNs token forwarding are gone.
//
// There is deliberately NO UNUserNotificationCenter delegate assignment here.
// FlutterAppDelegate conforms to FlutterAppLifeCycleProvider, which is exactly
// what lets firebase_messaging and flutter_local_notifications coexist:
// firebase_messaging detects that and defers to the plugin chain instead of
// seizing the delegate. Assigning it by hand would break the scheduled
// feeding/sleep/medication reminders.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
