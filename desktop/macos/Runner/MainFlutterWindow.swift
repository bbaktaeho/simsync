import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Be born at the app's default size so the window doesn't visibly resize
    // right after Flutter init (avoids a first-run resize flash).
    self.setContentSize(NSSize(width: 1120, height: 760))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The menu bar popover runs in a desktop_multi_window sub-window. Turn that
    // sub-window into a non-activating floating panel so it can appear over
    // other apps' full-screen Spaces (like a native menu bar popover) WITHOUT
    // activating our app — activating would switch away from the full-screen
    // Space, which is exactly why the plain window approach never showed there.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      PopoverPanel.configure(controller)
    }

    super.awakeFromNib()
  }
}

/// Configures the menu bar popover sub-window as a non-activating floating panel
/// and bridges show / hide / outside-click dismissal to Dart over the
/// `simsync/popover` method channel.
///
/// Why native: window_manager's `show()` calls `NSApp.activate`, which brings
/// our app forward and switches away from any other app's full-screen Space, so
/// the popover never appears over full-screen. A non-activating panel shown via
/// `orderFrontRegardless()` floats over the current Space (full-screen included)
/// without activating the app.
enum PopoverPanel {
  // Keep the per-window bridges alive for the process lifetime.
  private static var bridges: [PopoverBridge] = []

  static func configure(_ controller: FlutterViewController) {
    guard let window = controller.view.window else { return }

    // Non-activating: showing or clicking the popover never activates the app,
    // so we stay on the current (possibly full-screen) Space.
    window.styleMask.insert(.nonactivatingPanel)
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false

    let channel = FlutterMethodChannel(
      name: "simsync/popover",
      binaryMessenger: controller.engine.binaryMessenger)
    let bridge = PopoverBridge(window: window, channel: channel)
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
    bridges.append(bridge)
  }
}

final class PopoverBridge {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var outsideClickMonitor: Any?

  init(window: NSWindow, channel: FlutterMethodChannel) {
    self.window = window
    self.channel = channel
  }

  func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "orderFront":
      // Show above everything on the current Space without activating the app.
      window?.orderFrontRegardless()
      window?.makeKey()
      installOutsideClickMonitor()
      result(nil)
    case "hide":
      hide()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Dismiss on the first click landing in any OTHER app. Global monitors only
  /// see events not delivered to us, so clicks inside the popover (selecting a
  /// date, typing) never trigger it.
  private func installOutsideClickMonitor() {
    removeOutsideClickMonitor()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      self?.hide()
    }
  }

  private func removeOutsideClickMonitor() {
    if let monitor = outsideClickMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
  }

  private func hide() {
    removeOutsideClickMonitor()
    window?.orderOut(nil)
    // Tell Dart so it can flush any in-flight editor edits and reset state.
    channel.invokeMethod("dismissed", arguments: nil)
  }
}
