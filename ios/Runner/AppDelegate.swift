import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications
import GoogleMaps  // ← ADD THIS

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure Firebase first
        FirebaseApp.configure()
        
        // Configure Google Maps from Info.plist
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String {
            GMSServices.provideAPIKey(apiKey)
            print("✅ Google Maps configured with API key")
        } else {
            print("❌ Google Maps API key not found in Info.plist")
        }
        
        // Firebase Messaging setup
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        Messaging.messaging().apnsToken = deviceToken
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("🏷 APNs device token: \(hex)")
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM registration token: \(fcmToken ?? "nil")")
    }
}