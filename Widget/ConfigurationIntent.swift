import AppIntents
import EventKit
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

// MARK: - Календарь как параметр настроек

struct CalendarEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar"
    static var defaultQuery = CalendarQuery()

    let id: String
    let title: String
    let source: String
    /// sRGB-цвет календаря — кружок перед названием в настройках.
    let rgb: [Double]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(source)",
                              image: ColorDot.png(rgb).map { .init(data: $0, isTemplate: false) })
    }

    static func all() -> [CalendarEntity] {
        EKEventStore().calendars(for: .event)
            .map { CalendarEntity(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title,
                                  rgb: CalendarData.rgb(of: $0.cgColor)) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }
}

struct CalendarQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CalendarEntity] {
        CalendarEntity.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CalendarEntity] {
        CalendarEntity.all()
    }
}

/// Варианты для настроек, уточняющих отображение: только календари из «Calendars to show»
/// (если там пусто — все).
struct ShownCalendarsOptions: DynamicOptionsProvider {
    @IntentParameterDependency<DayConfigurationIntent>(\.$calendars) var intent

    func results() async throws -> [CalendarEntity] {
        let all = CalendarEntity.all()
        guard let shown = intent?.calendars, !shown.isEmpty else { return all }
        let ids = Set(shown.map(\.id))
        return all.filter { ids.contains($0.id) }
    }
}

/// Цветной кружок календаря в виде PNG.
enum ColorDot {
    static func png(_ rgb: [Double]) -> Data? {
        let size = 64
        guard rgb.count >= 3,
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: size - 8, height: size - 8))
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

// MARK: - Час как параметр настроек

/// Час, который в панели настроек показывается как «6:00» вместо голого числа.
/// «Default» — интервал из настроек приложения.
enum Hour: Int, AppEnum {
    case appDefault = -1
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
        .appDefault: "Default",
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
    @Parameter(title: "Day start", description: "Default is set in the app's Calendar Settings", default: .appDefault)
    var dayStartHour: Hour

    @Parameter(title: "Day end", description: "Earlier than Day start means the next day", default: .appDefault)
    var dayEndHour: Hour

    @Parameter(title: "Hide All-day Events", default: false)
    var hideAllDay: Bool

    @Parameter(title: "Edge without margin", description: "To stack widgets one under another without a gap", default: .none)
    var noMarginEdge: MarginEdgeOption

    @Parameter(title: "Calendars to hide past events", optionsProvider: ShownCalendarsOptions())
    var hidePastCalendars: [CalendarEntity]?

    // Appearance
    @Parameter(title: "Dim past events for all calendars", default: false)
    var dimPast: Bool

    @Parameter(title: "Calendars to invert colors (for monochrome mode)", optionsProvider: ShownCalendarsOptions())
    var invertCalendars: [CalendarEntity]?

    @Parameter(title: "Calendars with dim events", optionsProvider: ShownCalendarsOptions())
    var dimCalendars: [CalendarEntity]?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$calendars
            \.$dayStartHour
            \.$dayEndHour
            \.$noMarginEdge
            \.$hideAllDay
            \.$hidePastCalendars
            \.$dimPast
            \.$invertCalendars
            \.$dimCalendars
        }
    }

    var dayConfig: DayConfig {
        var c = DayConfig()
        c.dayStart = dayStartHour == .appDefault ? CalendarSettings.defaultDayStart : dayStartHour.rawValue
        c.dayEnd = dayEndHour == .appDefault ? CalendarSettings.defaultDayEnd : dayEndHour.rawValue
        if let calendars, !calendars.isEmpty { c.calendarIDs = Set(calendars.map(\.id)) }
        c.hidePastCalendarIDs = Set((hidePastCalendars ?? []).map(\.id))
        c.invertCalendarIDs = Set((invertCalendars ?? []).map(\.id))
        c.dimCalendarIDs = Set((dimCalendars ?? []).map(\.id))
        c.hideAllDay = hideAllDay
        c.dimPastEvents = dimPast
        c.edgeWithoutMargin = MarginEdge(rawValue: noMarginEdge.rawValue) ?? .none
        return c
    }
}

/// Край виджета без отступа — выбор в настройках виджета.
enum MarginEdgeOption: Int, AppEnum {
    case none = 0
    case top = 1
    case bottom = 2

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Edge"
    static var caseDisplayRepresentations: [MarginEdgeOption: DisplayRepresentation] = [
        .none: "None", .top: "Top", .bottom: "Bottom",
    ]
}
