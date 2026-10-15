import EventKit
import Foundation

/// Настройки отображения дня.
struct DayConfig {
    /// Границы таймлайна в часах (0...24); колонки делят этот промежуток поровну.
    /// Конец раньше начала означает следующие сутки: 9 → 2 — с 9:00 до 2:00 ночи.
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

    /// Границы дня в минутах от начала суток; конец может быть больше 24 часов.
    /// Начало и конец должны различаться (0 → 24 — целые сутки); иначе 6:00–24:00.
    var bounds: (start: Int, end: Int) {
        guard (0...24).contains(dayStart), (0...24).contains(dayEnd) else { return (6 * 60, 24 * 60) }
        let start = dayStart % 24
        let end = dayEnd > start ? dayEnd : dayEnd + 24
        if end - start >= 24 && !(start == 0 && dayEnd == 24) { return (6 * 60, 24 * 60) }
        return (start * 60, end * 60)
    }

    /// Делит день на `count` колонок поровну (в минутах от начала суток). Границы
    /// округляются вниз до часа; если часов меньше, чем колонок, — до минуты.
    func columns(count: Int) -> [(start: Int, end: Int)] {
        let (start, end) = bounds
        let hours = (end - start) / 60
        let b = (0...count).map { hours >= count ? start + hours * $0 / count * 60 : start + (end - start) * $0 / count }
        return zip(b, b.dropFirst()).map { ($0, $1) }
    }

    /// Начало суток, к которым относится момент `now`. Если день заходит за полночь
    /// и сейчас ещё его ночной хвост, это вчерашние сутки.
    func anchor(for now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tailEnd = cal.date(byAdding: .minute, value: max(bounds.end - 24 * 60, 0), to: today)!
        return now < tailEnd ? cal.date(byAdding: .day, value: -1, to: today)! : today
    }

    /// Момент `minute` минут от начала суток `anchor`.
    static func date(minute: Int, anchor: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute, to: anchor)!
    }

    /// Промежуток, за который нужны события: сутки дня плюс ночной хвост, если он есть.
    func fetchRange(anchor: Date) -> (from: Date, to: Date) {
        (anchor, Self.date(minute: max(bounds.end, 24 * 60), anchor: anchor))
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

    /// События дня с началом суток `anchor`: обычные — пересекающие `from...to`,
    /// all-day — только самих суток `anchor` (не завтрашние из ночного хвоста).
    static func events(store: EKEventStore, anchor: Date, from: Date, to: Date, calendarIDs: Set<String>? = nil) -> [DayEvent] {
        let anchorEnd = Calendar.current.date(byAdding: .day, value: 1, to: anchor)!
        return fetch(store: store, from: from, to: to, calendarIDs: calendarIDs)
            .filter { !$0.isAllDay || ($0.start < anchorEnd && $0.end > anchor) }
    }

    /// События сегодня и завтра — для отслеживания изменений.
    static func upcomingEvents(store: EKEventStore, now: Date = Date()) -> [DayEvent] {
        let today = Calendar.current.startOfDay(for: now)
        return fetch(store: store, from: today, to: Calendar.current.date(byAdding: .day, value: 2, to: today)!, calendarIDs: nil)
    }

    private static func fetch(store: EKEventStore, from dayStart: Date, to dayEnd: Date, calendarIDs: Set<String>?) -> [DayEvent] {
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

    static func rgb(of color: CGColor?) -> [Double] {
        guard let color,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let c = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3
        else { return [0.4, 0.55, 1.0] }
        return comps.prefix(3).map(Double.init)
    }
}
