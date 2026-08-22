import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private lazy var viewModel = CalendarViewModel()
    private var dayCheckTimer: Timer?
    private var currentIconDay = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureMenu()
        viewModel.syncLaunchAtLoginStatus()
        startDayRolloverTimer()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.toolTip = "CalBar — Menu Bar Calendar"
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
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launch.target = self
        launch.identifier = NSUserInterfaceItemIdentifier("launchAtLogin")
        let quit = NSMenuItem(title: "Quit CalBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        viewModel.setLaunchAtLogin(!viewModel.launchAtLogin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startDayRolloverTimer() {
        dayCheckTimer?.invalidate()
        dayCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.refreshStatusIcon()
            self.viewModel.refreshDayIfNeeded()
            // Only enforce the idle snap-back while the panel is visible;
            // when it's hidden, prepareForPopoverOpen() decides on reopen.
            if self.popover.isShown {
                self.viewModel.enforceIdleSnapBack()
            }
        }
    }
}

extension Notification.Name {
    static let calbarDayMayHaveChanged = Notification.Name("calbarDayMayHaveChanged")
}
