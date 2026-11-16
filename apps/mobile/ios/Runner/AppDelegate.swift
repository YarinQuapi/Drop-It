import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // HealthKit background delivery relaunches the app in the background; re-arm observers first.
    HealthSync.shared.resumeIfEnabled()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // A notification arriving while the app is open gets a small tap from the haptic engine.
  // (In the background, iOS plays the notification's own sound/vibration.)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(.success)
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    HealthSync.shared.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
