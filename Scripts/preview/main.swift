import Cocoa
import SwiftUI

// Preview-only harness. Hosts CalendarPanelView inside a real NSPopover over a
// wallpaper-like backdrop, so what gets screenshotted is the same chrome the
// shipping app puts the panel in — not an approximation of it.

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let popover = NSPopover()
    let keyboard = KeyboardCommands()
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

        keyboard.install(viewModel: vm) { [weak self] in self?.popover.performClose(nil) }
        postScriptedKeys()

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
        // Spans the whole day so some rows are past and one is next whatever
        // time the suite happens to run at. Includes text that must NOT parse.
        add(0, [
            "Water the plants",
            "Standup 09:30",
            "Design review 12pm",
            "Ship CalBar build 15:00",
            "Retro 17:30",
            "Level 3 parking",
            "Dinner 8pm",
        ])
        add(3, ["Dentist 11am"])
        add(-2, ["Standup 09:30"])
        add(6, ["Flight to SFO 6:45am"])
        vm.select(today)

        let env = ProcessInfo.processInfo.environment
        if let off = env["CALBAR_SELECT"].flatMap(Int.init),
           let d = cal.date(byAdding: .day, value: off, to: today) {
            vm.select(d)
        }
        if env["CALBAR_WEEKSTART"] == "sun" { vm.weekStartsMonday = false }
        if env["CALBAR_TIME"] == "1" { vm.toggleDraftTime(); vm.draftEvent = "Retro" }
        if env["CALBAR_TIME"] == "2" {
            vm.toggleDraftTime()
            vm.draftEvent = "Retro"
            // Same mutation the stepper performs. If the field still shows the
            // armed time after this, the display is frozen again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.vm.draftMinutes = 7 * 60 + 15
                self.log("stepper-sim set draftMinutes=435 (07:15 AM)")
            }
        }
        if env["CALBAR_GOTO"] == "1" { vm.openGoToDate() }
        if env["CALBAR_EMPTY"] == "1" {
            vm.eventsByDay = [:]
            vm.rebuild()
        }
    }
}

/// Key codes for the scripted sequences in CALBAR_KEYS.
private let keyCodes: [String: (code: UInt16, chars: String)] = [
    "left":   (123, "\u{F702}"),
    "right":  (124, "\u{F703}"),
    "down":   (125, "\u{F701}"),
    "up":     (126, "\u{F700}"),
    "return": (36,  "\r"),
    "esc":    (53,  "\u{1B}"),
    "tab":    (48,  "\t"),
    "t":      (17,  "t"),
    "a":      (0,   "a"),
]

extension PreviewDelegate {
    /// Posts a comma-separated key sequence into the popover so the real
    /// monitor -> view model -> render chain runs before the screenshot.
    /// Prefix a key with "cmd-" for the command modifier, e.g. "cmd-right".
    /// Reports the resulting state once the run loop has actually drained the
    /// posted events — reading it inline would sample before dispatch.
    func reportAfterDrain(_ sent: [String], after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.log("keys=[\(sent.joined(separator: ","))] -> selected="
                     + EventStore.key(for: self.vm.selectedDate)
                     + " month=" + EventStore.key(for: self.vm.displayedMonth)
                     + " goto=\(self.vm.showGoToDate)"
                     + " shown=\(self.popover.isShown)"
                     + " draft=\u{27}\(self.vm.draftEvent)\u{27}"
                     + " editing=\(self.popover.contentViewController?.view.window?.firstResponder is NSTextView)")
        }
    }

    func log(_ m: String) {
        FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    }

    func postScriptedKeys() {
        let script = ProcessInfo.processInfo.environment["CALBAR_KEYS"] ?? ""
        guard !script.isEmpty else { return }
        guard let window = popover.contentViewController?.view.window else { return }
        window.makeKey()

        // Keys are staggered rather than posted back-to-back. A real person's
        // keystrokes are milliseconds apart, and some effects — SwiftUI moving
        // FocusState into an AppKit first responder — need a run-loop turn to
        // land. Zero-gap posting tests a situation that cannot happen.
        // A lead-in before the first key: the panel blurs the text field as it
        // opens, and a key posted into that window gets swallowed. A real user
        // cannot type this fast, so waiting is faithful, not a fudge.
        let leadIn = 0.2
        let stagger = 0.03
        var sent: [String] = []
        for (index, token) in script.split(separator: ",").enumerated() {
            var name = token.trimmingCharacters(in: .whitespaces).lowercased()
            var flags: NSEvent.ModifierFlags = []
            if name.hasPrefix("cmd-") { flags.insert(.command); name = String(name.dropFirst(4)) }
            guard let key = keyCodes[name] else {
                log("unknown key: \(name)")
                continue
            }
            sent.append(name)
            DispatchQueue.main.asyncAfter(deadline: .now() + leadIn + Double(index) * stagger) {
                for phase in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let e = NSEvent.keyEvent(
                        with: phase, location: .zero, modifierFlags: flags,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        characters: key.chars, charactersIgnoringModifiers: key.chars,
                        isARepeat: false, keyCode: key.code
                    ) else { continue }
                    // postEvent, not sendEvent: local monitors hook events as
                    // the run loop dequeues them, so sendEvent skips the monitor.
                    NSApp.postEvent(e, atStart: false)
                }
            }
        }
        reportAfterDrain(sent, after: leadIn + Double(sent.count) * stagger + 0.5)
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
