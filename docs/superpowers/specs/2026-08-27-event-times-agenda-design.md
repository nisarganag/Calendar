# CalBar event times and agenda — design

**Date:** 2026-08-27
**Status:** approved, implementing

## Context

Events are stored as `[String: [String]]` under `CalBar.events.v1` — a day maps
to a list of plain strings. An event has no time, so nothing sorts, nothing can
remind you, and "2pm" exists only if you typed those characters yourself. The
keyboard work made this sharper: Return now drops you into a field that accepts
anything at all.

This gives events a real time and turns a day's list into an agenda.

## Goals

- An event can carry a time, entered by typing it inline.
- A day's events sort meaningfully.
- On today, past events recede and the next one is marked.
- Existing stored events survive untouched.

## Non-goals

- No notifications yet. Times are the prerequisite; reminders are separate work.
- No end times, durations, or multi-day events.
- No recurrence.
- No EventKit. This stays CalBar's own store.

## Storage

`CalEvent` persisted as JSON under a new key `CalBar.events.v2`:

```swift
struct CalEvent: Codable, Equatable {
    var title: String
    var minutes: Int?    // minutes from midnight; nil = untimed
}
```

**Time is minutes from midnight, not a `Date`.** A `Date` would drag timezone
and DST correctness into what is really "3pm on whatever day this row belongs
to" — on 27 October a stored `Date` shifts by an hour and the agenda reorders
itself. An `Int?` sorts trivially, survives timezone changes, and cannot drift.

Range 0...1439. Values outside are rejected at parse time.

### Migration

On first load: if v2 is absent and v1 present, map each string to
`CalEvent(title: s, minutes: nil)` and write v2.

- **v1 is left in place, not deleted.** It costs a few KB and means a downgrade
  doesn't lose data.
- **Titles are not re-parsed during migration.** An existing "Design review ·
  2pm" stays exactly as typed. Rewriting stored user data during an upgrade is
  fine until it mangles one entry, and there is no undo. The user can retype the
  few that matter.

## Parsing

Lives in `EventTimeParser`, isolated because it is the riskiest part and pure.
A wrong parse silently mangles the user's text, which is worse than not parsing
at all — so the rules are deliberately conservative.

Accepted only when the time is a **standalone token at the start or end** of the
input:

| Form | Requirement | Examples |
|---|---|---|
| 12-hour | am/pm suffix required | `3pm`, `3 pm`, `3:30pm`, `3.30 PM` |
| 24-hour | separator required | `15:00`, `15.30`, `09:05` |

Consequences that matter:

- Bare digits are never a time. `Level 3`, `Sprint 12`, `Room 3` pass through.
- `Q1 review` is untouched — `Q1` is not a time token.
- If stripping the time leaves an empty title, the whole input is kept as
  untimed text. Typing just `3pm` must not create a nameless event.
- Separators and surrounding whitespace are trimmed from the remaining title.

`12am` is 0 minutes, `12pm` is 720. Hours above 23 or minutes above 59 are
rejected and the text stays untimed.

## Ordering

1. Untimed events first, in insertion order — matching how calendars place
   all-day items above the timed grid.
2. Timed events after, ascending by `minutes`.

Sorting is stable, so two events at the same time keep the order they were added.

## Time-of-day treatment

Applies **only to today**; any other day renders neutrally.

- **Past** — a timed event whose `minutes` is less than now. Dimmed.
- **Next** — the first timed event whose `minutes` is greater than or equal to
  now. Carries a marker.
- Untimed events are never past and never next.

This has to re-evaluate as the day advances. `AppDelegate` already runs a 30-second
`dayCheckTimer` for the menu bar icon; reuse it rather than adding a second
timer. 30s granularity is well inside what a per-minute agenda needs.

## Files

| File | Change |
|---|---|
| `Sources/EventStore.swift` *(new)* | `CalEvent`, v2 codec, v1 migration. Currently buried in `CalendarViewModel.swift` and about to grow. |
| `Sources/EventTimeParser.swift` *(new)* | The parser. |
| `Sources/CalendarViewModel.swift` | `[String: [CalEvent]]`, sorted accessor, next-up computation, parse on add. |
| `Sources/CalendarViews.swift` | Row shows the time; dim and next-up styling. |
| `Sources/AppDelegate.swift` | Reuse the existing timer to refresh time-of-day state. |
| `build.sh`, `Scripts/preview/shoot.sh` | New sources. |

## Testing

The parser is pure, so it does not need the GUI harness. `Scripts/parsertests.swift`
compiles and runs directly against `EventTimeParser`, which is faster and far
more precise than screenshots.

### Parser cases

| Input | Expect |
|---|---|
| `Dentist 3pm` | 900, "Dentist" |
| `3pm Dentist` | 900, "Dentist" |
| `Standup 09:30` | 570, "Standup" |
| `Standup 9:30am` | 570, "Standup" |
| `Lunch 12pm` | 720, "Lunch" |
| `Late 12am` | 0, "Late" |
| `Review 3.30pm` | 930, "Review" |
| `Level 3` | nil, "Level 3" |
| `Room 3` | nil, "Room 3" |
| `Q1 review` | nil, "Q1 review" |
| `Sprint 12` | nil, "Sprint 12" |
| `3pm` | nil, "3pm" — no title left |
| `Meeting 25:00` | nil, "Meeting 25:00" — hour out of range |
| `Meeting 12:75` | nil, "Meeting 12:75" — minute out of range |
| `Call 3pm sharp` | nil, "Call 3pm sharp" — not at an edge |
| `` (empty) | nil, "" |

### Store cases

| Case | Expect |
|---|---|
| v1 present, v2 absent | migrated to untimed, v1 still on disk |
| v2 present | v1 ignored |
| both absent | empty |
| v1 title containing a time | preserved verbatim, not re-parsed |

### Visual cases (preview harness)

Sorted order, untimed above timed, a dimmed past event on today, the next-up
marker, and a non-today date rendering neutrally.

## Risks

- **Parser false positives** are the main one; a mangled title has no undo.
  Mitigated by requiring edge position plus an explicit separator or suffix, and
  by the case table above.
- **Migration** runs once against real user data. Mitigated by writing to a new
  key and never touching v1.
