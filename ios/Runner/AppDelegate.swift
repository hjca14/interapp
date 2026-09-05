import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var bleProvisioningBridge: EspressifBleProvisioningBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceTimezonePlugin")!
    FlutterMethodChannel(
      name: "interapp/device_timezone",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler { call, result in
      if call.method == "getIdentifier" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    bleProvisioningBridge = EspressifBleProvisioningBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    bleProvisioningBridge?.dispose()
    super.applicationWillTerminate(application)
  }
}
