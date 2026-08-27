import Foundation

// MARK: - Inline time parsing
//
// Splits "Dentist 3pm" into 15:00 + "Dentist" so a time can be typed without
// leaving the keyboard.
//
// Deliberately conservative. A false positive silently mangles the user's text
// and there is no undo, so the rules require a time to be unmistakable: a
// standalone token at the start or end, with an am/pm suffix or a separator.
// Bare digits are never a time, which keeps "Level 3" and "Sprint 12" intact.

enum EventTimeParser {

    struct Parsed: Equatable {
        var title: String
        var minutes: Int?
    }

    /// Minutes from midnight, 0...1439.
    private static let dayMinutes = 24 * 60

    static func parse(_ input: String) -> Parsed {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(title: input, minutes: nil) }

        var tokens = trimmed.split(separator: " ").map(String.init)
        guard tokens.count >= 1 else { return Parsed(title: trimmed, minutes: nil) }

        // Try the tail first, then the head. A time in the middle ("Call 3pm
        // sharp") is left alone — it is more likely prose than a field.
        if let (minutes, consumed) = timeAtEnd(tokens) {
            tokens.removeLast(consumed)
            return finish(tokens, minutes, fallback: trimmed)
        }
        if let (minutes, consumed) = timeAtStart(tokens) {
            tokens.removeFirst(consumed)
            return finish(tokens, minutes, fallback: trimmed)
        }
        return Parsed(title: trimmed, minutes: nil)
    }

    /// A time with nothing left over is not an event — keep the original text.
    private static func finish(_ tokens: [String], _ minutes: Int, fallback: String) -> Parsed {
        let title = tokens.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return Parsed(title: fallback, minutes: nil) }
        return Parsed(title: title, minutes: minutes)
    }

    /// Handles both "3pm" as one token and "3 pm" as two.
    private static func timeAtEnd(_ tokens: [String]) -> (Int, Int)? {
        if let last = tokens.last, let m = minutes(from: last) { return (m, 1) }
        if tokens.count >= 2 {
            let joined = tokens[tokens.count - 2] + tokens[tokens.count - 1]
            if let m = minutes(from: joined) { return (m, 2) }
        }
        return nil
    }

    private static func timeAtStart(_ tokens: [String]) -> (Int, Int)? {
        if let first = tokens.first, let m = minutes(from: first) { return (m, 1) }
        if tokens.count >= 2 {
            let joined = tokens[0] + tokens[1]
            if let m = minutes(from: joined) { return (m, 2) }
        }
        return nil
    }

    /// Parses a single token. Returns nil unless it is unambiguously a time.
    static func minutes(from token: String) -> Int? {
        let t = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        guard !t.isEmpty else { return nil }

        if t.hasSuffix("am") || t.hasSuffix("pm") {
            let isPM = t.hasSuffix("pm")
            let body = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces)
            guard let (hour, minute) = hourMinute(body, separatorRequired: false) else { return nil }
            guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
            // 12am is midnight, 12pm is noon.
            let base = (hour % 12) + (isPM ? 12 : 0)
            return base * 60 + minute
        }

        // 24-hour form must carry a separator, so a bare "3" is never a time.
        guard let (hour, minute) = hourMinute(t, separatorRequired: true) else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let total = hour * 60 + minute
        return total < dayMinutes ? total : nil
    }

    /// Splits "9", "9:30" or "9.30" into components.
    private static func hourMinute(_ body: String, separatorRequired: Bool) -> (Int, Int)? {
        guard !body.isEmpty else { return nil }
        let parts = body.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)

        switch parts.count {
        case 1 where !separatorRequired:
            guard parts[0].allSatisfy(\.isNumber), let h = Int(parts[0]) else { return nil }
            return (h, 0)
        case 2:
            guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                  let h = Int(parts[0]), let m = Int(parts[1]),
                  parts[1].count == 2 else { return nil }
            return (h, m)
        default:
            return nil
        }
    }

    /// Canonical 24-hour form, "15:00". Locale-independent, so tests and
    /// storage comparisons stay deterministic.
    static func format(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// A time split into the two pieces a row lays out separately.
    ///
    /// The hour is zero-padded even in 12-hour locales, so "06:00 PM" sits
    /// under "12:00 AM". That is unusual for prose but it is the only thing
    /// that makes a column truly flush: with a bare "6:00", any alignment you
    /// pick leaves something ragged — right-aligning lines the colons up but
    /// lets the "1" of 12 jut out into the gutter, and left-aligning lines the
    /// hours up but scatters the colons. Equal-width strings cannot be ragged.
    struct DisplayParts: Equatable {
        var numeric: String     // "9:30", "12:00", "17:30"
        var meridiem: String    // "AM"/"PM"; empty in 24-hour locales
    }

    /// Whether the locale writes times with AM/PM. Rows use this to size the
    /// time column, so a 24-hour locale does not carry an empty meridiem gutter.
    static func usesMeridiem(locale: Locale = .current) -> Bool {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("jm")
        return (f.dateFormat ?? "").contains("a")
    }

    static func displayParts(_ minutes: Int, locale: Locale = .current) -> DisplayParts {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("jm")

        let hour24 = minutes / 60
        let minute = minutes % 60

        // A 12-hour locale's pattern carries the meridiem placeholder.
        guard (f.dateFormat ?? "").contains("a") else {
            return DisplayParts(numeric: String(format: "%02d:%02d", hour24, minute),
                                meridiem: "")
        }
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return DisplayParts(numeric: String(format: "%02d:%02d", hour12, minute),
                            meridiem: hour24 < 12 ? f.amSymbol : f.pmSymbol)
    }

    /// Flat form, for tooltips and accessibility.
    static func display(_ minutes: Int, locale: Locale = .current) -> String {
        let p = displayParts(minutes, locale: locale)
        return p.meridiem.isEmpty ? p.numeric : "\(p.numeric) \(p.meridiem)"
    }
}
