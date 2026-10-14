import EventKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    let date: Date
    let events: [DayEvent]
    let hasAccess: Bool
    var config = DayConfig()

    /// События, которые видны в момент `date`: прошедшие из «скрываемых» календарей убраны.
    var visibleEvents: [DayEvent] {
        events.filter { !(config.hidePastCalendarIDs.contains($0.calendarID) && $0.end <= date) }
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
            return DayEntry(date: now, events: events, hasAccess: true, config: config)
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

        var entries = [DayEntry(date: now, events: events, hasAccess: hasAccess, config: config)]
        for i in 1...60 {
            let d = minuteStart.addingTimeInterval(Double(i) * 60)
            if d >= nextDay { break }
            entries.append(DayEntry(date: d, events: events, hasAccess: hasAccess, config: config))
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
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // Полноцветный режим — светлая тема как у системного Calendar; в монохроме цвета задаёт система.
        content.environment(\.colorScheme, renderingMode == .fullColor ? .light : colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder private var content: some View {
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
                ForEach(Array(entry.config.columns.enumerated()), id: \.offset) { idx, col in
                    VStack(alignment: .leading, spacing: 4) {
                        if idx == 0 {
                            AllDayList(events: entry.visibleEvents.filter(\.isAllDay), mode: renderingMode)
                        }
                        ColumnView(entry: entry, startHour: col.start, endHour: col.end, mode: renderingMode)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}

private func eventTint(_ ev: DayEvent, _ mode: WidgetRenderingMode) -> Color {
    mode == .fullColor ? Color(red: ev.rgb[0], green: ev.rgb[1], blue: ev.rgb[2]) : .primary
}

struct AllDayList: View {
    let events: [DayEvent]
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
                        .background(Capsule().fill(eventTint(ev, mode).opacity(0.35)))
                        .widgetAccentable()
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
                        .foregroundStyle(.secondary)
                        .frame(width: gutter - 4, alignment: .trailing)
                        .offset(y: yy - labelHeight / 2)
                    Rectangle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: eventsWidth, height: 0.5)
                        .offset(x: gutter, y: yy)
                }

                // События
                ForEach(Layout.place(entry.visibleEvents, from: from, to: to)) { p in
                    let laneWidth = eventsWidth / CGFloat(p.lanes)
                    let y0 = y(p.start)
                    let h = max(y(p.end) - y0 - 1, 13)
                    EventBlock(event: p.event, height: h, isPast: entry.config.dimPastEvents && p.event.end <= entry.date, mode: mode)
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
                    .foregroundStyle(Theme.cursor)
                    .frame(width: geo.size.width - cursorX + cursorDot / 2)
                    .offset(x: cursorX - cursorDot / 2, y: yy - cursorDot / 2)
                    .widgetAccentable()
                }
            }
        }
    }
}

struct EventBlock: View {
    let event: DayEvent
    let height: CGFloat
    let isPast: Bool
    let mode: WidgetRenderingMode

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    var body: some View {
        let color = eventTint(event, mode)
        HStack(alignment: .top, spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(height > 30 ? 2 : 1)
                if height > 34 {
                    Text(Self.timeFormat.string(from: event.start))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, height > 16 ? 2 : 0)
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.22)))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(isPast ? 0.55 : 1)
    }
}

enum Theme {
    static let background = Color.white
    static let cursor = Color(red: 0xF1 / 255, green: 0x65 / 255, blue: 0x4E / 255)
}

// MARK: - Widget

@main
struct TodayCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayCalendarWidget", intent: DayConfigurationIntent.self, provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "todaycalendarwidget://open"))
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName("Triple Today")
        .description("")
        .supportedFamilies([.systemExtraLarge])
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
