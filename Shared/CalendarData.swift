import EventKit
import Foundation

/// Границы дня и деление на три колонки (часы, 24 = полночь).
enum DayConfig {
    static let columns: [(start: Int, end: Int)] = [(6, 12), (12, 18), (18, 24)]
    /// Прошедшие события чуть приглушаются (false — рисовать как остальные).
    static let dimPastEvents = true
}

struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// sRGB-компоненты цвета календаря.
    let rgb: [Double]
}

enum CalendarData {
    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func todayEvents(store: EKEventStore, now: Date = Date()) -> [DayEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { ev in
                DayEvent(
                    id: "\(ev.eventIdentifier ?? UUID().uuidString)|\(ev.startDate.timeIntervalSince1970)",
                    title: ev.title ?? "",
                    start: ev.startDate,
                    end: ev.endDate,
                    isAllDay: ev.isAllDay,
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
