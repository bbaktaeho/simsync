import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
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

  // MARK: - Daily reminders (see ReminderChannel in MainFlutterWindow.swift)

  // The app is menu bar resident, so it is "running" whenever a reminder
  // fires; without this the banner would be suppressed while it is frontmost.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  // Both the "SimSync 열기" action button and a click on the banner body land
  // here: bring the (possibly hidden-to-tray) main window forward.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    completionHandler()
  }
}
