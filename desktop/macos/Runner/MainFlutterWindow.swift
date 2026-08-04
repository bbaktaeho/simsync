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

    // Where should the tray popover appear? Computed natively — see
    // TrayAnchorChannel below and MenuBarManager._popoverAnchor (Dart).
    TrayAnchorChannel.register(flutterViewController.engine.binaryMessenger)

    // The menu bar popover runs in a desktop_multi_window sub-window. That
    // sub-window is a plain titled NSWindow, and that class is why every
    // previous full-screen attempt failed: `.nonactivatingPanel` is honored
    // only by NSPanel (inserting it into an NSWindow's style mask is a no-op),
    // and a titled plain NSWindow is not allowed to join another app's
    // full-screen Space even with `.fullScreenAuxiliary`. So re-host the
    // Flutter content inside a real non-activating NSPanel we own.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      PopoverPanel.adopt(controller)
    }

    super.awakeFromNib()
  }
}

/// Moves the popover sub-window's Flutter content into a floating,
/// non-activating NSPanel and bridges show / hide / outside-click dismissal to
/// Dart over the `simsync/popover` method channel.
///
/// Why native: window_manager's `show()` calls `NSApp.activate`, which brings
/// our app forward and switches away from any other app's full-screen Space. A
/// non-activating panel shown via `orderFrontRegardless()` floats over the
/// current Space (full-screen included) without activating the app, and clicks
/// inside it never activate the app either.
enum PopoverPanel {
  // Keep the per-window bridges alive for the process lifetime.
  private static var bridges: [PopoverBridge] = []

  // NOTE: this runs for EVERY desktop_multi_window sub-window. The popover is
  // the app's only sub-window today; if another kind is ever added, gate the
  // adoption (e.g. by launch argument) so it doesn't also become a panel.
  static func adopt(_ controller: FlutterViewController) {
    guard let pluginWindow = controller.view.window else { return }

    let panel = NonActivatingPanel(
      contentRect: pluginWindow.frame,
      // .titled keeps the standard rounded-corner window shape (the title bar
      // itself is hidden below). .closable/.miniaturizable make AppKit create
      // the standard title-bar buttons — window_manager's titlebar helpers
      // force-unwrap the close button's view hierarchy, so it must exist even
      // though every button is hidden right below.
      styleMask: [
        .titled, .closable, .miniaturizable, .fullSizeContentView,
        .nonactivatingPanel,
      ],
      backing: .buffered,
      defer: false)
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.isMovable = false
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    // Above normal window levels so nothing on the full-screen Space covers it.
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

    // Re-host: window_manager targets the Flutter view's window, so after this
    // move its setSize/setPosition calls operate on the panel. The plugin's
    // original window was created hidden (hiddenAtLaunch) and nothing ever
    // shows it; it just keeps the plugin's window bookkeeping alive.
    pluginWindow.contentViewController = nil
    panel.contentViewController = controller

    let channel = FlutterMethodChannel(
      name: "simsync/popover",
      binaryMessenger: controller.engine.binaryMessenger)
    let bridge = PopoverBridge(window: panel, channel: channel)
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
    bridges.append(bridge)
  }
}

/// Main-engine channel answering "where should the tray popover appear?".
///
/// Why native: the Dart side has no trustworthy source for this on
/// multi-monitor setups. tray_manager's getBounds flips y against
/// NSScreen.main (the key window's screen — it drifts with focus), and
/// screen_retriever's cursor point flips against yet another reference, so
/// with a second monitor or after a resolution change the popover used to
/// land on the wrong display or at the bottom of the screen. Here the
/// clicked display is identified from the live pointer location and the
/// anchor is derived from that display's own metrics (PopoverAnchor.swift),
/// in the primary-anchored top-left space window_manager's setPosition
/// expects — so the round-trip is exact by construction.
enum TrayAnchorChannel {
  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "simsync/tray", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "popoverAnchor" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let screens = NSScreen.screens.map {
        ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
      }
      guard !screens.isEmpty else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any]
      let iconRight = (args?["iconRight"] as? NSNumber)
        .map { CGFloat(truncating: $0) }
      let width = CGFloat(truncating: (args?["width"] as? NSNumber) ?? 332)
      let anchor = PopoverAnchor.compute(
        mouse: NSEvent.mouseLocation,
        screens: screens,
        iconRight: iconRight,
        width: width)
      result(["x": anchor.x, "y": anchor.y])
    }
  }
}

/// NSPanel that can take key status (so the popover's editor receives
/// keystrokes) without ever becoming the app's main window; combined with
/// `.nonactivatingPanel` it never activates the app.
final class NonActivatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class PopoverBridge {
  // Strong on purpose: this bridge is the panel's only owner. The panel is not
  // in the plugin's window bookkeeping (that still tracks the original hidden
  // window) and a never-shown NSWindow with no strong owner is deallocated —
  // taking the FlutterViewController and its engine down with it.
  private let window: NSWindow
  private let channel: FlutterMethodChannel
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?

  init(window: NSWindow, channel: FlutterMethodChannel) {
    self.window = window
    self.channel = channel
  }

  func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "orderFront":
      // Show above everything on the current Space without activating the app.
      window.orderFrontRegardless()
      window.makeKey()
      installOutsideClickMonitors()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Dismiss on the first click landing outside the panel — in another app
  /// (global monitor: only sees events NOT delivered to us) or in one of our
  /// own windows, e.g. the main window (local monitor: sees our events before
  /// dispatch; clicks inside the panel itself pass through untouched). A tray
  /// click also dismisses here first; the tray handler then re-shows, which
  /// keeps the icon's "open" gesture working.
  private func installOutsideClickMonitors() {
    removeOutsideClickMonitors()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      self?.hide()
    }
    localClickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      if let self, event.window !== self.window {
        self.hide()
      }
      return event
    }
  }

  private func removeOutsideClickMonitors() {
    if let monitor = outsideClickMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
    if let monitor = localClickMonitor {
      NSEvent.removeMonitor(monitor)
      localClickMonitor = nil
    }
  }

  private func hide() {
    removeOutsideClickMonitors()
    window.orderOut(nil)
    // Tell Dart so it can flush any in-flight editor edits and reset state.
    channel.invokeMethod("dismissed", arguments: nil)
  }
}
