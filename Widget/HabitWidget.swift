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
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Привычки из приложения (кроме архивных), с поиском по названию.
struct HabitQuery: EntityStringQuery {
    private func all() -> [HabitEntity] {
        HabitStorage.load().habits.filter { !$0.archived }.map { HabitEntity(id: $0.id.uuidString, name: $0.title) }
    }

    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        HabitStorage.load().habits.filter { identifiers.contains($0.id.uuidString) }
            .map { HabitEntity(id: $0.id.uuidString, name: $0.title) }
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

    @Parameter(title: "Title size", default: .appDefault)
    var titleSize: TitleSize
}

// MARK: - Кнопка «сегодня выполнено»

struct MarkHabitTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Habit Done Today"
    static var isDiscoverable = false

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: habitID) { HabitActions.markToday(habitID: id) }
        return .result()
    }
}

// MARK: - Timeline

struct HabitEntry: TimelineEntry {
    let date: Date
    let habit: Habit?
    var titleSize = 24.0
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { HabitEntry(date: Date(), habit: TestHabit.make()) }

    func snapshot(for configuration: HabitWidgetIntent, in context: Context) async -> HabitEntry {
        HabitEntry(date: Date(), habit: await habit(for: configuration), titleSize: configuration.titleSize.points)
    }

    func timeline(for configuration: HabitWidgetIntent, in context: Context) async -> Timeline<HabitEntry> {
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let entry = HabitEntry(date: now, habit: await habit(for: configuration), titleSize: configuration.titleSize.points)
        return Timeline(entries: [entry], policy: .after(min(midnight, now.addingTimeInterval(30 * 60))))
    }

    /// Выбранная привычка (после подтягивания отметок из Reminders); без выбора — первая в списке.
    private func habit(for configuration: HabitWidgetIntent) async -> Habit? {
        var db = HabitStorage.load()
        await ReminderSync.sync(&db)
        HabitStorage.save(db)
        if let id = configuration.habit?.id, let habit = db.habits.first(where: { $0.id.uuidString == id }) { return habit }
        return db.habits.first { !$0.archived }
    }
}

// MARK: - Общая шапка: название и кнопка

/// Название привычки и круглая кнопка «сегодня выполнено» в правом верхнем углу.
/// Название в одну строку — заданным размером; не влезает — на треть мельче в две строки
/// с растворением конца второй строки.
struct HabitHeader: View {
    let habit: Habit
    let titleSize: Double

    var body: some View {
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                title(size: titleSize).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                title(size: titleSize * 2 / 3)
                    .lineLimit(2)
                    .mask(
                        VStack(spacing: 0) {
                            Color.black
                            HStack(spacing: 0) {
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
                            }
                        }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetAccentable()
            Button(intent: MarkHabitTodayIntent(habitID: habit.id)) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(habit.color)
                    .frame(width: HabitSettings.buttonSize, height: HabitSettings.buttonSize)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .widgetAccentable()
        }
    }

    private func title(size: Double) -> some View {
        Text(habit.title)
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
                    // Чётко видны N недель (включая текущую), следующая — полупрозрачная, выше — под заголовком.
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: max(0, fifthWeekTop - gap - cell / 2) / gridHeight),
                            .init(color: .black.opacity(0.35), location: fifthWeekTop / gridHeight),
                            .init(color: .black.opacity(0.35), location: (fourWeeksTop - gap) / gridHeight),
                            .init(color: .black, location: (fourWeeksTop - gap / 2) / gridHeight),
                        ], startPoint: .top, endPoint: .bottom)
                    )

                HabitHeader(habit: habit, titleSize: entry.titleSize)
                    .frame(width: geo.size.width - inset - buttonInset, height: buttonSize)
                    .padding(.leading, inset)
                    .padding(.top, buttonInset)
            }
        }
    }

    private func grid(_ habit: Habit, cell: CGFloat) -> some View {
        let today = HabitDay.today(entry.date)
        let style = HabitSettings.style
        return VStack(spacing: gap) {
            ForEach(Array(HabitGrid.weeks(count: weeks + 2, endingAt: today).enumerated()), id: \.offset) { _, week in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        if let day = week[i] {
                            HabitCell(state: habit.state(day), isToday: day == today, color: habit.color, size: cell,
                                      style: style, partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
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
        .configurationDisplayName("Habit")
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
            HabitHeader(habit: habit, titleSize: entry.titleSize)
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
