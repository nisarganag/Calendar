import Foundation
import SwiftUI
import ServiceManagement

struct DayCell: Identifiable {
    let id: String
    let date: Date?
    let isInCurrentMonth: Bool
    let dayNumber: Int
    let hasEvents: Bool
}

enum EventStore {
    private static let storageKey = "CalBar.events.v1"
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }

    static func load() -> [String: [String]] {
        (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [String]]) ?? [:]
    }

    static func save(_ events: [String: [String]]) {
        UserDefaults.standard.set(events, forKey: storageKey)
    }
}

extension Date {
    func startOfMonth(using calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: self)) ?? self
    }
}

final class CalendarViewModel: ObservableObject {
    /// How long a browsed month survives after the panel is closed (or the app quits).
    static let reopenGracePeriod: TimeInterval = 10

    private static let kDisplayedMonth = "CalBar.displayedMonth"
    private static let kSelectedDate = "CalBar.selectedDate"
    private static let kContextSavedAt = "CalBar.contextSavedAt"

    @Published var displayedMonth: Date
    @Published var selectedDate: Date
    @Published var today: Date
    @Published var days: [DayCell] = []
    @Published var weekStartsMonday: Bool {
        didSet {
            UserDefaults.standard.set(weekStartsMonday, forKey: "CalBar.weekStartsMonday")
            rebuild()
        }
    }
    @Published var launchAtLogin: Bool = false
    @Published var eventsByDay: [String: [String]] {
        didSet { EventStore.save(eventsByDay) }
    }
    @Published var draftEvent: String = ""

    // MARK: Go to date
    @Published var showGoToDate: Bool = false
    @Published var gotoMonth: Int {  // 0-based index into monthSymbols
        didSet { clampGotoDay() }
    }
    @Published var gotoYear: Int {
        didSet { clampGotoDay() }
    }
    @Published var gotoDay: Int

    private let calendar = Calendar.current

    init() {
        let now = Date()
        today = now
        selectedDate = now
        displayedMonth = now.startOfMonth(using: calendar)
        weekStartsMonday = UserDefaults.standard.object(forKey: "CalBar.weekStartsMonday") as? Bool ?? true
        eventsByDay = EventStore.load()
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        gotoYear = comps.year ?? 2026
        gotoMonth = (comps.month ?? 1) - 1
        gotoDay = comps.day ?? 1
        rebuild()
        restoreRecentContextIfFresh()
    }

    // MARK: - Close-time grace window

    private var contextSavedDate: Date {
        let ts = UserDefaults.standard.double(forKey: Self.kContextSavedAt)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }

    /// Persists the browsed context, stamped with the moment the panel was
    /// closed (or the app quit). The grace window counts from this moment.
    func saveContext() {
        UserDefaults.standard.set(displayedMonth.timeIntervalSince1970, forKey: Self.kDisplayedMonth)
        UserDefaults.standard.set(selectedDate.timeIntervalSince1970, forKey: Self.kSelectedDate)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.kContextSavedAt)
    }

    private func restoreRecentContextIfFresh() {
        guard Date().timeIntervalSince(contextSavedDate) < Self.reopenGracePeriod,
              let monthTS = UserDefaults.standard.object(forKey: Self.kDisplayedMonth) as? TimeInterval,
              let selectedTS = UserDefaults.standard.object(forKey: Self.kSelectedDate) as? TimeInterval
        else { return }
        displayedMonth = Date(timeIntervalSince1970: monthTS).startOfMonth(using: calendar)
        selectedDate = Date(timeIntervalSince1970: selectedTS)
        rebuild()
    }

    /// Called right before the panel opens. The panel is always restored
    /// exactly as it was left; only after the grace window has elapsed since
    /// it was last closed does it snap back to today.
    func prepareForPopoverOpen() {
        refreshDayIfNeeded()
        if Date().timeIntervalSince(contextSavedDate) >= Self.reopenGracePeriod {
            resetToTodayIfAway()
        }
    }

    private func resetToTodayIfAway() {
        let todayMonth = today.startOfMonth(using: calendar)
        if !calendar.isDate(displayedMonth, equalTo: todayMonth, toGranularity: .month)
            || !calendar.isDate(selectedDate, inSameDayAs: today) {
            displayedMonth = todayMonth
            selectedDate = today
            rebuild()
        }
    }

    // MARK: - Grid

    func rebuild() {
        days = makeDays()
    }

    private func makeDays() -> [DayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)
        else { return [] }

        let anchor: Int = weekStartsMonday ? 2 : 1
        let leading = (calendar.component(.weekday, from: monthInterval.start) - anchor + 7) % 7
        var result: [DayCell] = []

        if leading > 0,
           let prevStart = calendar.date(byAdding: .day, value: -leading, to: monthInterval.start) {
            for i in 0..<leading {
                if let d = calendar.date(byAdding: .day, value: i, to: prevStart) {
                    result.append(cell(for: d, inMonth: false))
                }
            }
        }
        for i in 0..<daysInMonth.count {
            if let d = calendar.date(byAdding: .day, value: i, to: monthInterval.start) {
                result.append(cell(for: d, inMonth: true))
            }
        }
        let remaining = 42 - result.count
        if remaining > 0,
           let nextStart = calendar.date(byAdding: .day, value: daysInMonth.count, to: monthInterval.start) {
            for i in 0..<remaining {
                if let d = calendar.date(byAdding: .day, value: i, to: nextStart) {
                    result.append(cell(for: d, inMonth: false))
                }
            }
        }
        return result
    }

    private func cell(for date: Date, inMonth inCurrentMonth: Bool) -> DayCell {
        let key = EventStore.key(for: date)
        return DayCell(
            id: key,
            date: date,
            isInCurrentMonth: inCurrentMonth,
            dayNumber: calendar.component(.day, from: date),
            hasEvents: !(eventsByDay[key]?.isEmpty ?? true)
        )
    }

    var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return weekStartsMonday ? Array(symbols[1...]) + [symbols[0]] : symbols
    }

    // MARK: - Navigation & selection

    func moveMonth(_ delta: Int) {
        guard let m = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = m.startOfMonth(using: calendar)
        rebuild()
    }

    func goToday() {
        today = Date()
        selectedDate = today
        displayedMonth = today.startOfMonth(using: calendar)
        rebuild()
    }

    func select(_ date: Date) {
        selectedDate = date
    }

    func isSelected(_ c: DayCell) -> Bool {
        c.date.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false
    }

    func isToday(_ c: DayCell) -> Bool {
        c.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false
    }

    func refreshDayIfNeeded() {
        let now = Date()
        guard !calendar.isDate(now, inSameDayAs: today) else { return }
        today = now
        selectedDate = now
        displayedMonth = now.startOfMonth(using: calendar)
        rebuild()
    }

    // MARK: - Go to date

    var gotoMonthSymbols: [String] { calendar.monthSymbols }

    var gotoDaysInMonth: Int {
        var comps = DateComponents()
        comps.year = gotoYear
        comps.month = gotoMonth + 1
        let probe = calendar.date(from: comps) ?? Date()
        return calendar.range(of: .day, in: .month, for: probe)?.count ?? 30
    }

    private func clampGotoDay() {
        if gotoDay > gotoDaysInMonth { gotoDay = gotoDaysInMonth }
    }

    func openGoToDate() {
        let c = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        gotoYear = c.year ?? gotoYear
        gotoMonth = (c.month ?? 1) - 1
        gotoDay = c.day ?? 1
        showGoToDate = true
    }

    func applyGoToDate() {
        var comps = DateComponents()
        comps.year = gotoYear
        comps.month = gotoMonth + 1
        comps.day = gotoDay
        if let d = calendar.date(from: comps) {
            selectedDate = d
            displayedMonth = d.startOfMonth(using: calendar)
            rebuild()
        }
        showGoToDate = false
    }

    // MARK: - Events

    var selectedEvents: [String] {
        eventsByDay[EventStore.key(for: selectedDate)] ?? []
    }

    var selectedDayTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        return f.string(from: selectedDate)
    }

    func addDraftEvent() {
        let text = draftEvent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let key = EventStore.key(for: selectedDate)
        eventsByDay[key, default: []].append(text)
        draftEvent = ""
    }

    func removeEvents(at offsets: IndexSet) {
        let key = EventStore.key(for: selectedDate)
        eventsByDay[key]?.remove(atOffsets: offsets)
        if eventsByDay[key]?.isEmpty == true {
            eventsByDay.removeValue(forKey: key)
        }
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                switch (enabled, service.status) {
                case (true, .enabled):
                    break
                case (true, _):
                    try service.register()
                case (false, .enabled):
                    try service.unregister()
                case (false, _):
                    break
                }
            } catch {
                NSLog("CalBar: login item operation failed: \(error)")
            }
            syncLaunchAtLoginStatus(registerIfRequested: false)
        }
    }

    func syncLaunchAtLoginStatus(registerIfRequested: Bool = true) {
        if #available(macOS 13.0, *) {
            let pref = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
            let service = SMAppService.mainApp
            if pref, registerIfRequested, service.status != .enabled {
                try? service.register()
            }
            launchAtLogin = (service.status == .enabled)
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        }
    }
}
