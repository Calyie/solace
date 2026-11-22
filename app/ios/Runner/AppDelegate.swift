import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    SwitcherCover.start() // the native app-switcher cover (SceneDelegate.swift; round 9 review, 9A-07)
    NoNetworkProtocol.install() // AIR-3: no web request leaves the app (below)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Security review 2026-11-14 (F-03): the encrypted store (Application Support) and the model, voice and safety
  // files (Documents) stay on this iPhone: never in an iCloud or computer backup, which could be restored elsewhere.
  private func excludeAppDataFromBackup() {
    for dir in [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory] {
      guard var url = FileManager.default.urls(for: dir, in: .userDomainMask).first else { continue }
      try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
  }

  // Security review 2026-11-14 (F-10): third-party keyboards can send what is typed to their makers; only the
  // system keyboard is allowed in the app.
  override func application(
    _ application: UIApplication,
    shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
  ) -> Bool {
    return extensionPointIdentifier != .keyboard
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // the screen stays on while the quiet timer or the sleep wind-down runs (core/screen_awake.dart, 2026-11-14):
    // a locked iPhone pauses the app, so a bell would wait and the wind-down would stop
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SolaceScreen") {
      // the device's storage, so Solace's own room is a small share of it (core/storage.dart, 2026-11-14)
      FlutterMethodChannel(name: "solace/storage", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
        guard call.method == "space" else { result(FlutterMethodNotImplemented); return }
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        // "Important usage" counts the space the system would free for the person, but it reads 0 on some Macs (a
        // session with no one at the screen, some volumes) while the plain free space is large; Solace then refused
        // every import as "not enough free space" (the user journey, 2026-11-16). The larger of the two is used.
        let important = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values?.volumeAvailableCapacity ?? 0)
        if let total = values?.volumeTotalCapacity, total > 0 {
          result(["total": Int64(total), "free": max(important, plain)])
        } else {
          result(nil)
        }
      }
      // Copies use Flutter's own clipboard, as in any other app (owner, 2026-11-19); until then they were kept on this
      // iPhone only (round 8, A-11)
      FlutterMethodChannel(name: "solace/screen", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
        if call.method == "setKeepAwake" {
          UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

// AIR-3 (owner, 2026-11-16): the iPhone gives an ordinary app no switch that blocks the network for it, so Solace
// guards itself. Registered at launch, this claims every http, https, ws, wss and ftp request that reaches Apple's URL
// loading system (the shared session, NSURLConnection, and every session whose configuration comes from
// URLSessionConfiguration.default or .ephemeral), and fails it at once as "not connected to the internet"
// (NSURLErrorNotConnectedToInternet), before any connection is made. Public API only. Solace's own code makes no such
// request; this stops one from anything inside it. The Dart side has its own guards (lib/core/network_guard.dart).
final class NoNetworkProtocol: URLProtocol {
  private static let schemes: Set<String> = ["http", "https", "ws", "wss", "ftp"]

  /// AIR-3: registers the guard for the shared session and NSURLConnection, and puts it first in every configuration
  /// made from URLSessionConfiguration.default or .ephemeral. A session made with its own configuration never asks
  /// the registered classes (round 10 device check: those sessions still reached a loopback port), so the two class
  /// methods that hand out configurations are wrapped once, at launch, through the Objective-C runtime.
  static func install() {
    _ = URLProtocol.registerClass(NoNetworkProtocol.self)
    _ = configurationsGuarded
  }

  private static let configurationsGuarded: Void = {
    let configurationClass: AnyClass = URLSessionConfiguration.self
    for name in ["defaultSessionConfiguration", "ephemeralSessionConfiguration"] {
      let selector = NSSelectorFromString(name)
      guard let method = class_getClassMethod(configurationClass, selector) else { continue }
      typealias Maker = @convention(c) (AnyObject, Selector) -> URLSessionConfiguration
      let original = unsafeBitCast(method_getImplementation(method), to: Maker.self)
      let guarded: @convention(block) (AnyObject) -> URLSessionConfiguration = { receiver in
        let configuration = original(receiver, selector)
        let others = (configuration.protocolClasses ?? []).filter { ObjectIdentifier($0) != ObjectIdentifier(NoNetworkProtocol.self) }
        configuration.protocolClasses = [NoNetworkProtocol.self] + others
        return configuration
      }
      method_setImplementation(method, imp_implementationWithBlock(guarded))
    }
  }()

  override class func canInit(with request: URLRequest) -> Bool {
    guard let scheme = request.url?.scheme?.lowercased() else { return false }
    return schemes.contains(scheme)
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }

  override func stopLoading() {}
}
