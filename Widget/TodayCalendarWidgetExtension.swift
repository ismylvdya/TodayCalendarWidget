import EventKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    let date: Date
    let events: [DayEvent]
    let hasAccess: Bool
    var config = DayConfig()
    /// Когда виджет последний раз прочитал календарь (nil — данные-заглушка).
    var fetchedAt: Date? = nil

    /// События, которые видны в момент `date`: без all-day, если они скрыты,
    /// и без прошедших из «скрываемых» календарей.
    var visibleEvents: [DayEvent] {
        events.filter {
            !(config.hideAllDay && $0.isAllDay)
                && !(config.hidePastCalendarIDs.contains($0.calendarID) && $0.end <= date)
        }
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), events: SampleData.events, hasAccess: true)
    }

    func snapshot(for configuration: DayConfigurationIntent, in context: Context) async -> DayEntry {
        let now = Date()
        let config = configuration.dayConfig
        if CalendarData.hasAccess {
            let events = CalendarData.todayEvents(store: EKEventStore(), now: now, calendarIDs: config.calendarIDs)
            return DayEntry(date: now, events: events, hasAccess: true, config: config, fetchedAt: now)
        }
        return DayEntry(date: now, events: SampleData.events, hasAccess: context.isPreview, config: config)
    }

    /// Кадры на каждую минуту в течение часа — двигается только курсор.
    func timeline(for configuration: DayConfigurationIntent, in context: Context) async -> Timeline<DayEntry> {
        let now = Date()
        let cal = Calendar.current
        let config = configuration.dayConfig
        let hasAccess = CalendarData.hasAccess
        let events = hasAccess ? CalendarData.todayEvents(store: EKEventStore(), now: now, calendarIDs: config.calendarIDs) : []
        let minuteStart = cal.dateInterval(of: .minute, for: now)?.start ?? now
        let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!

        var entries = [DayEntry(date: now, events: events, hasAccess: hasAccess, config: config, fetchedAt: now)]
        for i in 1...60 {
            let d = minuteStart.addingTimeInterval(Double(i) * 60)
            if d >= nextDay { break }
            entries.append(DayEntry(date: d, events: events, hasAccess: hasAccess, config: config, fetchedAt: now))
        }
        let reloadAt = min(entries.last!.date.addingTimeInterval(60), nextDay)
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

// MARK: - Layout helpers

/// Событие, обрезанное по колонке, с номером дорожки при пересечениях.
struct PlacedEvent: Identifiable {
    let event: DayEvent
    let start: Date
    let end: Date
    let lane: Int
    let lanes: Int
    /// Событие начинается раньше колонки / продолжается после неё.
    var continuesBefore: Bool { event.start < start }
    var continuesAfter: Bool { event.end > end }
    var id: String { event.id }
}

enum Layout {
    static func date(hour: Int, on day: Date) -> Date {
        Calendar.current.date(byAdding: .hour, value: hour, to: Calendar.current.startOfDay(for: day))!
    }

    /// Раскладывает события колонки по дорожкам, чтобы пересекающиеся стояли рядом.
    static func place(_ events: [DayEvent], from: Date, to: Date) -> [PlacedEvent] {
        let clipped = events
            .filter { !$0.isAllDay && $0.end > from && $0.start < to }
            .map { (ev: $0, s: max($0.start, from), e: min(max($0.end, $0.start.addingTimeInterval(15 * 60)), to)) }
            .sorted { $0.s < $1.s }

        var result: [PlacedEvent] = []
        var cluster: [(ev: DayEvent, s: Date, e: Date, lane: Int)] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let lanes = (cluster.map(\.lane).max() ?? 0) + 1
            result += cluster.map { PlacedEvent(event: $0.ev, start: $0.s, end: $0.e, lane: $0.lane, lanes: lanes) }
            cluster.removeAll()
        }

        for item in clipped {
            if item.s >= clusterEnd { flush() }
            var laneEnds: [Int: Date] = [:]
            for c in cluster { laneEnds[c.lane] = max(laneEnds[c.lane] ?? .distantPast, c.e) }
            var lane = 0
            while let end = laneEnds[lane], end > item.s { lane += 1 }
            cluster.append((item.ev, item.s, item.e, lane))
            clusterEnd = max(clusterEnd, item.e)
        }
        flush()
        return result
    }
}

// MARK: - Views

struct TodayWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        DayView(entry: entry, columnCount: family == .systemLarge ? 2 : 3)
    }
}

/// Сам виджет: таймлайн дня, разбитый на `columnCount` колонок.
struct DayView: View {
    let entry: DayEntry
    let columnCount: Int
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetContentMargins) private var margins

    /// Отступ подписи синхронизации от линии конца дня и от низа виджета —
    /// такой же, как системный отступ контента справа.
    private var syncGap: CGFloat { margins.trailing > 0 ? margins.trailing : 16 }

    var body: some View {
        if !entry.hasAccess {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark").font(.title)
                Text("No calendar access").font(.headline)
                Text("Open TodayCalendarWidget and allow full calendar access.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 14) {
                let columns = entry.config.columns(count: columnCount)
                ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                    let showsSync = idx == columns.count - 1 && entry.fetchedAt != nil
                    VStack(alignment: .leading, spacing: 4) {
                        if idx == 0 {
                            AllDayList(events: entry.visibleEvents.filter(\.isAllDay), config: entry.config, mode: renderingMode)
                        }
                        ColumnView(entry: entry, startHour: col.start, endHour: col.end, mode: renderingMode)
                        // Под концом дня — давность последней синхронизации; последняя колонка сжимается.
                        // Подпись стоит у самого низа контента, от линии конца дня её отделяет тот же отступ.
                        if showsSync, let fetchedAt = entry.fetchedAt {
                            SyncLabel(fetchedAt: fetchedAt, now: entry.date)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.top, syncGap - 4 - 1)
                        }
                    }
                    // Остальным колонкам — место под подпись нижнего часа.
                    .padding(.bottom, showsSync ? 0 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}

private func eventTint(_ ev: DayEvent, _ mode: WidgetRenderingMode) -> Color {
    mode == .fullColor ? Color(red: ev.rgb[0], green: ev.rgb[1], blue: ev.rgb[2]) : .primary
}

private func isInverted(_ ev: DayEvent, _ config: DayConfig, _ mode: WidgetRenderingMode) -> Bool {
    mode != .fullColor && config.invertCalendarIDs.contains(ev.calendarID)
}

extension View {
    /// Подложка события. Обычно — полупрозрачная заливка цветом календаря.
    /// В инвертированном виде фигура залита сплошным цветом полоски, а сам контент
    /// (текст, полоска, иконка) выбит до фона — все одного цвета.
    /// `fade` — затухание заливки сверху/снизу для событий, перенесённых через границу колонок.
    @ViewBuilder
    func eventBackground<S: Shape>(_ shape: S, color: Color, opacity: Double, inverted: Bool,
                                   fade: (top: Bool, bottom: Bool) = (false, false)) -> some View {
        // Инвертированная заливка чуть прозрачнее белого, чтобы курсор оставался самым ярким.
        let fill = shape.fill(color.opacity(inverted ? 0.85 : opacity)).mask(FadeMask(top: fade.top, bottom: fade.bottom))
        if inverted {
            self.blendMode(.destinationOut)
                .background(fill)
                .compositingGroup()
                .widgetAccentable()
        } else {
            self.background(fill)
        }
    }
}

/// Маска, которая растворяет заливку к верхнему и/или нижнему краю.
struct FadeMask: View {
    let top: Bool
    let bottom: Bool
    private let length: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let f = min(length / max(geo.size.height, 1), 0.5)
            LinearGradient(stops: [
                .init(color: .black.opacity(top ? 0 : 1), location: 0),
                .init(color: .black, location: top ? f : 0),
                .init(color: .black, location: bottom ? 1 - f : 1),
                .init(color: .black.opacity(bottom ? 0 : 1), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct AllDayList: View {
    let events: [DayEvent]
    let config: DayConfig
    let mode: WidgetRenderingMode

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(events.prefix(3)) { ev in
                    HStack(spacing: 4) {
                        // Иконка в квадрате 16×16 с одинаковым отступом слева и сверху/снизу —
                        // её круг концентричен скруглению капсулы.
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(eventTint(ev, mode))
                            .frame(width: 16, height: 16)
                        Text(ev.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                        .padding(.leading, 2)
                        .padding(.trailing, 8)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .eventBackground(Capsule(), color: eventTint(ev, mode), opacity: 0.35,
                                         inverted: isInverted(ev, config, mode))
                        .widgetAccentable()
                        .opacity(config.dimCalendarIDs.contains(ev.calendarID) ? 0.55 : 1)
                }
                if events.count > 3 {
                    Text("+\(events.count - 3)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct ColumnView: View {
    let entry: DayEntry
    let startHour: Int
    let endHour: Int
    let mode: WidgetRenderingMode

    private let gutter: CGFloat = 20
    private let labelHeight: CGFloat = 12
    /// Центр кружка курсора относительно левого края колонки (левее цифр часов).
    private let cursorX: CGFloat = -5
    private let cursorDot: CGFloat = 9
    /// На сколько перенесённое событие заходит за границу колонки — до края цифр часа.
    private let overshoot: CGFloat = 7

    @Environment(\.colorScheme) private var scheme

    /// Цифры часов и линии сетки: в полноцветной тёмной теме — цвета системного Calendar,
    /// в остальных случаях — системные полутона (в монохроме их перекрашивает система).
    private var labelStyle: Color { mode == .fullColor && scheme == .dark ? Theme.darkLabel : .secondary }
    private var gridStyle: Color { mode == .fullColor && scheme == .dark ? Theme.darkGrid : .secondary.opacity(0.35) }

    var body: some View {
        GeometryReader { geo in
            let from = Layout.date(hour: startHour, on: entry.date)
            let to = Layout.date(hour: endHour, on: entry.date)
            // Сверху оставляем место под подпись первого часа.
            let top = labelHeight / 2
            let height = max(geo.size.height - top - 1, 1)
            let span = to.timeIntervalSince(from)
            let y: (Date) -> CGFloat = { top + CGFloat($0.timeIntervalSince(from) / span) * height }
            let eventsWidth = geo.size.width - gutter

            ZStack(alignment: .topLeading) {
                // Часовая сетка
                ForEach(startHour...endHour, id: \.self) { h in
                    let yy = top + CGFloat(h - startHour) / CGFloat(endHour - startHour) * height
                    Text("\(h % 24)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(labelStyle)
                        .frame(width: gutter - 4, alignment: .trailing)
                        .offset(y: yy - labelHeight / 2)
                    Rectangle()
                        .fill(gridStyle)
                        .frame(width: eventsWidth, height: 0.5)
                        .offset(x: gutter, y: yy)
                }

                // События
                ForEach(Layout.place(entry.visibleEvents, from: from, to: to)) { p in
                    let laneWidth = eventsWidth / CGFloat(p.lanes)
                    // Перенесённое событие выходит за границу колонки до края цифр часа,
                    // чтобы затухание заканчивалось (начиналось) на уровне подписи.
                    let y0 = y(p.start) - (p.continuesBefore ? overshoot : 0)
                    let y1 = y(p.end) + (p.continuesAfter ? overshoot : -1)
                    let h = max(y1 - y0, 13)
                    EventBlock(event: p.event, height: h, dimmed: entry.config.isDimmed(p.event, now: entry.date),
                               inverted: isInverted(p.event, entry.config, mode),
                               continuesBefore: p.continuesBefore, continuesAfter: p.continuesAfter, mode: mode)
                        .frame(width: laneWidth - 2, height: h)
                        .offset(x: gutter + CGFloat(p.lane) * laneWidth, y: y0 + 0.5)
                }

                // Курсор текущего момента
                if entry.date >= from && entry.date < to {
                    let yy = y(entry.date)
                    // Кружок — посередине между краем соседней колонки и цифрами часов.
                    HStack(spacing: 0) {
                        Circle().frame(width: cursorDot, height: cursorDot)
                        Rectangle().frame(height: 2.4)
                    }
                    // В монохроме яркость = светлота цвета, поэтому курсор чисто белый — ярче всего остального.
                    .foregroundStyle(mode == .fullColor ? Theme.cursor : .white)
                    .frame(width: geo.size.width - cursorX + cursorDot / 2)
                    .offset(x: cursorX - cursorDot / 2, y: yy - cursorDot / 2)
                    .widgetAccentable()
                }
            }
        }
    }
}

/// «⟳ 20 min ago» / «⟳ 2 hr ago».
struct SyncLabel: View {
    let fetchedAt: Date
    let now: Date

    private var text: String {
        let minutes = max(Int(now.timeIntervalSince(fetchedAt) / 60), 0)
        return minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) hr ago"
    }

    var body: some View {
        HStack(spacing: 4.5) {
            Image(systemName: "arrow.clockwise.icloud")
            Text(text)
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(.tertiary)
    }
}

struct EventBlock: View {
    let event: DayEvent
    let height: CGFloat
    let dimmed: Bool
    let inverted: Bool
    let continuesBefore: Bool
    let continuesAfter: Bool
    let mode: WidgetRenderingMode

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    var body: some View {
        let color = eventTint(event, mode)
        // На стыке колонок углы прямые, а полоска доходит до самого края.
        let top: CGFloat = continuesBefore ? 0 : 5, bottom: CGFloat = continuesAfter ? 0 : 5
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(height > 30 ? 2 : 1)
                if height > 34 {
                    Text(Self.timeFormat.string(from: event.start))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(inverted ? HierarchicalShapeStyle.primary : .secondary)  // при инверсии выбивается целиком, как заголовок
                }
            }
            .padding(.top, height > 16 ? 2 : 0)
            Spacer(minLength: 0)
        }
        .padding(3)
        .padding(.leading, 7)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: continuesBefore ? 0 : 1.5, bottomLeadingRadius: continuesAfter ? 0 : 1.5,
                                   bottomTrailingRadius: continuesAfter ? 0 : 1.5, topTrailingRadius: continuesBefore ? 0 : 1.5)
                .fill(color)
                .frame(width: 3)
                .padding(.leading, 3)
                .padding(.top, continuesBefore ? 0 : 3)
                .padding(.bottom, continuesAfter ? 0 : 3)
                .mask(FadeMask(top: continuesBefore, bottom: continuesAfter))
                .widgetAccentable()
        }
        .eventBackground(shape, color: color, opacity: 0.22, inverted: inverted,
                         fade: (continuesBefore, continuesAfter))
        .clipShape(shape)
        .opacity(dimmed ? 0.55 : 1)
    }
}

enum Theme {
    static let cursor = Color(red: 0xF1 / 255, green: 0x65 / 255, blue: 0x4E / 255)
    static let darkBackground = Color(white: 0x3C / 255)
    static let darkLabel = Color(white: 0xB0 / 255)
    static let darkGrid = Color(white: 0x54 / 255)
}

/// Фон виджета по теме системы: белый или тёмно-серый, как у системного Calendar.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        scheme == .dark ? Theme.darkBackground : Color.white
    }
}

// MARK: - Widget

@main
struct TodayCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayCalendarWidget", intent: DayConfigurationIntent.self, provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "todaycalendarwidget://open"))
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Triple Today")
        .description("")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: - Sample data

enum SampleData {
    static var events: [DayEvent] {
        let d = Date()
        func ev(_ title: String, _ h: Double, _ dur: Double, allDay: Bool = false) -> DayEvent {
            let s = Calendar.current.startOfDay(for: d).addingTimeInterval(h * 3600)
            return DayEvent(id: title, title: title, start: s, end: s.addingTimeInterval(dur * 3600),
                            isAllDay: allDay, calendarID: "sample", rgb: [0.45, 0.6, 1.0])
        }
        return [
            ev("pay bills", 0, 24, allDay: true),
            ev("workout", 7.5, 0.5),
            ev("call", 10, 1),
            ev("meeting", 12, 3),
            ev("call mom", 18, 0.5),
            ev("market?", 19, 1),
        ]
    }
}

#Preview(as: .systemExtraLarge) {
    TodayCalendarWidget()
} timeline: {
    DayEntry(date: Date(), events: SampleData.events, hasAccess: true)
}
