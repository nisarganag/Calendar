import Foundation

// Direct assertions against EventTimeParser. The parser is pure, so it needs no
// GUI harness — this is faster and far more precise than screenshots.

var passed = 0, failed = 0

func check(_ input: String, _ minutes: Int?, _ title: String, _ note: String = "") {
    let got = EventTimeParser.parse(input)
    if got.minutes == minutes && got.title == title {
        passed += 1
        print("  PASS  \(input.isEmpty ? "<empty>" : input)")
    } else {
        failed += 1
        print("  FAIL  \(input.isEmpty ? "<empty>" : input)\(note.isEmpty ? "" : "  (\(note))")")
        print("        expected minutes=\(minutes.map(String.init) ?? "nil") title=\u{27}\(title)\u{27}")
        print("        got      minutes=\(got.minutes.map(String.init) ?? "nil") title=\u{27}\(got.title)\u{27}")
    }
}

print("Times are recognised")
check("Dentist 3pm", 900, "Dentist")
check("3pm Dentist", 900, "Dentist")
check("Dentist 3 pm", 900, "Dentist")
check("Standup 09:30", 570, "Standup")
check("Standup 9:30am", 570, "Standup")
check("Lunch 12pm", 720, "Lunch")
check("Late 12am", 0, "Late")
check("Review 3.30pm", 930, "Review")
check("Sync 15:00", 900, "Sync")
check("Team offsite 9am", 540, "Team offsite")

print("Text that only looks like a time is left alone")
check("Level 3", nil, "Level 3", "bare digit")
check("Room 3", nil, "Room 3", "bare digit")
check("Q1 review", nil, "Q1 review")
check("Sprint 12", nil, "Sprint 12", "bare digit")
check("Call 3pm sharp", nil, "Call 3pm sharp", "time not at an edge")
check("Read chapter 7", nil, "Read chapter 7", "bare digit")

print("Malformed times stay as text")
check("Meeting 25:00", nil, "Meeting 25:00", "hour out of range")
check("Meeting 12:75", nil, "Meeting 12:75", "minute out of range")
check("Meeting 13pm", nil, "Meeting 13pm", "no 13 on a 12-hour clock")
check("3pm", nil, "3pm", "no title left")
check("15:00", nil, "15:00", "no title left")
check("", nil, "")

print("Formatting")
do {
    let en24 = Locale(identifier: "en_GB")
    let en12 = Locale(identifier: "en_US")
    expect("display follows a 24-hour locale",
           EventTimeParser.display(1050, locale: en24).contains("17"),
           "got \(EventTimeParser.display(1050, locale: en24))")
    expect("display follows a 12-hour locale",
           EventTimeParser.display(1050, locale: en12).lowercased().contains("5"),
           "got \(EventTimeParser.display(1050, locale: en12))")
    expect("canonical format stays 24-hour regardless",
           EventTimeParser.format(1050) == "17:30")
    let us = Locale(identifier: "en_US")
    let gb = Locale(identifier: "en_GB")
    expect("12-hour splits into numeric and meridiem",
           EventTimeParser.displayParts(570, locale: us)
               == EventTimeParser.DisplayParts(numeric: "09:30", meridiem: "AM"),
           "got \(EventTimeParser.displayParts(570, locale: us))")
    expect("noon is 12 PM not 0 PM",
           EventTimeParser.displayParts(720, locale: us).numeric == "12:00")
    expect("midnight is 12 AM not 0 AM",
           EventTimeParser.displayParts(0, locale: us)
               == EventTimeParser.DisplayParts(numeric: "12:00", meridiem: "AM"))
    expect("every 12-hour time renders the same width",
           Set([0, 570, 720, 1050, 1439].map { EventTimeParser.displayParts($0, locale: us).numeric.count }).count == 1,
           "widths: \([0, 570, 720, 1050, 1439].map { EventTimeParser.displayParts($0, locale: us).numeric })")
    expect("six PM is zero-padded",
           EventTimeParser.displayParts(1080, locale: us).numeric == "06:00")
    expect("24-hour locale has no meridiem and zero-pads the hour",
           EventTimeParser.displayParts(570, locale: gb)
               == EventTimeParser.DisplayParts(numeric: "09:30", meridiem: ""),
           "got \(EventTimeParser.displayParts(570, locale: gb))")
    // The time field renders with `display` and commits with `minutes(from:)`.
    // If those two ever disagree, typing back exactly what is shown would
    // change the time — so pin the round trip.
    let roundTrip: [Int] = [0, 1, 570, 719, 720, 721, 1050, 1110, 1439]
    expect("everything the field shows parses back to the same time (12-hour)",
           roundTrip.allSatisfy { m in
               EventTimeParser.minutes(from:
                   EventTimeParser.display(m, locale: us).replacingOccurrences(of: " ", with: "")) == m
           },
           "offenders: \(roundTrip.filter { m in EventTimeParser.minutes(from: EventTimeParser.display(m, locale: us).replacingOccurrences(of: " ", with: "")) != m }.map { ($0, EventTimeParser.display($0, locale: us)) })")
    expect("everything the field shows parses back to the same time (24-hour)",
           roundTrip.allSatisfy { m in
               EventTimeParser.minutes(from:
                   EventTimeParser.display(m, locale: gb).replacingOccurrences(of: " ", with: "")) == m
           },
           "offenders: \(roundTrip.filter { m in EventTimeParser.minutes(from: EventTimeParser.display(m, locale: gb).replacingOccurrences(of: " ", with: "")) != m }.map { ($0, EventTimeParser.display($0, locale: gb)) })")

    expect("flat display joins the parts",
           EventTimeParser.display(1050, locale: us) == "05:30 PM")
}
if EventTimeParser.format(900) == "15:00" && EventTimeParser.format(545) == "9:05" {
    passed += 1; print("  PASS  format")
} else {
    failed += 1; print("  FAIL  format -> \(EventTimeParser.format(900)), \(EventTimeParser.format(545))")
}

func expect(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    if condition { passed += 1; print("  PASS  \(label)") }
    else { failed += 1; print("  FAIL  \(label)"); let d = detail(); if !d.isEmpty { print("        \(d)") } }
}

func freshDefaults(_ name: String) -> UserDefaults {
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

print("Store: migration")
do {
    let d = freshDefaults("calbar.tests.migrate")
    d.set(["2026-08-27": ["Design review · 2pm", "Ship it"]], forKey: EventStore.legacyKey)
    let loaded = EventStore.load(from: d)
    expect("v1 migrates to untimed",
           loaded["2026-08-27"] == [CalEvent(title: "Design review · 2pm"), CalEvent(title: "Ship it")],
           "got \(loaded)")
    expect("v1 title is not re-parsed",
           loaded["2026-08-27"]?.first?.minutes == nil)
    expect("v1 is left on disk",
           d.dictionary(forKey: EventStore.legacyKey) != nil)
    expect("v2 was written",
           d.data(forKey: EventStore.storageKey) != nil)
}

do {
    let d = freshDefaults("calbar.tests.v2wins")
    d.set(["2026-08-27": ["legacy"]], forKey: EventStore.legacyKey)
    EventStore.save(["2026-08-27": [CalEvent(title: "modern", minutes: 600)]], to: d)
    let loaded = EventStore.load(from: d)
    expect("v2 takes precedence over v1", loaded["2026-08-27"]?.first?.title == "modern")
}

do {
    let d = freshDefaults("calbar.tests.empty")
    expect("no data yields empty", EventStore.load(from: d).isEmpty)
}

print("Store: ordering")
do {
    let events = [
        CalEvent(title: "afternoon", minutes: 900),
        CalEvent(title: "note a"),
        CalEvent(title: "morning", minutes: 540),
        CalEvent(title: "note b"),
    ]
    let s = EventStore.sorted(events)
    expect("untimed first, then timed ascending",
           s.map(\.title) == ["note a", "note b", "morning", "afternoon"],
           "got \(s.map(\.title))")
    expect("next-up skips untimed and picks the first upcoming",
           EventStore.nextUpIndex(in: s, atOrAfter: 600) == 3,
           "got \(String(describing: EventStore.nextUpIndex(in: s, atOrAfter: 600)))")
    expect("next-up is nil when the day is over",
           EventStore.nextUpIndex(in: s, atOrAfter: 1400) == nil)
    expect("next-up matches an event starting exactly now",
           EventStore.nextUpIndex(in: s, atOrAfter: 540) == 2)
}

print("Add row: picked time vs typed time")
do {
    expect("picker wins over a typed time",
           EventStore.makeEvent(text: "Standup 9:30", pickedMinutes: 1050)
               == CalEvent(title: "Standup", minutes: 1050))
    expect("typed time is stripped from the title even when the picker wins",
           EventStore.makeEvent(text: "Standup 9:30", pickedMinutes: 1050)?.title == "Standup")
    expect("typed time is used when the picker is off",
           EventStore.makeEvent(text: "Standup 9:30", pickedMinutes: nil)
               == CalEvent(title: "Standup", minutes: 570))
    expect("plain text stays untimed",
           EventStore.makeEvent(text: "Water the plants", pickedMinutes: nil)
               == CalEvent(title: "Water the plants", minutes: nil))
    expect("picker time applies to plain text",
           EventStore.makeEvent(text: "Water the plants", pickedMinutes: 600)?.minutes == 600)
    expect("bare time with a picker set is still not an event",
           EventStore.makeEvent(text: "3pm", pickedMinutes: 1050)?.title == "3pm")
    expect("empty text makes nothing",
           EventStore.makeEvent(text: "   ", pickedMinutes: 600) == nil)
    expect("next half hour rounds up", EventStore.nextHalfHour(from: 17 * 60 + 12) == 17 * 60 + 30)
    expect("next half hour on the half rounds to the next",
           EventStore.nextHalfHour(from: 17 * 60 + 30) == 18 * 60)
    expect("next half hour clamps inside the day",
           EventStore.nextHalfHour(from: 23 * 60 + 50) == 23 * 60 + 30)
}

print("")
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
