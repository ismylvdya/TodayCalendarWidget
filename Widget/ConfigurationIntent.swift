import AppIntents
import EventKit
import WidgetKit

// MARK: - Календарь как параметр настроек

struct CalendarEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar"
    static var defaultQuery = CalendarQuery()

    let id: String
    let title: String
    let source: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(source)")
    }
}

struct CalendarQuery: EntityQuery {
    private func all() -> [CalendarEntity] {
        EKEventStore().calendars(for: .event)
            .map { CalendarEntity(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    func entities(for identifiers: [String]) async throws -> [CalendarEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CalendarEntity] {
        all()
    }
}

// MARK: - Час как параметр настроек

/// Час, который в панели настроек показывается как «6:00» вместо голого числа.
enum Hour: Int, AppEnum {
    case h0 = 0
    case h1 = 1
    case h2 = 2
    case h3 = 3
    case h4 = 4
    case h5 = 5
    case h6 = 6
    case h7 = 7
    case h8 = 8
    case h9 = 9
    case h10 = 10
    case h11 = 11
    case h12 = 12
    case h13 = 13
    case h14 = 14
    case h15 = 15
    case h16 = 16
    case h17 = 17
    case h18 = 18
    case h19 = 19
    case h20 = 20
    case h21 = 21
    case h22 = 22
    case h23 = 23
    case h24 = 24

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Hour"
    static var caseDisplayRepresentations: [Hour: DisplayRepresentation] = [
        .h0: "0:00",
        .h1: "1:00",
        .h2: "2:00",
        .h3: "3:00",
        .h4: "4:00",
        .h5: "5:00",
        .h6: "6:00",
        .h7: "7:00",
        .h8: "8:00",
        .h9: "9:00",
        .h10: "10:00",
        .h11: "11:00",
        .h12: "12:00",
        .h13: "13:00",
        .h14: "14:00",
        .h15: "15:00",
        .h16: "16:00",
        .h17: "17:00",
        .h18: "18:00",
        .h19: "19:00",
        .h20: "20:00",
        .h21: "21:00",
        .h22: "22:00",
        .h23: "23:00",
        .h24: "24:00",
    ]
}

// MARK: - Настройки виджета

/// Порядок параметров повторяет группы: календари, таймлайн, внешний вид.
/// Панель «Изменить виджет» не умеет заголовки групп и отступы между ними.
struct DayConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Triple Today"
    static var description = IntentDescription("Calendars and day bounds.")

    @Parameter(title: "Calendars to show", description: "Empty means all calendars")
    var calendars: [CalendarEntity]?

    // Timeline
    @Parameter(title: "Day start", default: .h6)
    var dayStartHour: Hour

    @Parameter(title: "Day end", description: "Earlier than Day start means the next day", default: .h24)
    var dayEndHour: Hour

    @Parameter(title: "Hide All-day Events", default: false)
    var hideAllDay: Bool

    @Parameter(title: "Calendars to hide past events")
    var hidePastCalendars: [CalendarEntity]?

    // Appearance
    @Parameter(title: "Dim past events for all calendars", default: false)
    var dimPast: Bool

    @Parameter(title: "Calendars to invert colors (for monochrome mode)")
    var invertCalendars: [CalendarEntity]?

    @Parameter(title: "Calendars with dim events")
    var dimCalendars: [CalendarEntity]?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$calendars
            \.$dayStartHour
            \.$dayEndHour
            \.$hideAllDay
            \.$hidePastCalendars
            \.$dimPast
            \.$invertCalendars
            \.$dimCalendars
        }
    }

    var dayConfig: DayConfig {
        var c = DayConfig()
        c.dayStart = dayStartHour.rawValue
        c.dayEnd = dayEndHour.rawValue
        if let calendars, !calendars.isEmpty { c.calendarIDs = Set(calendars.map(\.id)) }
        c.hidePastCalendarIDs = Set((hidePastCalendars ?? []).map(\.id))
        c.invertCalendarIDs = Set((invertCalendars ?? []).map(\.id))
        c.dimCalendarIDs = Set((dimCalendars ?? []).map(\.id))
        c.hideAllDay = hideAllDay
        c.dimPastEvents = dimPast
        return c
    }
}
