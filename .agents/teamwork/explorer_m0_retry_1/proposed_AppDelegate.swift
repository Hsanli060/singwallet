import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        if let controller = window?.rootViewController as? FlutterViewController {
            let hostApi = NativeCaptureHostApiImpl(controller: controller)
            NativeCaptureHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: hostApi)
        }
        GeneratedPluginRegistrant.register(with: self)
        return result
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        if let controller = window?.rootViewController as? FlutterViewController {
            NativeCaptureHostApiSetup.setUp(binaryMessenger: controller.binaryMessenger, api: nil)
        }
        super.applicationWillTerminate(application)
    }
}
