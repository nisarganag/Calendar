import Foundation

// MARK: - Event storage
//
// v1 stored a day as a list of plain strings. v2 stores CalEvent, which can
// carry a time. The two keys coexist: v1 is migrated on first load and then
// left on disk, so downgrading does not lose anything.

struct CalEvent: Codable, Equatable, Identifiable {
    /// Stable identity so a row can be deleted by reference. The list is shown
    /// sorted, so an index into the displayed order no longer matches the
    /// stored order — deleting by position would remove the wrong event.
    var id: UUID = UUID()
    var title: String
    /// Minutes from midnight, 0...1439. nil means untimed.
    ///
    /// Deliberately not a Date: a Date drags timezone and DST correctness into
    /// what is really "3pm on whatever day this row belongs to", and on a
    /// clock-change day a stored Date shifts an hour and the agenda reorders
    /// itself. An Int sorts trivially and cannot drift.
    var minutes: Int?

    init(title: String, minutes: Int? = nil, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.minutes = minutes
    }

    var isTimed: Bool { minutes != nil }

    /// Identity is not part of equality — two events with the same title and
    /// time are the same event as far as anyone reading the list is concerned.
    static func == (a: CalEvent, b: CalEvent) -> Bool {
        a.title == b.title && a.minutes == b.minutes
    }
}

enum EventStore {
    static let legacyKey = "CalBar.events.v1"
    static let storageKey = "CalBar.events.v2"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }

    static func load(from defaults: UserDefaults = .standard) -> [String: [CalEvent]] {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [CalEvent]].self, from: data) {
            return decoded
        }
        let migrated = migrateLegacy(from: defaults)
        if !migrated.isEmpty { save(migrated, to: defaults) }
        return migrated
    }

    static func save(_ events: [String: [CalEvent]], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Reads v1 and lifts it to v2 as untimed events.
    ///
    /// Titles are copied verbatim — an existing "Design review · 2pm" keeps
    /// those characters rather than being re-parsed into a real time. Rewriting
    /// stored user data during an upgrade is fine right up until it mangles one
    /// entry, and there is no undo.
    static func migrateLegacy(from defaults: UserDefaults = .standard) -> [String: [CalEvent]] {
        guard let legacy = defaults.dictionary(forKey: legacyKey) as? [String: [String]] else {
            return [:]
        }
        return legacy.mapValues { titles in titles.map { CalEvent(title: $0) } }
    }

    /// Builds the event an add-row currently describes.
    ///
    /// Kept pure and out of the view model so it can be tested directly. An
    /// explicitly picked time wins over one typed into the text — but the typed
    /// token is still stripped, so a 17:30 event never carries "9:30" in its
    /// title.
    static func makeEvent(text: String, pickedMinutes: Int?) -> CalEvent? {
        let parsed = EventTimeParser.parse(text)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return CalEvent(title: title, minutes: pickedMinutes ?? parsed.minutes)
    }

    /// The next half hour on the clock — a sensible opening value for the
    /// picker, since events are far more often ahead than behind.
    static func nextHalfHour(from minutes: Int) -> Int {
        let next = ((minutes / 30) + 1) * 30
        return min(next, 23 * 60 + 30)
    }

    /// Untimed first in insertion order, then timed ascending — matching how
    /// calendars place all-day items above the timed grid.
    static func sorted(_ events: [CalEvent]) -> [CalEvent] {
        let untimed = events.filter { !$0.isTimed }
        let timed = events.filter(\.isTimed)
            .sorted { ($0.minutes ?? 0) < ($1.minutes ?? 0) }
        return untimed + timed
    }

    /// Index of the first event at or after `minutes`, within an already sorted
    /// list. Untimed events are never "next".
    static func nextUpIndex(in sorted: [CalEvent], atOrAfter minutes: Int) -> Int? {
        sorted.firstIndex { ($0.minutes ?? -1) >= minutes }
    }
}
