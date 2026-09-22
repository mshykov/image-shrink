import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Where "Check for Updates" goes until there is an appcast to subscribe to.
    static let releases = URL(string: "https://github.com/mshykov/image-shrink/releases/latest")!

    private let model = AppModel()
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var settingsPopover: NSPopover?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        installServicesIfNeeded()
        let menuBar = MenuBarController(model: model) { [weak self] in self?.showWindow() }
        menuBar.install()
        self.menuBar = menuBar
        showWindow()
    }

    /// The window is the exception, not the product: closing it leaves the app in the menu
    /// bar rather than quitting, and drops the Dock icon while there is nothing to show.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    /// Finder Quick Action and "Open With" both land here.
    func application(_ application: NSApplication, open urls: [URL]) {
        Log.write("opened with \(urls.count) file(s)")
        model.add(urls: urls)
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingView(rootView: ContentView().environmentObject(model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Image Shrink"
            window.applyGlassChrome()
            window.contentView = hosting
            attachToolbar(to: window)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("main")
            window.delegate = self
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A downloaded app has no install script to run, so it puts its own Quick Actions in
    /// place — on the first launch, and again whenever it moves or updates.
    private func installServicesIfNeeded() {
        guard Services.needsInstall else { return }
        DispatchQueue.global(qos: .utility).async {
            guard Services.install() > 0 else { return }
            Services.restartFinder()
        }
    }

    @objc func reinstallServices(_ sender: Any?) {
        let installed = Services.install()
        Services.restartFinder()
        let alert = NSAlert()
        if installed > 0 {
            alert.messageText = "Finder actions installed"
            alert.informativeText = """
                \(installed) Quick Actions are in the right-click menu, under Quick Actions. \
                Finder was relaunched so it picks them up.
                """
        } else {
            alert.alertStyle = .warning
            alert.messageText = "No Finder actions to install"
            alert.informativeText = "This copy of the app was built without them."
        }
        alert.runModal()
    }

    @objc func removeServices(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Remove the Finder actions?"
        alert.informativeText = """
            The right-click entries and the shortcut go away. The app stays, and this menu \
            puts them back.
            """
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Services.uninstall()
        Services.restartFinder()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSWorkspace.shared.open(Self.releases)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: SettingsView())
            hosting.layoutSubtreeIfNeeded()
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Image Shrink Settings"
            window.contentView = hosting
            // The content decides the height; nothing here should ever need scrolling.
            window.setContentSize(hosting.fittingSize)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        model.add(urls: panel.urls)
        showWindow()
    }

    @objc func showHelp(_ sender: Any?) {
        guard let readme = Bundle.main.url(forResource: "README", withExtension: "md") else { return }
        NSWorkspace.shared.open(readme)
    }

    /// The two round buttons the design puts in the titlebar: add files, and settings.
    private func attachToolbar(to window: NSWindow) {
        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @objc func toggleSettingsPopover(_ sender: Any?) {
        // Anchor to the button that was actually clicked. `itemForItemIdentifier` runs more
        // than once — the customisation palette asks for items too — so a button stored at
        // creation time can be one that never entered the window, and the popover then hangs
        // off nothing, above the titlebar.
        let anchor = (sender as? NSView)
            ?? window?.toolbar?.items
                .first { $0.itemIdentifier == Self.settingsItem }?.view
        guard let anchor, anchor.window != nil else { return }
        if let popover = settingsPopover, popover.isShown {
            popover.performClose(sender)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = Self.sizedController(
            SettingsPopover().environmentObject(model), popover: popover)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        settingsPopover = popover
    }

    /// A SwiftUI popover has no size until it is laid out, and AppKit places the popover
    /// before that happens: it positions a zero-sized window and then, when the content
    /// grows, the window is pushed to the top of the screen, adrift from its button.
    /// Measuring first and handing over `contentSize` is what keeps it under the button.
    static func sizedController<Content: View>(_ content: Content,
                                               popover: NSPopover) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: content)
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        controller.preferredContentSize = size
        popover.contentSize = size
        return controller
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Image Shrink", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Reinstall Finder Actions", action: #selector(reinstallServices(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Remove Finder Actions…", action: #selector(removeServices(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Image Shrink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Image Shrink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Add Files…", action: #selector(openFiles(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Without an Edit menu the text fields lose cut/copy/paste and ⌘A.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Image Shrink Help", action: #selector(showHelp(_:)), keyEquivalent: "?")
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }
}


extension AppDelegate: NSToolbarDelegate {
    static let addItem = NSToolbarItem.Identifier("dev.shykov.imageshrink.add")
    static let settingsItem = NSToolbarItem.Identifier("dev.shykov.imageshrink.settings")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.addItem, Self.settingsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        // A real button as the item view, so the popover has something to point at.
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        button.bezelStyle = .texturedRounded
        button.target = self

        switch identifier {
        case Self.addItem:
            button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add images")
            button.action = #selector(openFiles(_:))
            item.label = "Add Images"
            item.toolTip = "Add images"
        case Self.settingsItem:
            button.image = NSImage(systemSymbolName: "slider.horizontal.3",
                                   accessibilityDescription: "Settings")
            button.action = #selector(toggleSettingsPopover(_:))
            item.label = "Settings"
            item.toolTip = "All settings"
        default:
            return nil
        }

        item.view = button
        return item
    }
}
