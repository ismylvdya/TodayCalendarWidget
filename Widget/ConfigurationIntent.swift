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

// MARK: - Настройки виджета

struct DayConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Triple Today"
    static var description = IntentDescription("Calendars and timeline bounds.")

    @Parameter(title: "Calendars to show", description: "Empty means all calendars")
    var calendars: [CalendarEntity]?

    @Parameter(title: "Hide past events in calendars")
    var hidePastCalendars: [CalendarEntity]?

    @Parameter(title: "Dim past events", default: false)
    var dimPast: Bool

    @Parameter(title: "Day start", default: 6, inclusiveRange: (0, 24))
    var dayStart: Int

    @Parameter(title: "Column 1 end", default: 12, inclusiveRange: (0, 24))
    var split1: Int

    @Parameter(title: "Column 2 end", default: 18, inclusiveRange: (0, 24))
    var split2: Int

    @Parameter(title: "Day end", description: "0 or 24 means midnight", default: 24, inclusiveRange: (0, 24))
    var dayEnd: Int

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$calendars
            \.$hidePastCalendars
            \.$dimPast
            \.$dayStart
            \.$split1
            \.$split2
            \.$dayEnd
        }
    }

    var dayConfig: DayConfig {
        var c = DayConfig()
        c.columns = DayConfig.columns([dayStart, split1, split2, dayEnd])
        if let calendars, !calendars.isEmpty { c.calendarIDs = Set(calendars.map(\.id)) }
        c.hidePastCalendarIDs = Set((hidePastCalendars ?? []).map(\.id))
        c.dimPastEvents = dimPast
        return c
    }
}
