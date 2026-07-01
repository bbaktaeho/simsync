import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Be born at the app's default size (matching MenuBarManager's app form) so
    // the window doesn't visibly resize right after Flutter/window_manager init.
    self.setContentSize(NSSize(width: 1120, height: 760))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
