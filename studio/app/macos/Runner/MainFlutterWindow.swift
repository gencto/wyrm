import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // No title bar of its own (docs/studio.md §7.1): the content runs under
    // a transparent one and the native close, minimize and zoom buttons
    // stay. Set here, before the first frame, so the window never shows a
    // title; `window_manager` asks for the same once Dart runs.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // An empty unified toolbar makes the title bar 52 pt high, which puts
    // the three buttons on the centre line of the app's own top bar
    // (52 to 56 high) with no frame arithmetic to redo on every resize.
    // Mouse events in that region still reach the Flutter view (it is the
    // hit view there and does not move the window), so the app's top bar
    // stays clickable and Dart starts the window drag (`WindowBar`).
    let toolbar = NSToolbar(identifier: "main")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unified
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
