import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private lazy var viewModel = CalendarViewModel()
    private let keyboard = KeyboardCommands()
    private let hotKey = HotKey()
    private var dayCheckTimer: Timer?
    private var currentIconDay = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureMenu()
        viewModel.syncLaunchAtLoginStatus()
        startDayRolloverTimer()
        observePopoverClose()
        registerHotKey()
    }

    /// ⌃⌥C toggles the panel from anywhere. If the combination is already taken
    /// CalBar carries on without it — a menu bar app losing its shortcut is not
    /// worth refusing to launch over.
    private func registerHotKey() {
        let ok = hotKey.register { [weak self] in
            guard let self else { return }
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else {
                self.showPopover()
            }
        }
        if ok {
            NSLog("CalBar: ⌃⌥C registered")
        } else {
            NSLog("CalBar: could not register ⌃⌥C — another app already owns it")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        // Quitting counts as closing the panel: stamp the grace window now.
        viewModel.saveContext()
    }

    /// The grace window is measured from the moment the panel closes, so the
    /// browsed month is never disturbed while the panel is open.
    private func observePopoverClose() {
        NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.saveContext()
            // Leaving the monitor installed would intercept keys for the rest
            // of the app's lifetime.
            self?.keyboard.remove()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.toolTip = "\(AppInfo.longDisplay) — Menu Bar Calendar"
        refreshStatusIcon()
    }

    func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        let day = Calendar.current.component(.day, from: Date())
        guard day != currentIconDay else { return }
        currentIconDay = day
        button.image = StatusBarIcon.image(dayNumber: day)
    }

    private func configurePopover() {
        let controller = NSHostingController(rootView: CalendarPanelView(viewModel: viewModel))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    private func configureMenu() {
        let about = NSMenuItem(title: AppInfo.longDisplay, action: nil, keyEquivalent: "")
        about.isEnabled = false
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launch.target = self
        launch.identifier = NSUserInterfaceItemIdentifier("launchAtLogin")
        let quit = NSMenuItem(title: "Quit CalBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        statusMenu.addItem(about)
        statusMenu.addItem(.separator())
        statusMenu.addItem(launch)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quit)
        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.identifier?.rawValue == "launchAtLogin" {
            item.state = viewModel.launchAtLogin ? .on : .off
        }
    }

    @objc private func statusItemClicked(_ sender: AnyObject) {
        guard let event = NSApp.currentEvent else {
            showPopover()
            return
        }
        if event.type == .rightMouseUp || event.type == .otherMouseUp {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                showPopover()
            }
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        viewModel.prepareForPopoverOpen()
        // CalBar is an LSUIElement agent, so it is not frontmost when summoned
        // by the hotkey from another app. Without activating, the panel would
        // open and then ignore every keystroke.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Strip the popover's own backing so the panel's glass refracts the
        // desktop instead of a second blur layer. Must run after show(), when
        // the popover window exists.
        PopoverChrome.makeTransparent(popover)
        popover.contentViewController?.view.window?.makeKey()
        keyboard.install(viewModel: viewModel) { [weak self] in
            self?.popover.performClose(nil)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        viewModel.setLaunchAtLogin(!viewModel.launchAtLogin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startDayRolloverTimer() {
        dayCheckTimer?.invalidate()
        dayCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.refreshStatusIcon()
            self.viewModel.refreshDayIfNeeded()
            self.viewModel.refreshNowIfNeeded()
        }
    }
}

extension Notification.Name {
    static let calbarDayMayHaveChanged = Notification.Name("calbarDayMayHaveChanged")
}
