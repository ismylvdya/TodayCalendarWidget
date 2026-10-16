import AppIntents
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

    /// Начало суток, которые показывает виджет (с учётом дня, заходящего за полночь).
    var anchor: Date { config.anchor(for: date) }

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
            let events = Self.events(config: config, now: now)
            return DayEntry(date: now, events: events, hasAccess: true, config: config, fetchedAt: now)
        }
        return DayEntry(date: now, events: SampleData.events, hasAccess: context.isPreview, config: config)
    }

    /// Кадры на каждую минуту в течение часа — двигается только курсор. Перечитать календарь
    /// просим через 15 минут; если система откажет, кадров хватит ещё на час.
    func timeline(for configuration: DayConfigurationIntent, in context: Context) async -> Timeline<DayEntry> {
        let now = Date()
        let cal = Calendar.current
        let config = configuration.dayConfig
        let hasAccess = CalendarData.hasAccess
        let events = hasAccess ? Self.events(config: config, now: now) : []
        #if os(iOS)
        // Каждое обновление виджета заодно обновляет уведомления для событий с alert.
        await AlertScheduler.sync(now: now)
        #endif
        let minuteStart = cal.dateInterval(of: .minute, for: now)?.start ?? now
        // Следующие сутки начинаются, когда закончились текущие (с ночным хвостом).
        let nextDay = config.fetchRange(anchor: config.anchor(for: now)).to

        var entries = [DayEntry(date: now, events: events, hasAccess: hasAccess, config: config, fetchedAt: now)]
        for i in 1...60 {
            let d = minuteStart.addingTimeInterval(Double(i) * 60)
            if d >= nextDay { break }
            entries.append(DayEntry(date: d, events: events, hasAccess: hasAccess, config: config, fetchedAt: now))
        }
        let reloadAt = min(now.addingTimeInterval(15 * 60), nextDay)
        return Timeline(entries: entries, policy: .after(reloadAt))
    }

    private static func events(config: DayConfig, now: Date) -> [DayEvent] {
        let anchor = config.anchor(for: now)
        let range = config.fetchRange(anchor: anchor)
        return CalendarData.events(store: EKEventStore(), anchor: anchor, from: range.from, to: range.to,
                                   calendarIDs: config.calendarIDs)
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
    let continuesBefore: Bool
    let continuesAfter: Bool
    var id: String { event.id }
}

enum Layout {
    static let columnSpacing: CGFloat = 14
    /// Где начинается видимая часть двузначной подписи часа (10 pt, правый край на 16 pt)
    /// относительно левого края колонки. По ней выравниваются all-day плашки.
    static let labelInset: CGFloat = 3.7
    /// Видимая ширина двузначной подписи часа.
    static let labelWidth: CGFloat = 11.5


    /// Раскладывает события колонки по дорожкам, чтобы пересекающиеся стояли рядом.
    static func place(_ events: [DayEvent], from: Date, to: Date) -> [PlacedEvent] {
        let clipped = events
            .filter { !$0.isAllDay && $0.end > from && $0.start < to }
            .map { ev -> (ev: DayEvent, s: Date, e: Date) in
                // Короче 30 минут — показываем получасовым слотом, в который попадает начало
                // (17:45–18:00 → 17:30–18:00); не короче — как есть.
                guard ev.end.timeIntervalSince(ev.start) < 30 * 60 else { return (ev, max(ev.start, from), min(ev.end, to)) }
                let cal = Calendar.current
                var parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: ev.start)
                parts.minute = (parts.minute ?? 0) / 30 * 30
                let slot = cal.date(from: parts) ?? ev.start
                return (ev, max(slot, from), min(slot.addingTimeInterval(30 * 60), to))
            }
            .sorted { $0.s < $1.s }

        var result: [PlacedEvent] = []
        var cluster: [(ev: DayEvent, s: Date, e: Date, lane: Int)] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let lanes = (cluster.map(\.lane).max() ?? 0) + 1
            result += cluster.map { PlacedEvent(event: $0.ev, start: $0.s, end: $0.e, lane: $0.lane, lanes: lanes,
                                                continuesBefore: $0.ev.start < from, continuesAfter: $0.ev.end > to) }
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

    /// Отступ подписи синхронизации от низа виджета — как системный отступ контента справа;
    /// от линии конца дня — на 10% меньше.
    private var syncGap: CGFloat { margins.trailing > 0 ? margins.trailing : 16 }

    /// Подпись о синхронизации появляется, только если данные устарели на 30 минут и больше.
    private var staleSince: Date? {
        guard let fetchedAt = entry.fetchedAt,
              entry.date.timeIntervalSince(fetchedAt) >= Double(CalendarSettings.staleLabelMinutes) * 60 else { return nil }
        return fetchedAt
    }

    var body: some View {
        if !entry.hasAccess {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark").font(.title)
                Text("No calendar access").font(.headline)
                Text(appName + " needs full calendar access. Open it and allow access.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: Layout.columnSpacing) {
                let columns = entry.config.columns(count: columnCount)
                ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                    let showsSync = idx == columns.count - 1 && staleSince != nil
                    VStack(alignment: .leading, spacing: 4) {
                        if idx == 0 {
                            AllDayList(events: entry.visibleEvents.filter(\.isAllDay), config: entry.config, mode: renderingMode)
                        }
                        ColumnView(entry: entry, startMinute: col.start, endMinute: col.end, mode: renderingMode)
                        // Под концом дня — давность последней синхронизации; последняя колонка сжимается.
                        // Подпись стоит у самого низа контента, от линии конца дня её отделяет тот же отступ.
                        if showsSync, let fetchedAt = staleSince {
                            SyncLabel(fetchedAt: fetchedAt, now: entry.date)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.top, syncGap * 0.9 - 4 - 1)
                        }
                    }
                    // Остальным колонкам — место под подпись нижнего часа.
                    .padding(.bottom, showsSync ? 0 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            // Контент сдвинут влево, чтобы отступ слева до плашек равнялся отступу сверху.
            .padding(.leading, -Layout.labelInset)
        }
    }
}

private func eventTint(_ ev: DayEvent, _ mode: WidgetRenderingMode) -> Color {
    mode == .fullColor ? Color(red: ev.rgb[0], green: ev.rgb[1], blue: ev.rgb[2]) : .primary
}

/// Цвет текста события: на iPhone в полноцветной тёмной теме — цвет календаря (как полоска),
/// в остальных случаях — обычный.
private func eventTextStyle(_ color: Color, _ mode: WidgetRenderingMode, _ scheme: ColorScheme) -> AnyShapeStyle {
    #if os(iOS)
    if mode == .fullColor && scheme == .dark { return AnyShapeStyle(color) }
    #endif
    return AnyShapeStyle(.primary)
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
    @Environment(\.colorScheme) private var scheme

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
                            .foregroundStyle(eventTextStyle(eventTint(ev, mode), mode, scheme))
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
            // Левый край плашек — вровень с двузначными цифрами часов.
            .padding(.leading, Layout.labelInset)
        }
    }
}

struct ColumnView: View {
    let entry: DayEntry
    /// Границы колонки в минутах от начала суток (могут заходить на следующие сутки).
    let startMinute: Int
    let endMinute: Int
    let mode: WidgetRenderingMode

    private let gutter: CGFloat = 20
    private let labelHeight: CGFloat = 12
    /// Центр кружка курсора относительно левого края колонки: левее цифр часов,
    /// чуть правее середины промежутка — на шестую часть ширины подписи часа.
    private let cursorX: CGFloat = -5 + Layout.labelWidth / 6
    private let cursorDot: CGFloat = 9
    /// На сколько перенесённое событие заходит за границу колонки — до края цифр часа.
    private let overshoot: CGFloat = 7

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale

    /// Цифры часов и линии сетки: в полноцветной тёмной теме — цвета системного Calendar,
    /// в остальных случаях — системные полутона (в монохроме их перекрашивает система).
    private var labelStyle: Color { mode == .fullColor && scheme == .dark ? Theme.darkLabel : .secondary }
    private var gridStyle: Color { mode == .fullColor && scheme == .dark ? Theme.darkGrid : .secondary.opacity(0.35) }

    var body: some View {
        GeometryReader { geo in
            let from = DayConfig.date(minute: startMinute, anchor: entry.anchor)
            let to = DayConfig.date(minute: endMinute, anchor: entry.anchor)
            // Сверху оставляем место под подпись первого часа.
            let top = labelHeight / 2
            let height = max(geo.size.height - top - 1, 1)
            let span = to.timeIntervalSince(from)
            let y: (Date) -> CGFloat = { top + CGFloat($0.timeIntervalSince(from) / span) * height }
            let eventsWidth = geo.size.width - gutter
            // Всё — по целым пикселям экрана: иначе линия часа и край события округлялись
            // по-разному, и событие, начинающееся ровно в час, залезало на линию.
            let px = 1 / scale
            let snap: (CGFloat) -> CGFloat = { ($0 * scale).rounded() / scale }
            // Линия — прежние 0.5 pt; плашки отступают от пикселей, которые она задевает.
            let lineHeight = max(1, (0.5 * scale).rounded(.up)) / scale
            // Верх и высота плашки: ровно на 1 px ниже линии своего начала и на 1 px выше линии
            // конца (как если бы там была линия часа). Перенесённое событие выходит за край колонки.
            let vertical: (PlacedEvent) -> (top: CGFloat, height: CGFloat) = { p in
                let top = p.continuesBefore ? snap(y(p.start) - overshoot) : snap(y(p.start)) + lineHeight + px
                let bottom = p.continuesAfter ? snap(y(p.end) + overshoot) : snap(y(p.end)) - px
                return (top, max(bottom - top, px))
            }

            ZStack(alignment: .topLeading) {
                // Часовая сетка
                ForEach(Array(stride(from: (startMinute + 59) / 60, through: endMinute / 60, by: 1)), id: \.self) { h in
                    let yy = top + CGFloat(h * 60 - startMinute) / CGFloat(endMinute - startMinute) * height
                    Text("\(h % 24)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(labelStyle)
                        .frame(width: gutter - 4, alignment: .trailing)
                        .offset(y: yy - labelHeight / 2)
                    Rectangle()
                        .fill(gridStyle)
                        .frame(width: eventsWidth, height: 0.5)
                        .offset(x: gutter, y: snap(yy))
                }

                // События
                let placed = Layout.place(entry.visibleEvents, from: from, to: to)
                ForEach(placed) { p in
                    let laneWidth = eventsWidth / CGFloat(p.lanes)
                    // Перенесённое событие выходит за границу колонки до края цифр часа,
                    // чтобы затухание заканчивалось (начиналось) на уровне подписи.
                    let (y0, h) = vertical(p)
                    EventBlock(event: p.event, height: h, dimmed: entry.config.isDimmed(p.event, now: entry.date),
                               inverted: isInverted(p.event, entry.config, mode),
                               continuesBefore: p.continuesBefore, continuesAfter: p.continuesAfter, mode: mode)
                        .frame(width: laneWidth - 2, height: h)
                        .offset(x: gutter + CGFloat(p.lane) * laneWidth, y: y0)
                }

                // Курсор текущего момента
                if entry.date >= from && entry.date < to {
                    let yy = y(entry.date)
                    // Части курсора над событиями — прозрачнее: в маске курсора — сами плашки событий
                    // (с их скруглениями), в координатах курсора.
                    let origin = CGPoint(x: cursorX - cursorDot / 2, y: yy - cursorDot / 2)
                    let covered: [(rect: CGRect, top: CGFloat, bottom: CGFloat)] = placed.compactMap { p in
                        let (y0, h) = vertical(p)
                        guard yy + cursorDot / 2 >= y0, yy - cursorDot / 2 <= y0 + h else { return nil }
                        let laneWidth = eventsWidth / CGFloat(p.lanes)
                        let rect = CGRect(x: gutter + CGFloat(p.lane) * laneWidth - origin.x, y: y0 - origin.y,
                                          width: laneWidth - 2, height: h)
                        return (rect, p.continuesBefore ? 0 : 5, p.continuesAfter ? 0 : 5)
                    }
                    // Кружок — посередине между краем соседней колонки и цифрами часов.
                    ZStack(alignment: .leading) {
                        // Линия начинается в центре кружка, чтобы между ними не было щели;
                        // скруглён только правый конец.
                        UnevenRoundedRectangle(bottomTrailingRadius: 1.2, topTrailingRadius: 1.2)
                            .frame(height: 2.4)
                            .padding(.leading, cursorDot / 2)
                        Circle().frame(width: cursorDot, height: cursorDot)
                    }
                    // В монохроме яркость = светлота цвета, поэтому курсор чисто белый — ярче всего остального.
                    .foregroundStyle(mode == .fullColor ? CalendarSettings.cursorColor : .white)
                    // Маска рисуется на холсте ровно в рамке курсора: плашки событий выше курсора,
                    // и как отдельные виды они растягивали маску — её центрировало, и прозрачные
                    // места съезжали с курсора.
                    .mask {
                        Canvas { context, size in
                            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                            context.blendMode = .destinationOut
                            for c in covered {
                                let shape = UnevenRoundedRectangle(topLeadingRadius: c.top, bottomLeadingRadius: c.bottom,
                                                                   bottomTrailingRadius: c.bottom, topTrailingRadius: c.top)
                                context.fill(shape.path(in: c.rect), with: .color(.black.opacity(1 - CalendarSettings.cursorOverEventOpacity)))
                            }
                        }
                    }
                    // Правый конец доходит до середины промежутка до следующей колонки.
                    .frame(width: geo.size.width + Layout.columnSpacing / 2 - cursorX + cursorDot / 2)
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
        .opacity(0.7)
    }
}

#if os(iOS)
private let isPhone = true
#else
private let isPhone = false
#endif

struct EventBlock: View {
    let event: DayEvent
    let height: CGFloat
    let dimmed: Bool
    let inverted: Bool
    let continuesBefore: Bool
    let continuesAfter: Bool
    let mode: WidgetRenderingMode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = eventTint(event, mode)
        // На стыке колонок углы прямые, а полоска доходит до самого края.
        let top: CGFloat = continuesBefore ? 0 : 5, bottom: CGFloat = continuesAfter ? 0 : 5
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top)
        // Короткая плашка не растягивается: шрифт уменьшается до того, что помещается по высоте.
        let pad: CGFloat = height >= 19 ? 3 : 1
        let fontSize = min(11, max(4, (height - 2 * pad) / 1.2))
        let stripeInset = min(3, height / 4)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(eventTextStyle(color, mode, scheme))
                    .lineLimit(height > 30 ? 2 : 1)
                // На месте прежнего времени начала — колокольчик, если у события есть alert.
                if event.hasAlarm && height > 34 {
                    Image(systemName: "bell")
                        .font(.system(size: 10, weight: .medium))
                        // Цвет календаря, но прозрачнее (насколько — в настройках, отдельно для
                        // светлой и тёмной темы); при инверсии выбивается целиком.
                        .foregroundStyle(inverted ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                                         : mode == .fullColor && isPhone
                                            ? AnyShapeStyle((CalendarSettings.bellColor(dark: scheme == .dark) ?? color)
                                                .opacity(CalendarSettings.bellOpacity(dark: scheme == .dark)))
                                         : AnyShapeStyle(.secondary))
                        .padding(.top, 2)
                }
            }
            .padding(.top, height > 16 ? 2 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, pad)
        .padding(.leading, 7)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: continuesBefore ? 0 : 1.5, bottomLeadingRadius: continuesAfter ? 0 : 1.5,
                                   bottomTrailingRadius: continuesAfter ? 0 : 1.5, topTrailingRadius: continuesBefore ? 0 : 1.5)
                .fill(color)
                .frame(width: 3)
                .padding(.leading, 3)
                .padding(.top, continuesBefore ? 0 : stripeInset)
                .padding(.bottom, continuesAfter ? 0 : stripeInset)
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
    static let cursor = Color(red: 0xE9 / 255, green: 0x53 / 255, blue: 0x4C / 255)
    /// Вертикальный градиент тёмного фона, как у системного виджета Calendar.
    static let darkBackgroundTop = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x35 / 255)
    static let darkBackgroundBottom = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let darkLabel = Color(white: 0xB0 / 255)
    static let darkGrid = Color(white: 0x54 / 255)
}

/// Фон виджета по теме системы: белый или тёмный градиент, как у системного Calendar.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            LinearGradient(colors: [Theme.darkBackgroundTop, Theme.darkBackgroundBottom], startPoint: .top, endPoint: .bottom)
        } else {
            Color.white
        }
    }
}

// MARK: - Widget

@main
struct TodayWidgets: WidgetBundle {
    var body: some Widget {
        DoubleTodayWidget()
        #if os(macOS)
        TripleTodayWidget()
        #else
        HabitWidget()
        HabitGoalWidget()
        #endif
    }
}

/// Large: день в две колонки.
struct DoubleTodayWidget: Widget {
    var body: some WidgetConfiguration {
        // Вид (kind) прежний — уже поставленные виджеты не слетают; меняется только название.
        #if os(iOS)
        dayWidgetConfiguration(kind: "DoubleToday", name: "Completely Today", family: .systemLarge)
        #else
        dayWidgetConfiguration(kind: "DoubleToday", name: "Double Today", family: .systemLarge)
        #endif
    }
}

/// Extra Large (только macOS): день в три колонки.
struct TripleTodayWidget: Widget {
    var body: some WidgetConfiguration {
        dayWidgetConfiguration(kind: "TodayCalendarWidget", name: "Triple Today", family: .systemExtraLarge)
    }
}

private func dayWidgetConfiguration(kind: String, name: LocalizedStringResource, family: WidgetFamily) -> some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: DayConfigurationIntent.self, provider: Provider()) { entry in
        TodayWidgetView(entry: entry)
            .modifier(OpensCalendarOnTap())
            .widgetURL(tapURL(for: entry.date))
            .containerBackground(for: .widget) { WidgetBackground() }
    }
    .configurationDisplayName(name)
    .description("")
    .supportedFamilies([family])
}

/// На iOS 18+ весь виджет — кнопка, которая сразу открывает Calendar, минуя приложение.
/// Иначе срабатывает `widgetURL`: iOS запускает приложение, и оно перекидывает в Calendar.
struct OpensCalendarOnTap: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            Button(intent: OpenCalendarIntent()) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
@available(iOS 18, *)
struct OpenCalendarIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Calendar"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        // Нажатие на виджет — ещё и повод синхронизировать уведомления.
        await AlertScheduler.sync()
        return .result(opensIntent: OpenURLIntent(calendarURL(for: Date())))
    }
}

/// Calendar на iOS открывается сразу на дне, переданном секундами от 1 января 2001.
/// Calendar открывается так, что указанный момент оказывается ниже верха экрана примерно на час,
/// поэтому просим момент на час раньше — тогда на экране «сейчас».
private func calendarURL(for date: Date) -> URL {
    let date = date.addingTimeInterval(-3600)
    return URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))")!
}

/// На iOS виджет открывает Calendar напрямую, на сегодняшнем дне.
private func tapURL(for date: Date) -> URL? { calendarURL(for: date) }
#else
/// На macOS клик ловит фоновое приложение и открывает Calendar на сегодняшнем дне.
private func tapURL(for date: Date) -> URL? { URL(string: "todaycalendarwidget://open") }
#endif

// MARK: - Sample data

enum SampleData {
    static var events: [DayEvent] {
        let d = Date()
        func ev(_ title: String, _ h: Double, _ dur: Double, allDay: Bool = false) -> DayEvent {
            let s = Calendar.current.startOfDay(for: d).addingTimeInterval(h * 3600)
            return DayEvent(id: title, title: title, start: s, end: s.addingTimeInterval(dur * 3600),
                            isAllDay: allDay, calendarID: "sample", rgb: [0.45, 0.6, 1.0], hasAlarm: title == "meeting")
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

#Preview(as: .systemLarge) {
    DoubleTodayWidget()
} timeline: {
    DayEntry(date: Date(), events: SampleData.events, hasAccess: true)
}
