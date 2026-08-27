import Cocoa
import SwiftUI

// Preview-only harness. Hosts CalendarPanelView inside a real NSPopover over a
// wallpaper-like backdrop, so what gets screenshotted is the same chrome the
// shipping app puts the panel in — not an approximation of it.

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let popover = NSPopover()
    var vm: CalendarViewModel!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        resetDefaults()
        vm = CalendarViewModel()
        seedEvents()

        let anchor = NSView(frame: NSRect(x: 266, y: 758, width: 28, height: 22))
        let host = NSHostingView(rootView: Backdrop().frame(width: 560, height: 820))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 820),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "CalBar Preview"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = host
        host.addSubview(anchor)
        window.setFrameOrigin(NSPoint(x: 140, y: 90))
        window.appearance = NSAppearance(
            named: ProcessInfo.processInfo.environment["CALBAR_APPEARANCE"] == "light" ? .aqua : .darkAqua
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let controller = NSHostingController(rootView: CalendarPanelView(viewModel: vm))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)

        FileHandle.standardError.write(("HIERARCHY\n" + PopoverChrome.dump(popover)).data(using: .utf8)!)
        if ProcessInfo.processInfo.environment["CALBAR_CLEAR"] == "1" {
            PopoverChrome.makeTransparent(popover)
        }

        if let screen = NSScreen.main {
            let f = window.frame
            let top = screen.frame.maxY - f.maxY
            print("RECT \(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))")
            fflush(stdout)
        }
    }

    /// The view model persists to UserDefaults, so without this the seeded
    /// events pile up across preview runs.
    private func resetDefaults() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("CalBar.") {
            d.removeObject(forKey: key)
        }
        d.synchronize()
    }

    private func seedEvents() {
        let cal = Calendar.current
        let today = Date()
        func add(_ offset: Int, _ items: [String]) {
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return }
            vm.select(d)
            for i in items { vm.draftEvent = i; vm.addDraftEvent() }
        }
        add(0, ["Design review · 2pm", "Ship CalBar build"])
        add(3, ["Dentist"])
        add(-2, ["Standup"])
        add(6, ["Flight to SFO"])
        vm.select(today)

        let env = ProcessInfo.processInfo.environment
        if let off = env["CALBAR_SELECT"].flatMap(Int.init),
           let d = cal.date(byAdding: .day, value: off, to: today) {
            vm.select(d)
        }
        if env["CALBAR_GOTO"] == "1" { vm.openGoToDate() }
        if env["CALBAR_EMPTY"] == "1" {
            vm.eventsByDay = [:]
            vm.rebuild()
        }
    }
}

/// Stand-in for a desktop wallpaper: strong hue and luminance variation, so any
/// refraction the glass performs is actually visible in the screenshot.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.04, green: 0.09, blue: 0.26),
                Color(red: 0.36, green: 0.14, blue: 0.55),
                Color(red: 0.92, green: 0.40, blue: 0.26),
                Color(red: 0.98, green: 0.80, blue: 0.34),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<9, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i.isMultiple(of: 2) ? 0.16 : 0.07))
                    .frame(width: CGFloat(60 + i * 52))
                    .offset(x: CGFloat((i * 97) % 380) - 190, y: CGFloat(i * 88) - 300)
            }
            // Hard edges give the refraction something unambiguous to bend.
            VStack(spacing: 44) {
                ForEach(0..<9, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.22)).frame(height: 3)
                }
            }
        }
    }
}

let app = NSApplication.shared
let d = PreviewDelegate()
app.delegate = d
app.run()
