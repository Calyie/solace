import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Round 4 review (A-07): the encrypted store stays on this Mac, as on the iPhone (F-03). Its key is in the login
  // keychain, which Time Machine keeps; a backup holding both would open with the account password alone. The
  // transfer file is the way to move Solace's data to another device.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    excludeAppDataFromBackup()
    keepTextInsideTheApp()
    NoNetworkProtocol.install() // AIR-3: as on the iPhone, beside the sandbox's own block
    super.applicationWillFinishLaunching(notification)
  }

  // Round 9 review (9A-06): AppKit adds "Start Dictation…" and "Emoji & Symbols" to a menu titled Edit, and dictation
  // can send what is said to Apple (E-07). These two user defaults, set before the menu bar is first shown, keep AppKit
  // from adding them. The Services menu, which offers a text box's selection to other apps and services ("Search With
  // Google", "New Email With Selection"), is left out of the menu bar (ui/desktop.dart) and of MainMenu.xib. Writing
  // Tools (macOS 15) has no switch an app can reach for Flutter's text input without private hooks (docs/SECURITY.md
  // section 7).
  private func keepTextInsideTheApp() {
    UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
    UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
  }

  private func excludeAppDataFromBackup() {
    guard var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// AIR-3 (owner, 2026-11-16): the same guard as the iPhone's (ios/Runner/AppDelegate.swift). The Mac's App Sandbox,
// with no network entitlement, already blocks the network for Solace; this fails any http, https, ws, wss or ftp
// request that reaches Apple's URL loading system (the shared session, NSURLConnection, and every session whose
// configuration comes from URLSessionConfiguration.default or .ephemeral) before it gets that far.
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
