import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}

// Round 9 review, 9A-07: the app-switcher cover was drawn only by Flutter (ui/app_lock.dart, once the app is
// inactive), so the snapshot iOS keeps of the screen could show the conversation if that frame was late (a fast swipe
// home, a busy frame). Now a plain opaque view in the app's page colour also covers each window natively the moment
// the scene resigns active (UIScene.willDeactivateNotification, the notification of sceneWillResignActive, handled on
// the posting thread so the cover is there before the snapshot), and goes when it is active again
// (didActivateNotification, of sceneDidBecomeActive). Notifications rather than overriding FlutterSceneDelegate's own
// scene methods, so the engine's handling of them is untouched. "Hide in the app switcher" is kept in the encrypted
// store, which the native side cannot read, so this cover is always drawn (docs/SECURITY.md section 7). Started once
// from AppDelegate.swift.
enum SwitcherCover {
  private static let tag = 0x50_1ACE
  private static var started = false

  // the page colour of ui/theme.dart (light 0xF7F6F2, dark 0x0D1626), by the device's appearance
  private static let page = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x0D / 255.0, green: 0x16 / 255.0, blue: 0x26 / 255.0, alpha: 1)
      : UIColor(red: 0xF7 / 255.0, green: 0xF6 / 255.0, blue: 0xF2 / 255.0, alpha: 1)
  }

  static func start() {
    guard !started else { return }
    started = true
    let center = NotificationCenter.default
    _ = center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: nil) { note in
      guard let scene = note.object as? UIWindowScene else { return }
      for window in scene.windows where !window.subviews.contains(where: { $0.tag == SwitcherCover.tag }) {
        let cover = UIView(frame: window.bounds)
        cover.tag = SwitcherCover.tag
        cover.backgroundColor = SwitcherCover.page
        cover.isOpaque = true
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(cover)
      }
    }
    _ = center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: nil) { note in
      guard let scene = note.object as? UIWindowScene else { return }
      for window in scene.windows {
        for view in window.subviews where view.tag == SwitcherCover.tag {
          view.removeFromSuperview()
        }
      }
    }
  }
}
