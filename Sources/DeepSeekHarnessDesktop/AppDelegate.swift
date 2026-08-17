import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var shellViewController: ShellViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewController = ShellViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "DeepSeek Harness Desktop"
        window.contentViewController = viewController
        // Setting the controller can cause AppKit to fit a view with no
        // intrinsic size to its title bar. Re-assert the intended shell size
        // after the content view has been installed.
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.minSize = NSSize(width: 900, height: 600)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.shellViewController = viewController
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        shellViewController?.stopBackend()
    }
}
