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

    // Register plugins into every menu bar popover sub-window engine too, so
    // window_manager / path_provider / etc. work inside the popover window.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      // Let the popover appear over other apps' full-screen Spaces (not only the
      // desktop). Set at creation so it's on all Spaces before it's first shown.
      if let window = controller.view.window {
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.stationary)
      }
    }

    super.awakeFromNib()
  }
}
