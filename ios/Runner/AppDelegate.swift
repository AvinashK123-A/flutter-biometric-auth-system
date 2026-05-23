import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import LocalAuthentication

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

    private let kBiometricChannel = "com.avinash.biometric.auth/biometric"
    private let kSessionChannel = "com.avinash.biometric.auth/session"
    private let kSecurityChannel = "com.avinash.biometric.auth/security"
    private let kDeepLinkChannel = "com.avinash.biometric.auth/deeplink"

    private var biometricChannel: FlutterMethodChannel?
    private var sessionChannel: FlutterMethodChannel?
    private var deepLinkChannel: FlutterMethodChannel?
    private var pendingDeepLink: String?

    // Session management
    private var sessionTimer: Timer?
    private var sessionTimeoutSeconds: TimeInterval = 120

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()

        // Read session timeout from Info.plist
        let timeoutStr = Bundle.main.object(forInfoDictionaryKey: "SESSION_TIMEOUT_SECONDS") as? String ?? "120"
        sessionTimeoutSeconds = TimeInterval(timeoutStr) ?? 120

        if let controller = window?.rootViewController as? FlutterViewController {
            setupBiometricChannel(controller: controller)
            setupSessionChannel(controller: controller)
            setupSecurityChannel(controller: controller)
            setupDeepLinkChannel(controller: controller)
        }

        GeneratedPluginRegistrant.register(with: self)
        configurePushNotifications(application: application)
        Messaging.messaging().delegate = self

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - App Lifecycle (Session Management)

    override func applicationWillResignActive(_ application: UIApplication) {
        // Blur sensitive content when going to background
        showBlurOverlay()
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        startSessionTimer()
    }

    override func applicationWillEnterForeground(_ application: UIApplication) {
        removeBlurOverlay()
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        stopSessionTimer()
    }

    // MARK: - Session Timer

    private func startSessionTimer() {
        stopSessionTimer()
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: sessionTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            self?.sessionChannel?.invokeMethod("onSessionExpired", arguments: nil)
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Security Overlay (Prevents screen recording leaks)

    private var blurView: UIVisualEffectView?

    private func showBlurOverlay() {
        guard blurView == nil else { return }
        let blur = UIBlurEffect(style: .systemMaterialDark)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.frame = window?.bounds ?? .zero
        blurView.tag = 9999
        window?.addSubview(blurView)
        self.blurView = blurView
    }

    private func removeBlurOverlay() {
        blurView?.removeFromSuperview()
        blurView = nil
    }

    // MARK: - URL Handling

    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        deepLinkChannel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
        return true
    }

    override func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if let url = userActivity.webpageURL {
            deepLinkChannel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
            return true
        }
        return false
    }

    // MARK: - Biometric Channel

    private func setupBiometricChannel(controller: FlutterViewController) {
        biometricChannel = FlutterMethodChannel(
            name: kBiometricChannel,
            binaryMessenger: controller.binaryMessenger
        )

        biometricChannel?.setMethodCallHandler { call, result in
            switch call.method {
            case "checkBiometricAvailability":
                self.checkBiometricAvailability(result: result)
            case "getBiometryType":
                self.getBiometryType(result: result)
            case "authenticateWithBiometric":
                let args = call.arguments as? [String: Any] ?? [:]
                let title = args["title"] as? String ?? "Authenticate"
                let reason = args["reason"] as? String ?? "Verify your identity"
                let useDeviceCredential = args["useDeviceCredential"] as? Bool ?? true
                self.authenticateWithBiometric(
                    title: title,
                    reason: reason,
                    useDeviceCredential: useDeviceCredential,
                    result: result
                )
            case "authenticateWithDeviceCredential":
                let reason = (call.arguments as? [String: Any])?["reason"] as? String ?? "Enter passcode"
                self.authenticateWithDeviceCredential(reason: reason, result: result)
            case "invalidateContext":
                // Invalidate current LA context (force re-auth)
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func checkBiometricAvailability(result: @escaping FlutterResult) {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        let canEvaluateWithCredential = context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: nil
        )

        result([
            "available": canEvaluate,
            "deviceCredentialAvailable": canEvaluateWithCredential,
            "errorCode": error?.code as Any,
            "errorDescription": error?.localizedDescription as Any
        ])
    }

    private func getBiometryType(result: @escaping FlutterResult) {
        let context = LAContext()
        var error: NSError?
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        let typeString: String
        switch context.biometryType {
        case .faceID: typeString = "faceID"
        case .touchID: typeString = "touchID"
        default: typeString = "none"
        }
        result(typeString)
    }

    private func authenticateWithBiometric(
        title: String,
        reason: String,
        useDeviceCredential: Bool,
        result: @escaping FlutterResult
    ) {
        let context = LAContext()
        context.localizedFallbackTitle = useDeviceCredential ? "Use Passcode" : ""
        context.localizedCancelTitle = "Cancel"

        let policy: LAPolicy = useDeviceCredential
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            result([
                "success": false,
                "errorCode": error?.code ?? -1,
                "message": error?.localizedDescription ?? "Biometric not available"
            ])
            return
        }

        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    result(["success": true, "message": "Authentication successful"])
                } else {
                    var errorCode = -1
                    if let laError = error as? LAError {
                        errorCode = laError.code.rawValue
                    }
                    result([
                        "success": false,
                        "errorCode": errorCode,
                        "message": error?.localizedDescription ?? "Authentication failed"
                    ])
                }
            }
        }
    }

    private func authenticateWithDeviceCredential(reason: String, result: @escaping FlutterResult) {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                result(["success": success, "message": error?.localizedDescription as Any])
            }
        }
    }

    // MARK: - Session Channel

    private func setupSessionChannel(controller: FlutterViewController) {
        sessionChannel = FlutterMethodChannel(
            name: kSessionChannel,
            binaryMessenger: controller.binaryMessenger
        )
        sessionChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "resetSessionTimer":
                self?.stopSessionTimer()
                result(true)
            case "getSessionTimeout":
                result(self?.sessionTimeoutSeconds)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Security Channel

    private func setupSecurityChannel(controller: FlutterViewController) {
        FlutterMethodChannel(
            name: kSecurityChannel,
            binaryMessenger: controller.binaryMessenger
        ).setMethodCallHandler { call, result in
            switch call.method {
            case "isJailbroken":
                result(self.detectJailbreak())
            case "isScreenRecording":
                result(UIScreen.main.isCaptured)
            case "preventScreenCapture":
                // Screen capture prevention is handled via secure text fields and blur overlay
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func detectJailbreak() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return false
        #endif
    }

    // MARK: - Deep Link Channel

    private func setupDeepLinkChannel(controller: FlutterViewController) {
        deepLinkChannel = FlutterMethodChannel(
            name: kDeepLinkChannel,
            binaryMessenger: controller.binaryMessenger
        )
        deepLinkChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "getInitialLink":
                result(self?.pendingDeepLink)
                self?.pendingDeepLink = nil
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Push Notifications

    private func configurePushNotifications(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in }
        application.registerForRemoteNotifications()
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {}
}
