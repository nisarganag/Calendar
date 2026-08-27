# CalBar keyboard navigation — design

**Date:** 2026-08-27
**Status:** approved, not yet implemented

## Context

CalBar is a menu bar agent whose premise is "one click away from anywhere." The
panel is currently mouse-only: there is no way to move the selection, jump a
month, dismiss the panel, or summon it without reaching for the pointer. This
design adds keyboard control inside the panel, then a fixed system-wide key to
open it.

Ships in two cycles so the first half lands before the second is designed in
code.

## Goals

- Move the selected day, change month, and jump to today without the mouse.
- Dismiss the panel with Escape.
- Summon the panel from any app with a single fixed combination.
- Add no permission prompts and no new persisted state.

## Non-goals

- No user-configurable shortcut, no recorder UI, no conflict detection. The
  combination is a build-time constant; changing it means editing one line.
- No separate keyboard focus ring. Selection *is* focus.
- No type-ahead date search, no vim-style bindings, no multi-day selection.

## Cycle 1 — in-panel keyboard

### Key map

| Key | Action |
|---|---|
| `←` `→` | Move selection ∓1 day |
| `↑` `↓` | Move selection ∓1 week |
| `⌘←` `⌘→` | Previous / next month |
| `⌘T` | Jump to today |
| `Return` | Focus the "Add event…" field for the selected day |
| `Esc` | Escalating dismiss — see below |

### Escape precedence

Escape resolves the innermost thing first, so one key never does two jobs:

1. If the "Add event…" field is being edited → resign first responder, leave the
   draft text intact.
2. Else if the go-to-date card is open → close it, return to the event card.
3. Else → close the panel.

### Selection is focus

Arrow keys move `selectedDate` directly and the event card follows. There is no
second highlight to reason about, and the card updating is the affordance that
tells you the selection moved.

### `CalendarViewModel.moveSelection(byDays:)`

One new method. It selects the new date **and** flips `displayedMonth` when that
date falls outside the month on screen.

This pattern already exists, written by hand at the grid's tap site:

```swift
viewModel.select(date)
if !cell.isInCurrentMonth {
    viewModel.moveMonth(date < viewModel.displayedMonth ? -1 : 1)
}
```

Moving it into the view model gives mouse and keyboard one shared path rather
than two copies that can drift. The tap site is refactored to call it.

Requirements:

- Use `Calendar.date(byAdding: .day, value:)`. Never `timeIntervalSince`
  arithmetic — a ±86400 offset is wrong across a DST boundary and would skip or
  repeat a day twice a year.
- Month flip compares against the displayed month, not the old selection, so a
  jump of any size lands correctly.
- Clamp nothing. Any date is reachable; the grid rebuilds around it.

### Key capture

`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`, installed when the
popover opens and removed when it closes.

Chosen over SwiftUI's `.onKeyPress` because that is macOS 14+, and `Info.plist`
declares `LSMinimumSystemVersion 13.0` — keyboard navigation would silently not
exist on 13 while every other feature still worked. Chosen over a custom
`NSViewRepresentable` first responder because focus management inside a popover
is fiddly for no gain over a monitor.

Two guards, both load-bearing:

- **Text editing.** If `window.firstResponder is NSTextView`, pass every key
  through untouched except Escape. SwiftUI's `TextField` edits via the shared
  AppKit field editor, which is an `NSTextView`, so this is the reliable test.
  Without it, typing an event and pressing `←` would move the calendar instead
  of the caret.
- **Go-to-date open.** When `showGoToDate` is true, handle only Escape and let
  everything else reach the form's own controls — the month menu, year field and
  day stepper all want arrow keys.

Lifecycle: the monitor must be removed on close. `AppDelegate` already observes
`NSPopover.didCloseNotification` for the grace-window stamp; removal hangs off
the same hook. Leaving it installed would keep intercepting keys for the whole
app lifetime.

### Files

| File | Change |
|---|---|
| `Sources/CalendarViewModel.swift` | Add `moveSelection(byDays:)` |
| `Sources/KeyboardCommands.swift` | New — monitor lifecycle, key map, guards |
| `Sources/CalendarViews.swift` | Grid tap site calls `moveSelection` |
| `Sources/AppDelegate.swift` | Install/remove monitor on popover open/close |
| `build.sh` | Add the new source |

## Cycle 2 — global hotkey (⌃⌥C)

New `Sources/HotKey.swift` wrapping Carbon `RegisterEventHotKey` +
`InstallEventHandler`. Registered at launch, unregistered on terminate, toggles
the popover when fired.

Carbon rather than `NSEvent.addGlobalMonitorForEvents` specifically because the
global monitor requires Accessibility permission for key events, and
`RegisterEventHotKey` does not. Keeping CalBar prompt-free matters more here
than API modernity, especially for an ad-hoc-signed build.

**Activation.** CalBar is an `LSUIElement` agent, so when the hotkey fires from
another app it is not frontmost and the popover will not receive key events —
the panel would open and then arrows would do nothing. `showPopover()` must call
`NSApp.activate(ignoringOtherApps: true)`. This is the failure most likely to be
missed, because it only shows up when testing from a *different* app.

## Testing

There is no XCTest target; `build.sh` is raw `swiftc`. Verification runs through
the existing preview harness, which already hosts the panel in a real
`NSPopover`.

`Scripts/preview/main.swift` gains a `CALBAR_KEYS` variable taking a
comma-separated key sequence, posted as synthetic `keyDown` events after launch
and before the screenshot:

```
CALBAR_KEYS=right,right,down ./Scripts/preview/shoot.sh out.png
```

Key codes: `left` 123, `right` 124, `down` 125, `up` 126, `return` 36,
`esc` 53, `t` 17.

This exercises the real chain — monitor, guards, view model, render — rather
than a mock of it.

### Cases to cover

| Case | Expected |
|---|---|
| `right` from the 27th | 28th selected, event card follows |
| `right` from the last day of the month | 1st of next month, grid flips forward |
| `left` from the 1st | last day of previous month, grid flips back |
| `down` ×2 from the 27th | +14 days, month flips if it overruns |
| `⌘right` | Next month, selection preserved |
| `⌘T` after browsing away | Back on today |
| `right` while editing the event field | Caret moves, grid does not |
| `esc` while editing | Field blurs, draft text kept, panel stays open |
| `esc` with go-to-date open | Card closes, panel stays open |
| `esc` otherwise | Panel closes |
| `right` on 28 Feb 2028 | 29 Feb — leap year not skipped |
| Week start Sun vs Mon | Arrow behaviour identical; only layout differs |

DST is worth one explicit check, since it is the case the obvious
implementation gets wrong.

## Risks

- **Monitor leak.** Not removing it on close intercepts keys app-wide. Mitigated
  by hanging removal off the existing close notification.
- **Field editor detection.** If the `NSTextView` check ever fails, typing
  becomes unusable rather than degrading gracefully. Covered by two test cases.
- **Hotkey collision.** ⌃⌥C is a quiet namespace but not guaranteed free. By
  design the fix is editing one constant; accepted deliberately in exchange for
  dropping the recorder UI.
