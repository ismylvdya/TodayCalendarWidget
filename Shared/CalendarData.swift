import EventKit
import Foundation

/// Настройки отображения дня (часы, 24 = полночь).
struct DayConfig {
    /// Границы таймлайна; колонки делят этот промежуток поровну.
    var dayStart = 6
    var dayEnd = 24
    /// nil — все календари.
    var calendarIDs: Set<String>? = nil
    /// Календари, чьи события исчезают из виджета, когда закончились.
    var hidePastCalendarIDs: Set<String> = []
    /// Календари, чьи события в монохроме рисуются инвертированно (сплошная заливка).
    var invertCalendarIDs: Set<String> = []
    /// All-day события не показываются вовсе.
    var hideAllDay = false
    /// Прошедшие события чуть приглушаются во всех календарях.
    var dimPastEvents = false
    /// Календари, чьи события (включая all-day) приглушены всегда.
    var dimCalendarIDs: Set<String> = []

    /// Делит день на `count` колонок поровну; дробные границы округляются вниз.
    /// Конец дня 0 = полночь (24). Если промежуток короче числа колонок или
    /// конец не позже начала, берётся 6–24.
    func columns(count: Int) -> [(start: Int, end: Int)] {
        var (start, end) = (dayStart, dayEnd == 0 ? 24 : dayEnd)
        if !(0...24).contains(start) || !(0...24).contains(end) || end - start < count { (start, end) = (6, 24) }
        let b = (0...count).map { start + (end - start) * $0 / count }
        return zip(b, b.dropFirst()).map { ($0, $1) }
    }

    func isDimmed(_ ev: DayEvent, now: Date) -> Bool {
        dimCalendarIDs.contains(ev.calendarID) || (dimPastEvents && ev.end <= now)
    }
}

struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    /// sRGB-компоненты цвета календаря.
    let rgb: [Double]
}

enum CalendarData {
    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func todayEvents(store: EKEventStore, now: Date = Date(), calendarIDs: Set<String>? = nil) -> [DayEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let calendars = calendarIDs.map { ids in store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) } }
        if let calendars, calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { ev in
                DayEvent(
                    id: "\(ev.eventIdentifier ?? UUID().uuidString)|\(ev.startDate.timeIntervalSince1970)",
                    title: ev.title ?? "",
                    start: ev.startDate,
                    end: ev.endDate,
                    isAllDay: ev.isAllDay,
                    calendarID: ev.calendar.calendarIdentifier,
                    rgb: rgb(of: ev.calendar.cgColor)
                )
            }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// Отпечаток дня: меняется, если поменялось хоть одно событие или наступил новый день.
    static func fingerprint(_ events: [DayEvent], now: Date = Date()) -> String {
        let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        return "\(day);" + events.map { "\($0.id)|\($0.title)|\($0.end.timeIntervalSince1970)|\($0.isAllDay)|\($0.rgb)" }
            .joined(separator: ";")
    }

    private static func rgb(of color: CGColor?) -> [Double] {
        guard let color,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let c = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3
        else { return [0.4, 0.55, 1.0] }
        return comps.prefix(3).map(Double.init)
    }
}
