import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // The FlutterViewController (and its binary messenger) exists after super
    // sets up the scene. Wire the Apple Watch bridge to it.
    if let controller = window?.rootViewController as? FlutterViewController {
      WatchSessionManager.shared.attach(messenger: controller.binaryMessenger)
    }
  }
}
