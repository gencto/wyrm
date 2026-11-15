import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Closing the window keeps Studio running in the Dock, as macOS apps do
  // (owner decision 2026-11-15): the session, the open screens and their
  // subscriptions stay. ⌘Q quits.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // A click on the Dock icon (or `open` of the running app) brings the
  // closed window back. The window was only ordered out: it is not released
  // when closed (`MainFlutterWindow`), so the Flutter view is the same one.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
