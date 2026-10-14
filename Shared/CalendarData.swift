import EventKit
import Foundation

/// Настройки отображения дня (часы, 24 = полночь). Значения по умолчанию — 6–12–18–24.
struct DayConfig {
    var columns: [(start: Int, end: Int)] = [(6, 12), (12, 18), (18, 24)]
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

    func isDimmed(_ ev: DayEvent, now: Date) -> Bool {
        dimCalendarIDs.contains(ev.calendarID) || (dimPastEvents && ev.end <= now)
    }

    /// Границы четырьмя числами в 0...24, 0 в конце = полночь (24).
    /// Если они не строго по возрастанию, остаются значения по умолчанию.
    static func columns(_ bounds: [Int]) -> [(start: Int, end: Int)] {
        var b = bounds
        if b.last == 0 { b[b.count - 1] = 24 }
        guard b.count == 4, b.allSatisfy({ (0...24).contains($0) }), zip(b, b.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return DayConfig().columns
        }
        return [(b[0], b[1]), (b[1], b[2]), (b[2], b[3])]
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
