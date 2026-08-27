import AppKit

// MARK: - Keyboard control for the panel
//
// Uses a local NSEvent monitor rather than SwiftUI's `.onKeyPress`, which is
// macOS 14+. Info.plist declares a 13.0 minimum, so `.onKeyPress` would leave
// keyboard navigation silently missing on 13 while every other feature still
// worked.

/// Not actor-isolated, matching CalendarViewModel and AppDelegate: every entry
/// point here already runs on the main thread — popover show/close, and the
/// local monitor's callback.
final class KeyboardCommands {

    private enum Key {
        static let ret: UInt16 = 36
        static let tab: UInt16 = 48
        static let esc: UInt16 = 53
        static let keypadEnter: UInt16 = 76
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let t: UInt16 = 17
    }

    /// Bridges the gap between asking for the event field and focus arriving.
    ///
    /// Return routes through SwiftUI's FocusState, which reaches AppKit's first
    /// responder a run loop turn later. Without this, a key pressed in that
    /// window would be treated as grid navigation even though the user has
    /// already handed control to the field.
    private var yieldedToField = false

    private var monitor: Any?
    private weak var viewModel: CalendarViewModel?
    private var dismiss: (() -> Void)?

    /// Starts handling keys for `viewModel`. Call `remove()` when the panel
    /// closes.
    func install(viewModel: CalendarViewModel, dismiss: @escaping () -> Void) {
        remove()
        self.viewModel = viewModel
        self.dismiss = dismiss
        yieldedToField = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }

        // The popover hands first responder to the only focusable view — the
        // "Add event…" field — as it opens. Left alone, the field would swallow
        // every arrow key and the grid would never see one. Hand the keys back
        // to the grid; Return or Tab focuses the field deliberately.
        // Twice on purpose: once now for focus the popover has already
        // assigned, and once after the run loop turns for focus SwiftUI
        // assigns on its next pass.
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    /// Must run when the panel closes. A monitor left installed keeps
    /// intercepting keys for the rest of the app's lifetime.
    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        viewModel = nil
        dismiss = nil
        yieldedToField = false
    }

    /// Returns true when the event was consumed and should not travel further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let viewModel else { return false }
        let code = event.keyCode
        let command = event.modifierFlags.contains(.command)

        // Once focus has actually arrived, the first responder is authoritative
        // again and the bridge is dropped.
        if yieldedToField && isEditingText { yieldedToField = false }
        let editing = isEditingText || yieldedToField

        // Escape resolves the innermost thing first, so one key never does two
        // jobs: leave the field, then close the card, then close the panel.
        if code == Key.esc {
            if editing {
                yieldedToField = false
                endEditing()
                return true
            }
            if viewModel.showGoToDate {
                viewModel.showGoToDate = false
                return true
            }
            dismiss?()
            return true
        }

        // While the field editor is up, every other key belongs to the text.
        // Without this, typing an event and pressing left would move the
        // calendar instead of the caret.
        if editing { return false }

        // The go-to-date form's own controls want the arrow keys.
        if viewModel.showGoToDate { return false }

        switch (code, command) {
        case (Key.left, false):
            viewModel.moveSelection(byDays: -1)
        case (Key.right, false):
            viewModel.moveSelection(byDays: 1)
        case (Key.up, false):
            viewModel.moveSelection(byDays: -7)
        case (Key.down, false):
            viewModel.moveSelection(byDays: 7)
        case (Key.left, true):
            viewModel.moveMonth(-1)
        case (Key.right, true):
            viewModel.moveMonth(1)
        case (Key.t, true):
            viewModel.goToday()
        case (Key.ret, false), (Key.keypadEnter, false), (Key.tab, false):
            viewModel.focusEventField = true
            yieldedToField = true
        default:
            return false
        }
        return true
    }

    /// SwiftUI's TextField edits through AppKit's shared field editor, which is
    /// an NSTextView — so this is the reliable test for "the user is typing".
    private var isEditingText: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView
    }

    private func endEditing() {
        window?.makeFirstResponder(nil)
    }

    private var window: NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }
}
