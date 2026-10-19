#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Настройки виджета: привычка и размер шрифта

struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = HabitQuery()

    let id: String
    let name: String
    /// Цвет привычки — кружок перед названием, как у календарей в «Calendars to show».
    let rgb: [Double]

    init(_ habit: Habit) {
        id = habit.id.uuidString
        name = habit.title
        rgb = habit.rgb
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: ColorDot.png(rgb).map { .init(data: $0, isTemplate: false) })
    }
}

/// Привычки из приложения (кроме архивных), с поиском по названию.
struct HabitQuery: EntityStringQuery {
    private func all() -> [HabitEntity] {
        HabitStorage.load().habits.filter { !$0.archived && !$0.isTrashed }.map(HabitEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        HabitStorage.load().habits.filter { identifiers.contains($0.id.uuidString) }
            .map(HabitEntity.init)
    }
    func suggestedEntities() async throws -> [HabitEntity] { all() }
    func entities(matching string: String) async throws -> [HabitEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

/// Размер шрифта названия; «Default» — из настроек привычек в приложении.
enum TitleSize: Int, AppEnum {
    case appDefault = 0, s14 = 14, s16 = 16, s18 = 18, s20 = 20, s22 = 22, s24 = 24, s26 = 26, s28 = 28, s32 = 32

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Title Size"
    static var caseDisplayRepresentations: [TitleSize: DisplayRepresentation] = [
        .appDefault: "Default", .s14: "14", .s16: "16", .s18: "18", .s20: "20", .s22: "22",
        .s24: "24", .s26: "26", .s28: "28", .s32: "32",
    ]

    var points: Double { self == .appDefault ? HabitSettings.titleSize : Double(rawValue) }
}

struct HabitWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Habit"
    static var description = IntentDescription("Habit history for the last weeks.")

    @Parameter(title: "Habit")
    var habit: HabitEntity?

    @Parameter(title: "Title font", default: .appDefault)
    var titleSize: TitleSize

    @Parameter(title: "Wrap Title", description: "Off: one line, the end fades out", default: false)
    var wrapTitle: Bool

    @Parameter(title: "Break Words", description: "With Wrap Title: break by letters with a hyphen, not by words", default: false)
    var breakWords: Bool
}

// MARK: - Кнопка «сегодня выполнено»

struct MarkHabitTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Habit Done Today"
    static var isDiscoverable = false

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }

    /// Сегодня не отмечено — отметить «выполнено»; уже отмечено — снять отметку.
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: habitID) { HabitActions.toggleToday(habitID: id) }
        return .result()
    }
}

// MARK: - Timeline

struct HabitEntry: TimelineEntry {
    let date: Date
    let habit: Habit?
    var titleSize = 24.0
    var wrapTitle = false
    var breakWords = false
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { HabitEntry(date: Date(), habit: TestHabit.make()) }

    func snapshot(for configuration: HabitWidgetIntent, in context: Context) async -> HabitEntry {
        HabitEntry(date: Date(), habit: await habit(for: configuration), titleSize: configuration.titleSize.points,
                   wrapTitle: configuration.wrapTitle, breakWords: configuration.breakWords)
    }

    func timeline(for configuration: HabitWidgetIntent, in context: Context) async -> Timeline<HabitEntry> {
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let entry = HabitEntry(date: now, habit: await habit(for: configuration), titleSize: configuration.titleSize.points,
                               wrapTitle: configuration.wrapTitle, breakWords: configuration.breakWords)
        return Timeline(entries: [entry], policy: .after(min(midnight, now.addingTimeInterval(15 * 60))))
    }

    /// Выбранная привычка (после подтягивания отметок из Reminders); без выбора — первая в списке.
    private func habit(for configuration: HabitWidgetIntent) async -> Habit? {
        var db = HabitStorage.load()
        await ReminderSync.sync(&db)
        HabitStorage.save(db)
        if let id = configuration.habit?.id, let habit = db.habits.first(where: { $0.id.uuidString == id && !$0.isTrashed }) { return habit }
        return db.habits.first { !$0.archived && !$0.isTrashed }
    }
}

// MARK: - Общая шапка: название и кнопка

/// Название привычки и круглая кнопка «сегодня выполнено» в правом верхнем углу.
/// Название в одну строку — заданным размером; не влезает — на треть мельче в две строки
/// с растворением конца второй строки.
struct HabitHeader: View {
    let habit: Habit
    let titleSize: Double
    /// Переносить на две строки, если не влезает (иначе одна строка с растворением конца).
    var wrap = false
    /// При переносе резать по буквам с дефисом, а не по словам.
    var breakWords = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if wrap {
                    ViewThatFits(in: .horizontal) {
                        title(size: titleSize).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        if breakWords {
                            // Первая строка — сколько букв влезает (с дефисом), остальное — второй.
                            GeometryReader { g in
                                let lines = Self.hyphenated(habit.title, width: g.size.width, size: titleSize * 2 / 3)
                                VStack(alignment: .leading, spacing: 0) {
                                    title(lines.0, size: titleSize * 2 / 3).lineLimit(1)
                                    title(lines.1, size: titleSize * 2 / 3).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                }
                                .frame(maxHeight: .infinity, alignment: .leading)
                                .mask(fade(lines: 2))
                            }
                        } else {
                            title(size: titleSize * 2 / 3).lineLimit(2).mask(fade(lines: 2))
                        }
                    }
                } else {
                    // Одна строка от левого отступа; длинное название уходит под растворение
                    // перед кнопкой и не влияет на раскладку.
                    Color.clear
                        .overlay(alignment: .leading) {
                            title(size: titleSize).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        }
                        .clipped()
                        .mask(fade(lines: 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // Линия центровки названия на 1 pt выше середины кнопки.
            .offset(y: -1)
            .widgetAccentable()
            // Сегодня сделано полностью (у «Twice a day» — дважды) — кнопка снимает отметку.
            let today = HabitDay.today()
            let size = HabitSettings.buttonSize
            Button(intent: MarkHabitTodayIntent(habitID: habit.id)) {
                if HabitSettings.squircleButton {
                    // Сегодняшний день — та же клетка, что в сетке приложения.
                    HabitCell(state: habit.state(today), isToday: true, color: habit.color, size: size, style: HabitSettings.style,
                              partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex, twiceIconHex: habit.twiceIconHex)
                } else {
                    // Тот же круглый чекбокс, что на главной.
                    RoundCheckbox(habit: habit, size: size, today: today)
                }
            }
            .buttonStyle(.plain)
            .contentShape(HabitSettings.squircleButton
                          ? AnyShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)) : AnyShape(Circle()))
            // Размер шрифта названия на кнопку не влияет.
            .fixedSize()
            .layoutPriority(1)
            .widgetAccentable()
        }
    }

    /// Растворение конца последней строки.
    private func fade(lines: Int) -> some View {
        VStack(spacing: 0) {
            if lines > 1 { Color.black }
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
            }
        }
    }

    private func title(size: Double) -> some View { title(habit.title, size: size) }

    /// Разбивка по буквам: в первую строку — самый длинный кусок, который влезает с дефисом
    /// (на пробеле — без дефиса).
    static func hyphenated(_ text: String, width: CGFloat, size: Double) -> (String, String) {
        var font = UIFont.systemFont(ofSize: size, weight: .bold)
        if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: size) }
        func fits(_ s: String) -> Bool { (s as NSString).size(withAttributes: [.font: font]).width <= width }
        guard !fits(text) else { return (text, "") }
        let chars = Array(text)
        var cut = 1
        while cut < chars.count {
            let next = String(chars[..<(cut + 1)])
            if !fits(chars[cut] == " " ? next.trimmingCharacters(in: .whitespaces) : next + "-") { break }
            cut += 1
        }
        let first = String(chars[..<cut]), rest = String(chars[cut...])
        if first.hasSuffix(" ") || rest.hasPrefix(" ") {
            return (first.trimmingCharacters(in: .whitespaces), rest.trimmingCharacters(in: .whitespaces))
        }
        return (first + "-", rest)
    }

    private func title(_ text: String, size: Double) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(habit.color)
    }
}

// MARK: - Виджет с сеткой

struct HabitWidgetView: View {
    let entry: HabitEntry

    private let gap: CGFloat = 4
    private var inset: CGFloat { HabitSettings.gridInset }
    private var buttonSize: CGFloat { HabitSettings.buttonSize }
    private var buttonInset: CGFloat { HabitSettings.buttonInset }
    /// Сколько недель видно чётко (включая текущую).
    private var weeks: Int { HabitSettings.widgetWeeks }

    var body: some View {
        if let habit = entry.habit {
            content(habit)
                .widgetURL(URL(string: "todaycalendarwidget://habit/\(habit.id.uuidString)"))
        } else {
            Text("No habits yet").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func content(_ habit: Habit) -> some View {
        GeometryReader { geo in
            let cell = (geo.size.width - 2 * inset - 6 * gap) / 7
            // Верх самой старой из чётко видимых недель.
            let fourWeeksTop = geo.size.height - inset - CGFloat(weeks) * cell - CGFloat(weeks - 1) * gap
            let fifthWeekTop = fourWeeksTop - gap - cell
            // Маска накладывается на сетку, а она короче виджета на нижний отступ.
            let gridHeight = geo.size.height - inset
            ZStack(alignment: .topLeading) {
                // Сетка прижата к низу; верхние недели уходят под заголовок и растворяются.
                grid(habit, cell: cell)
                    .frame(width: geo.size.width - 2 * inset, height: gridHeight, alignment: .bottom)
                    .padding(.horizontal, inset)
                    // N недель (включая текущую) видны полностью: 100% — у верхнего края N-й недели;
                    // выше линейно до 0 на той же длине; дальше ничего не видно.
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: max(0, fifthWeekTop + gap) / gridHeight),
                            .init(color: .black, location: max(0, fourWeeksTop) / gridHeight),
                            .init(color: .black, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )

                HabitHeader(habit: habit, titleSize: entry.titleSize, wrap: entry.wrapTitle, breakWords: entry.breakWords)
                    .frame(width: geo.size.width - inset - buttonInset, height: buttonSize)
                    .padding(.leading, inset)
                    .padding(.top, buttonInset)
            }
        }
    }

    private func grid(_ habit: Habit, cell: CGFloat) -> some View {
        let today = HabitDay.today(entry.date)
        let style = HabitSettings.style
        let missed = habit.missedDays(today: today)
        return VStack(spacing: gap) {
            ForEach(Array(HabitGrid.weeks(count: weeks + 2, endingAt: today).enumerated()), id: \.offset) { _, week in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        if let day = week[i] {
                            HabitCell(state: habit.state(day), isToday: day == today, color: habit.color, size: cell,
                                      style: style, partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex,
                                      twiceIconHex: habit.twiceIconHex, missed: missed.contains(HabitDay.key(day)),
                                      missedHex: habit.missedHex)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
                .background(alignment: .topLeading) {
                    MissedLinks(flags: week.map { $0.map { missed.contains(HabitDay.key($0)) } ?? false }, cell: cell, gap: gap,
                                color: style.missedColor(habit.missedHex).opacity(style.missedLinkOpacity))
                }
            }
        }
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitWidget", intent: HabitWidgetIntent.self, provider: HabitProvider()) { entry in
            HabitWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Habit Grid")
        .description("")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Виджет с кольцом недельной цели

struct HabitGoalWidgetView: View {
    let entry: HabitEntry

    var body: some View {
        if let habit = entry.habit {
            content(habit)
                .widgetURL(URL(string: "todaycalendarwidget://habit/\(habit.id.uuidString)"))
        } else {
            Text("No habits yet").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func content(_ habit: Habit) -> some View {
        let today = HabitDay.today(entry.date)
        let done = habit.doneInWeek(of: today)
        let goal = habit.weeklyGoal > 0 ? habit.weeklyGoal : 7
        let inset = HabitSettings.gridInset
        return VStack(spacing: 0) {
            HabitHeader(habit: habit, titleSize: entry.titleSize, wrap: entry.wrapTitle, breakWords: entry.breakWords)
                .frame(height: HabitSettings.buttonSize)
                .padding(.leading, inset)
                .padding(.trailing, HabitSettings.buttonInset)
                .padding(.top, HabitSettings.buttonInset)
            ZStack {
                Circle().stroke(habit.color.opacity(HabitSettings.style.undoneOpacity), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(1, Double(done) / Double(goal)))
                    .stroke(habit.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                VStack(spacing: 0) {
                    Text("\(done)/\(goal)").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("this week").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .padding([.horizontal, .bottom], inset)
        }
    }
}

struct HabitGoalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitGoalWidget", intent: HabitWidgetIntent.self, provider: HabitProvider()) { entry in
            HabitGoalWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Habit Goal")
        .description("")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
#endif

// MARK: - Москва на экране блокировки

#if os(iOS)
struct MoscowEntry: TimelineEntry {
    let date: Date
    let line: String
}

struct MoscowProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoscowEntry { MoscowEntry(date: Date(), line: MoscowClock.line(Date())) }
    func getSnapshot(in context: Context, completion: @escaping (MoscowEntry) -> Void) { completion(placeholder(in: context)) }

    /// Кадр на каждую минуту на час вперёд.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoscowEntry>) -> Void) {
        let start = Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date()
        let entries = (0..<60).map { i -> MoscowEntry in
            let d = start.addingTimeInterval(Double(i) * 60)
            return MoscowEntry(date: d, line: MoscowClock.line(d))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Строка над временем на экране блокировки: свой текст и московское время.
struct MoscowClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoscowClock", provider: MoscowProvider()) { entry in
            Text(entry.line).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Moscow Time")
        .description("Your text and the time in Moscow (UTC+3).")
        .supportedFamilies([.accessoryInline])
    }
}
#endif
