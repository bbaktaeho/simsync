import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // SimSync is a menu bar resident app: hiding/closing the window must NOT quit
    // the process. Only the tray "앱 종료" action terminates it explicitly.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // The main window hides to the menu bar instead of closing. When the app is
  // reopened (Dock click, or relaunching while already running), macOS calls
  // this — re-show the main window so it isn't stuck hidden.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    return true
  }
}
