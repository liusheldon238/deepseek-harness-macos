import AppKit
import DeepSeekHarnessCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var shellViewController: ShellViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
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

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "DeepSeek Harness")
        appMenu.addItem(NSMenuItem(title: "退出 DeepSeek Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        for command in DesktopEditCommand.allCases {
            if command == .cut || command == .selectAll { editMenu.addItem(.separator()) }
            let item = NSMenuItem(title: command.title, action: selector(for: command), keyEquivalent: command.keyEquivalent)
            item.target = nil
            editMenu.addItem(item)
        }
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    private func selector(for command: DesktopEditCommand) -> Selector {
        switch command {
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        }
    }
}
