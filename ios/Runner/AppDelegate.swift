import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var isBridgeSetup = false
    private var hostApi: NativeCaptureHostApiImpl?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // Register native bridge after super has initialized the window and rootViewController
        setupNativeBridgeIfPossible()

        return didFinish
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        // Ensure bridge is registered if launch occurred in background or UI was delayed
        setupNativeBridgeIfPossible()
    }

    /// Resolves the active FlutterViewController defensively across standard and container hierarchies
    private func resolveFlutterViewController() -> FlutterViewController? {
        if let flutterVC = window?.rootViewController as? FlutterViewController {
            return flutterVC
        }
        if let nav = window?.rootViewController as? UINavigationController,
           let flutterVC = nav.viewControllers.first(where: { $0 is FlutterViewController }) as? FlutterViewController {
            return flutterVC
        }
        if let tab = window?.rootViewController as? UITabBarController,
           let flutterVC = tab.viewControllers?.first(where: { $0 is FlutterViewController }) as? FlutterViewController {
            return flutterVC
        }
        return nil
    }

    /// Idempotently sets up the Pigeon NativeCaptureHostApi bridge
    private func setupNativeBridgeIfPossible() {
        guard !isBridgeSetup else { return }
        guard let controller = resolveFlutterViewController() else { return }

        let host = NativeCaptureHostApiImpl(controller: controller)
        NativeCaptureHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: host)
        self.hostApi = host
        self.isBridgeSetup = true
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        if let controller = resolveFlutterViewController() {
            NativeCaptureHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: nil)
        }
        self.hostApi = nil
        self.isBridgeSetup = false
        super.applicationWillTerminate(application)
    }
}
