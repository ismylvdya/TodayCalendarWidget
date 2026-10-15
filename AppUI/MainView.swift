import SwiftUI
import WidgetKit
import EventKit

/// Заголовок раздела скруглённым шрифтом — как названия списков в Reminders.
struct RoundedHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.primary).textCase(nil)
    }
}

/// Экраны приложения. Все переходы — через один тип маршрута: смешение переходов по значению
/// и по экрану в одном стеке сбрасывало навигацию (из архива не открывалась привычка).
enum Route: Hashable {
    case habit(UUID), archive, habitSettings, calendarSettings
}

/// Главный экран: привычки, архив, настройки привычек и календаря.
struct MainView: View {
    @StateObject private var store = HabitStore()
    @State private var path: [Route] = []
    @State private var showingNewHabit = false
    /// Открыть привычку по ссылке из виджета.
    var openHabit: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Длинное название не влезает в стандартный крупный заголовок — свой, с переносом перед «&».
                Text(appName.replacingOccurrences(of: " & ", with: "\n& "))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                Section {
                    ForEach(store.habits.filter { !$0.archived }) { habit in
                        NavigationLink(value: Route.habit(habit.id)) { HabitRow(habit: habit) }
                    }
                    Button { showingNewHabit = true } label: { Label("New Habit", systemImage: "plus") }
                } header: {
                    RoundedHeader("Habits")
                }
                Section {
                    NavigationLink("Habit Settings", value: Route.habitSettings)
                    NavigationLink("Calendar Settings", value: Route.calendarSettings)
                    let archived = store.habits.filter(\.archived)
                    if !archived.isEmpty {
                        NavigationLink(value: Route.archive) {
                            HStack {
                                Text("Archive")
                                Spacer()
                                Text("\(archived.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .habit(let id): HabitDetailView(store: store, habitID: id)
                case .archive: ArchiveView(store: store)
                case .habitSettings: HabitSettingsView(store: store)
                case .calendarSettings: CalendarSettingsView()
                }
            }
            .sheet(isPresented: $showingNewHabit) { NewHabitView(store: store) }
        }
        .task { await store.refresh() }
        .onChange(of: openHabit) { _, id in if let id { path = [.habit(id)] } }
        .onAppear { if let openHabit { path = [.habit(openHabit)] } }
    }
}

struct ArchiveView: View {
    @ObservedObject var store: HabitStore

    var body: some View {
        List(store.habits.filter(\.archived)) { habit in
            NavigationLink(value: Route.habit(habit.id)) { HabitRow(habit: habit) }
        }
        .navigationTitle("Archive")
    }
}

struct HabitRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(habit.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title).font(.system(.body, design: .rounded).weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if habit.state(HabitDay.today()) != .none { Image(systemName: "checkmark.circle.fill").foregroundStyle(habit.color) }
        }
    }

    private var subtitle: String {
        let done = habit.doneInWeek(of: HabitDay.today())
        let goal = habit.weeklyGoal > 0 ? "\(done)/\(habit.weeklyGoal)" : "\(done)"
        return "\(goal) this week · " + (habit.links.isEmpty ? "manual" : "Reminders")
    }
}

// MARK: - Новая привычка

struct NewHabitView: View {
    @ObservedObject var store: HabitStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Color(hex: "#3478F6FF")!
    @State private var link: ReminderLink?
    @State private var choosingReminder = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(link == nil ? "Link a Reminder…" : "Linked: \(link!.titles.last ?? "")") { choosingReminder = true }
                } footer: {
                    Text("Without a reminder the habit is marked only in this app and its widgets.")
                }
                Section {
                    TextField(link?.titles.last ?? "Name (optional)", text: $name)
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                } footer: {
                    Text("Leave the name empty to use the reminder's title — it follows renames in Reminders.")
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var habit = Habit(name: name.trimmingCharacters(in: .whitespaces), colorHex: color.hexString)
                        if let link { habit.links = [link] }
                        store.add(habit)
                        Task { await store.refresh() }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && link == nil)
                }
            }
            .sheet(isPresented: $choosingReminder) { ReminderPickerView { link = $0 } }
        }
    }
}

// MARK: - Карточки страницы привычки

/// Карточка как в сгруппированном списке: заголовок и белая подложка со скруглением.
struct Card<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { RoundedHeader(title).padding(.horizontal, 4) }
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            if let footer { Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4) }
        }
    }
}

/// Поле для цвета «#RRGGBBAA» с образцом.
struct HexField: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("#RRGGBBAA", text: $hex)
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Circle().fill(Color(hex: hex) ?? .clear).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3)))
        }
    }
}

// MARK: - Страница привычки

struct HabitDetailView: View {
    @ObservedObject var store: HabitStore
    let habitID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var choosingReminder = false
    @State private var noteDay: Date?
    @State private var noteText = ""
    /// Нижняя граница видимой области страницы — до неё может расти подложка сетки.
    @State private var pageBottom: CGFloat = 800

    var body: some View {
        if let habit = store.habit(habitID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(habit.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)

                    GrowingHistoryGrid(habit: habit, pageBottom: pageBottom,
                                       setState: { day, state in store.set(habitID, day: day, state: state) },
                                       editNote: { day in noteText = habit.note(day) ?? ""; noteDay = day })

                    settingsCard(habit)
                    StatsCard(habit: habit)
                    remindersCard(habit)

                    Card {
                        ShareLink(item: HabitCSV.file([habit], name: "\(habit.title).csv")) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                        Divider()
                        Button(habit.archived ? "Unarchive Habit" : "Archive Habit") {
                            var h = habit; h.archived.toggle(); store.update(h)
                            if h.archived { dismiss() }
                        }
                        Divider()
                        Button("Delete Habit", role: .destructive) { confirmingDelete = true }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { pageBottom = $0 }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete \(habit.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { dismiss(); store.delete(habitID) }
            } message: {
                Text("The history in this app is deleted. Reminders are not touched.")
            }
            .alert(noteDay.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Note",
                   isPresented: Binding(get: { noteDay != nil }, set: { if !$0 { noteDay = nil } })) {
                TextField("Note", text: $noteText)
                Button("Save") {
                    if let day = noteDay { var h = habit; h.setNote(noteText, day: day); store.update(h) }
                    noteDay = nil
                }
                Button("Cancel", role: .cancel) { noteDay = nil }
            }
            .sheet(isPresented: $choosingReminder) {
                ReminderPickerView { picked in
                    var h = habit
                    if !h.links.contains(where: { $0.reminderID == picked.reminderID }) { h.links.append(picked) }
                    store.update(h)
                    Task { await store.refresh() }
                }
            }
        }
    }

    private func settingsCard(_ habit: Habit) -> some View {
        Card(title: "Habit") {
            TextField(habit.links.last?.titles.last ?? "Name (optional)",
                      text: Binding(get: { habit.name }, set: { var h = habit; h.name = $0; store.update(h) }))
            Divider()
            ColorPicker("Color", selection: Binding(get: { habit.color }, set: { var h = habit; h.colorHex = $0.hexString; store.update(h) }),
                        supportsOpacity: false)
            Divider()
            Stepper(habit.weeklyGoal == 0 ? "Weekly goal: off" : "Weekly goal: \(habit.weeklyGoal) times",
                    value: Binding(get: { habit.weeklyGoal }, set: { var h = habit; h.weeklyGoal = $0; store.update(h) }), in: 0...7)
            Divider()
            iconColor("Partially Done Icon", hex: habit.partialIconHex, fallback: "#FFFFFFFF") { var h = habit; h.partialIconHex = $0; store.update(h) }
            Divider()
            iconColor("Overdone Icon", hex: habit.overIconHex, fallback: "#FFFFFFFF") { var h = habit; h.overIconHex = $0; store.update(h) }
        }
    }

    /// Свой цвет иконки: переключатель, палитра и hex с прозрачностью.
    @ViewBuilder
    private func iconColor(_ title: String, hex: String?, fallback: String, set: @escaping (String?) -> Void) -> some View {
        Toggle("\(title): own color", isOn: Binding(get: { hex != nil }, set: { set($0 ? fallback : nil) }))
        if let hex {
            ColorPicker("Color", selection: Binding(get: { Color(hex: hex) ?? .white }, set: { set($0.hexString) }), supportsOpacity: true)
            HexField(title: "Hex", hex: Binding(get: { hex }, set: { if Color(hex: $0) != nil { set($0) } }))
        }
    }

    private func remindersCard(_ habit: Habit) -> some View {
        Card(title: "Reminders",
             footer: "Linking a new reminder keeps the whole history under this habit. Unlinking or deleting never changes Reminders.") {
            ForEach(habit.links, id: \.reminderID) { link in
                HStack {
                    VStack(alignment: .leading) {
                        Text(link.titles.last ?? "Reminder")
                        if link.titles.count > 1 {
                            Text("Also known as: " + link.titles.dropLast().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        var h = habit; h.links.removeAll { $0.reminderID == link.reminderID }; store.update(h)
                    } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            Button("Link a Reminder…") { choosingReminder = true }
        }
    }
}

// MARK: - Сетка с растущей подложкой

/// История за всё время: недели строками (старые сверху), дни столбцами.
/// Подложка показывает последние недели; при прокрутке к более ранним она растёт вниз
/// вслед за пальцем, пока низ не дойдёт до края экрана, дальше сетка прокручивается внутри.
struct GrowingHistoryGrid: View {
    let habit: Habit
    let pageBottom: CGFloat
    let setState: (Date, HabitDayState) -> Void
    let editNote: (Date) -> Void

    private let gap: CGFloat = 6
    private let pad: CGFloat = 16
    private let baseWeeks = 5
    private let fade: CGFloat = 22

    /// Ширина подложки: экран минус поля страницы (сразу известна — без перестройки сетки
    /// после первой раскладки, из-за которой прокрутка вставала не в самый низ).
    private var width: CGFloat { UIScreen.main.bounds.width - 32 }
    @State private var cardTop: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    /// Нижнее поле прокрутки (= fade, когда поля применились).
    @State private var bottomInset: CGFloat = 0
    /// Пока прокрутка не встала в самый низ при базовой высоте, подложка не растёт
    /// (иначе на первой раскладке она сразу растягивается до максимума).
    @State private var ready = false
    @State private var position = ScrollPosition(edge: .bottom)

    private var cell: CGFloat { max(10, (width - 2 * pad - 6 * gap) / 7) }

    private var weekCount: Int {
        let first = ([habit.createdAt] + habit.completions.compactMap(HabitDay.date)).min() ?? Date()
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: HabitGrid.weekStart(first), to: HabitDay.today()).weekOfYear ?? 0
        return max(weeks + 1, baseWeeks) + 26   // запас ранних недель, чтобы было куда листать
    }

    var body: some View {
        let header: CGFloat = 20
        // Последние недели целиком и полоска растворяющейся недели над ними.
        let base = CGFloat(baseWeeks) * (cell + gap) - gap + fade + pad
        // Подложка растёт, пока её низ не дойдёт до заданного отступа от низа экрана.
        let maxHeight = max(base, pageBottom - HabitSettings.gridBottomMargin - cardTop - pad - header - 8)
        // Пока низ сетки виден, высота = от текущей прокрутки до конца контента (с нижним полем).
        let height = ready ? min(maxHeight, max(base, contentHeight + bottomInset - offset)) : base
        let today = HabitDay.today()
        let style = HabitSettings.style

        VStack(spacing: 8) {
            HStack(spacing: gap) {
                ForEach(Array(HabitGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .frame(height: header)
            .padding(.horizontal, pad)

            // Сетка доходит до краёв подложки: поля — внутри прокрутки, поэтому увеличенная
            // при долгом нажатии клетка не обрезается рамкой.
            ScrollView {
                VStack(spacing: gap) {
                    ForEach(Array(HabitGrid.weeks(count: weekCount, endingAt: today).enumerated()), id: \.offset) { _, week in
                        HStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { i in
                                if let day = week[i] {
                                    dayCell(day, today: today, style: style)
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, pad)
                .padding(.bottom, pad)
            }
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: [CGFloat].self) {
                [$0.contentOffset.y, $0.contentSize.height, $0.contentInsets.bottom, $0.visibleRect.maxY, $0.containerSize.height]
            } action: { _, v in
                offset = v[0]
                contentHeight = v[1]
                bottomInset = v[2]
                // Готово, когда прокрутка встала в самый низ.
                guard !ready, v[1] > 0 else { return }
                if abs(v[3] - (v[1] + v[2])) < 2 { ready = true } else { position.scrollTo(edge: .bottom) }
            }
            .frame(height: height)
            .mask(edgeFade(top: offset > 1, bottom: contentHeight + bottomInset - offset - height > 1))
        }
        .padding(.top, pad)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { cardTop = $0 }
    }

    private func dayCell(_ day: Date, today: Date, style: HabitStyle) -> some View {
        let state = habit.state(day)
        let note = habit.note(day)
        return HabitCell(state: state, isToday: day == today, color: habit.color, size: cell, style: style,
                         partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex, hasNote: note != nil)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous))
            .onTapGesture { setState(day, state == .none ? .done : .none) }
            .contextMenu {
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(HabitDayState.allCases) { option in
                        Button { setState(day, option) } label: {
                            Label(option.title, systemImage: option == state ? "checkmark" : icon(option, style))
                        }
                    }
                }
                Section {
                    Button { editNote(day) } label: { Label(note == nil ? "Add Note…" : "Edit Note…", systemImage: "doc") }
                    if let note { Text(note) }
                }
            }
    }

    /// Сетка растворяется у краёв подложки, если за краем есть ещё недели.
    private func edgeFade(top: Bool, bottom: Bool) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
            Color.black
            LinearGradient(colors: [.black, bottom ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
        }
    }

    private func icon(_ state: HabitDayState, _ style: HabitStyle) -> String {
        switch state {
        case .none: "square"
        case .partial: style.partialSymbol
        case .done: "square.fill"
        case .over: style.overSymbol
        }
    }
}

// MARK: - Статистика

struct StatsCard: View {
    let habit: Habit

    var body: some View {
        let s = HabitStats(habit: habit)
        Card(title: "Statistics") {
            if habit.weeklyGoal > 0 {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(habit.color.opacity(0.15), lineWidth: 7)
                        Circle().trim(from: 0, to: min(1, Double(s.thisWeek) / Double(habit.weeklyGoal)))
                            .stroke(habit.color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 44, height: 44)
                    Text("This week: \(s.thisWeek) of \(habit.weeklyGoal)").font(.headline)
                }
                Divider()
            }
            HStack {
                stat("Current streak", "\(s.currentStreak) d")
                stat("Longest streak", "\(s.longestStreak) d")
            }
            HStack {
                stat("Last 7 days", percent(s.last7))
                stat("Last 30 days", percent(s.last30))
                stat("All time", percent(s.allTime))
            }
            HStack {
                stat("Done days", "\(s.doneDays)")
                stat("Partially", "\(s.partialDays)")
                stat("Overdone", "\(s.overDays)")
            }
            Divider()
            Text("By weekday").font(.subheadline.weight(.semibold))
            bars(s.byWeekday.map { ($0.0, $0.1) })
            Divider()
            Text("By month").font(.subheadline.weight(.semibold))
            ForEach(s.byMonth, id: \.0) { month, count in
                HStack {
                    Text(month).font(.subheadline).frame(width: 90, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(habit.color)
                            .frame(width: max(4, g.size.width * CGFloat(count) / CGFloat(max(1, s.byMonth.map(\.1).max() ?? 1))))
                    }
                    .frame(height: 10)
                    Text("\(count)").font(.subheadline.monospacedDigit()).frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func bars(_ items: [(String, Int)]) -> some View {
        let top = max(1, items.map(\.1).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Text("\(item.1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4).fill(habit.color)
                        .frame(height: max(4, 60 * CGFloat(item.1) / CGFloat(top)))
                    Text(item.0).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Статистика привычки по отмеченным дням.
struct HabitStats {
    var currentStreak = 0, longestStreak = 0
    var last7 = 0.0, last30 = 0.0, allTime = 0.0
    var doneDays = 0, partialDays = 0, overDays = 0, thisWeek = 0
    var byWeekday: [(String, Int)] = []
    var byMonth: [(String, Int)] = []

    init(habit: Habit) {
        let cal = Calendar.current
        let today = HabitDay.today()
        let done = Set(habit.completions)
        func isDone(_ d: Date) -> Bool { done.contains(HabitDay.key(d)) }
        func day(_ back: Int) -> Date { cal.date(byAdding: .day, value: -back, to: today)! }

        // Текущая серия: от сегодня (или вчера, если сегодня ещё не отмечено) назад.
        var i = isDone(today) ? 0 : 1
        while isDone(day(i)) { currentStreak += 1; i += 1 }

        let dates = done.compactMap(HabitDay.date).sorted()
        var run = 0, prev: Date?
        for d in dates {
            run = (prev.flatMap { cal.dateComponents([.day], from: $0, to: d).day } == 1) ? run + 1 : 1
            longestStreak = max(longestStreak, run)
            prev = d
        }

        last7 = Double((0..<7).filter { isDone(day($0)) }.count) / 7
        last30 = Double((0..<30).filter { isDone(day($0)) }.count) / 30
        let start = cal.startOfDay(for: ([habit.createdAt] + dates).min() ?? today)
        let total = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        allTime = Double(done.count) / Double(max(1, total))

        doneDays = done.count
        partialDays = habit.partialDays.count
        overDays = habit.overDays.count
        thisWeek = habit.doneInWeek(of: today)

        let symbols = HabitGrid.weekdaySymbols()
        var counts = Array(repeating: 0, count: 7)
        for d in dates {
            let index = (cal.component(.weekday, from: d) - cal.firstWeekday + 7) % 7
            counts[index] += 1
        }
        byWeekday = zip(symbols, counts).map { ($0, $1) }

        let monthFormat = DateFormatter()
        monthFormat.setLocalizedDateFormatFromTemplate("MMM yyyy")
        var months: [(Date, Int)] = []
        for d in dates {
            let m = cal.dateInterval(of: .month, for: d)!.start
            if let last = months.last, last.0 == m { months[months.count - 1].1 += 1 } else { months.append((m, 1)) }
        }
        byMonth = months.suffix(12).reversed().map { (monthFormat.string(from: $0.0), $0.1) }
    }
}

// MARK: - Настройки привычек

struct HabitSettingsView: View {
    @ObservedObject var store: HabitStore
    @AppStorage(HabitSettings.Key.dayCutoffHour, store: AppGroup.defaults) private var cutoff = 0
    @AppStorage(HabitSettings.Key.titleSize, store: AppGroup.defaults) private var titleSize = 24.0
    @AppStorage(HabitSettings.Key.widgetWeeks, store: AppGroup.defaults) private var weeks = 4.0
    @AppStorage(HabitSettings.Key.buttonSize, store: AppGroup.defaults) private var buttonSize = 40.0
    @AppStorage(HabitSettings.Key.buttonInset, store: AppGroup.defaults) private var buttonInset = 7.0
    @AppStorage(HabitSettings.Key.gridInset, store: AppGroup.defaults) private var gridInset = 12.0
    @AppStorage(HabitSettings.Key.undoneOpacity, store: AppGroup.defaults) private var undoneOpacity = 0.13
    @AppStorage(HabitSettings.Key.partialPattern, store: AppGroup.defaults) private var pattern = PartialPattern.icon.rawValue
    @AppStorage(HabitSettings.Key.stripeWidth, store: AppGroup.defaults) private var stripeWidth = 6.0
    @AppStorage(HabitSettings.Key.doneStripeOpacity, store: AppGroup.defaults) private var doneStripeOpacity = 1.0
    @AppStorage(HabitSettings.Key.undoneStripeOpacity, store: AppGroup.defaults) private var undoneStripeOpacity = 0.13
    @AppStorage(HabitSettings.Key.partialSymbol, store: AppGroup.defaults) private var partialSymbol = "tortoise.fill"
    @AppStorage(HabitSettings.Key.overSymbol, store: AppGroup.defaults) private var overSymbol = "star.fill"
    @AppStorage(HabitSettings.Key.partialIconScale, store: AppGroup.defaults) private var partialIconScale = 0.55
    @AppStorage(HabitSettings.Key.overIconScale, store: AppGroup.defaults) private var overIconScale = 0.55
    @AppStorage(HabitSettings.Key.overIconDarker, store: AppGroup.defaults) private var overDarker = false
    @AppStorage(HabitSettings.Key.overIconDarkness, store: AppGroup.defaults) private var overDarkness = 0.35
    @AppStorage(HabitSettings.Key.gridBottomMargin, store: AppGroup.defaults) private var gridBottomMargin = 16.0
    @State private var hasAccess = ReminderSync.hasAccess

    private var previewStyle: HabitStyle {
        HabitStyle(undoneOpacity: undoneOpacity, partialPattern: PartialPattern(rawValue: pattern) ?? .icon,
                   stripeWidth: stripeWidth, doneStripeOpacity: doneStripeOpacity, undoneStripeOpacity: undoneStripeOpacity,
                   partialSymbol: partialSymbol.isEmpty ? "tortoise.fill" : partialSymbol,
                   overSymbol: overSymbol.isEmpty ? "star.fill" : overSymbol,
                   partialIconScale: partialIconScale, overIconScale: overIconScale,
                   overIconDarker: overDarker, overIconDarkness: overDarkness)
    }

    /// Все четыре состояния дня с текущими настройками.
    private var preview: some View {
        HStack(spacing: 10) {
            ForEach(HabitDayState.allCases) { state in
                VStack(spacing: 4) {
                    HabitCell(state: state, isToday: false, color: .blue, size: 40, style: previewStyle)
                    Text(state.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        Form {
            Section {
                if hasAccess {
                    Button("Sync with Reminders Now") { Task { await store.refresh() } }
                } else {
                    Button("Allow Access to Reminders") { Task { hasAccess = await ReminderSync.requestAccess() } }
                }
            } header: {
                RoundedHeader("Reminders")
            } footer: {
                Text("Completed linked reminders are added to habit history automatically.")
            }

            Section {
                Stepper(cutoff == 0 ? "A day ends at midnight" : "A day ends at \(cutoff):00 at night", value: $cutoff, in: 0...6)
            } header: {
                RoundedHeader("Day")
            } footer: {
                Text("Marks made before this hour count for the previous day.")
            }

            Section {
                Stepper("Title size: \(Int(titleSize)) pt", value: $titleSize, in: 12...36)
                Stepper("Weeks shown: \(Int(weeks))", value: $weeks, in: 1...8)
                Stepper("Button diameter: \(Int(buttonSize)) pt", value: $buttonSize, in: 24...60)
                Stepper("Button inset: \(Int(buttonInset)) pt", value: $buttonInset, in: 0...24)
                Stepper("Grid inset: \(Int(gridInset)) pt", value: $gridInset, in: 0...24)
            } header: {
                RoundedHeader("Widgets")
            } footer: {
                Text("Title size is the default for all habit widgets (one line; two lines are a third smaller) — each widget can override it. Button inset is from the top and right edges; grid inset is from the bottom, left and right edges.")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Not done opacity: \(Int(undoneOpacity * 100))%")
                    Slider(value: $undoneOpacity, in: 0.03...0.5)
                }
                Stepper("Page grid bottom margin: \(Int(gridBottomMargin)) pt", value: $gridBottomMargin, in: 0...200, step: 4)
                preview
            } header: {
                RoundedHeader("Days")
            } footer: {
                Text("Bottom margin: how close to the bottom of the screen the grid card on a habit page may grow.")
            }

            Section {
                Picker("Style", selection: $pattern) {
                    ForEach(PartialPattern.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if pattern == PartialPattern.diagonal.rawValue {
                    Stepper("Stripe width: \(Int(stripeWidth)) pt", value: $stripeWidth, in: 4...16)
                    VStack(alignment: .leading) {
                        Text("Done stripes opacity: \(Int(doneStripeOpacity * 100))%")
                        Slider(value: $doneStripeOpacity, in: 0.05...1)
                    }
                    VStack(alignment: .leading) {
                        Text("Not done stripes opacity: \(Int(undoneStripeOpacity * 100))%")
                        Slider(value: $undoneStripeOpacity, in: 0...1)
                    }
                }
                if pattern == PartialPattern.icon.rawValue {
                    SymbolField(title: "Icon", symbol: $partialSymbol,
                                presets: ["tortoise.fill", "circle.lefthalf.filled", "hare.fill", "drop.fill", "leaf.fill", "minus", "battery.50percent", "hourglass"])
                    VStack(alignment: .leading) {
                        Text("Icon size: \(Int(partialIconScale * 100))% of the day")
                        Slider(value: $partialIconScale, in: 0.2...0.9)
                    }
                }
                preview
            } header: {
                RoundedHeader("Partially Done")
            } footer: {
                Text("Icon style: the day has the not-done color and the icon the done color. Each habit can set its own icon color.")
            }

            Section {
                SymbolField(title: "Icon", symbol: $overSymbol,
                            presets: ["star.fill", "flame.fill", "bolt.fill", "plus", "sparkles", "crown.fill", "heart.fill", "trophy.fill"])
                VStack(alignment: .leading) {
                    Text("Icon size: \(Int(overIconScale * 100))% of the day")
                    Slider(value: $overIconScale, in: 0.2...0.9)
                }
                Toggle("Icon darker than the day", isOn: $overDarker)
                if overDarker {
                    VStack(alignment: .leading) {
                        Text("Darker by: \(Int(overDarkness * 100))%")
                        Slider(value: $overDarkness, in: 0.05...0.9)
                    }
                }
                preview
            } header: {
                RoundedHeader("Overdone")
            } footer: {
                Text("Off: the icon has the not-done (lighter) color. On: the habit color mixed with black. Each habit can set its own icon color.")
            }

            Section {
                ShareLink(item: HabitCSV.file(store.habits, name: "habits.csv")) { Label("Export All Habits (CSV)", systemImage: "square.and.arrow.up") }
            } header: {
                RoundedHeader("Export")
            } footer: {
                Text("Columns: habit_id, habit_name, date, status, note. Each habit keeps one ID even after relinking reminders.")
            }
        }
        .navigationTitle("Habit Settings")
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// Имя SF Symbol текстом и быстрый выбор из готовых.
struct SymbolField: View {
    let title: String
    @Binding var symbol: String
    let presets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                TextField("SF Symbol", text: $symbol)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Image(systemName: symbol.isEmpty ? "questionmark" : symbol).frame(width: 22)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(presets, id: \.self) { name in
                        Image(systemName: name).font(.title3)
                            .foregroundStyle(name == symbol ? Color.accentColor : .secondary)
                            .onTapGesture { symbol = name }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Настройки календаря

struct CalendarSettingsView: View {
    @AppStorage(CalendarSettings.Key.alertsEnabled, store: AppGroup.defaults) private var alertsEnabled = true
    @AppStorage(CalendarSettings.Key.keepAfterTap, store: AppGroup.defaults) private var keepAfterTap = true
    @AppStorage(CalendarSettings.Key.removeWhenMovedLater, store: AppGroup.defaults) private var removeMovedLater = true
    @AppStorage(CalendarSettings.Key.removeWhenDeleted, store: AppGroup.defaults) private var removeDeleted = false
    @AppStorage(CalendarSettings.Key.notificationTapOpensEvent, store: AppGroup.defaults) private var tapOpensEvent = false
    @AppStorage(CalendarSettings.Key.staleLabelMinutes, store: AppGroup.defaults) private var staleMinutes = 30
    @AppStorage(CalendarSettings.Key.cursorHex, store: AppGroup.defaults) private var cursorHex = CalendarSettings.defaultCursorHex
    @AppStorage(CalendarSettings.Key.defaultDayStart, store: AppGroup.defaults) private var dayStart = 6
    @AppStorage(CalendarSettings.Key.defaultDayEnd, store: AppGroup.defaults) private var dayEnd = 24

    var body: some View {
        Form {
            Section {
                Toggle("Alert Notifications", isOn: $alertsEnabled)
                Toggle("Keep Notification After Tap", isOn: $keepAfterTap)
                Toggle("Remove When Event Moves Later", isOn: $removeMovedLater)
                Toggle("Remove When Event Is Deleted", isOn: $removeDeleted)
                Picker("Tapping a Notification Opens", selection: $tapOpensEvent) {
                    Text("Calendar").tag(false)
                    Text("Event Details").tag(true)
                }
            } header: {
                RoundedHeader("Notifications")
            } footer: {
                Text("Notifications for events with alerts are scheduled \(CalendarSettings.alertDaysAhead) days ahead.")
            }
            Section {
                Picker("Default Day Start", selection: $dayStart) { ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) } }
                Picker("Default Day End", selection: $dayEnd) { ForEach(0...24, id: \.self) { Text("\($0):00").tag($0) } }
                Stepper("Show “synced N min ago” after \(staleMinutes) min", value: $staleMinutes, in: 5...240, step: 5)
                HexField(title: "Cursor Color", hex: $cursorHex)
            } header: {
                RoundedHeader("Widget")
            } footer: {
                Text("Default Day Start and End apply to calendar widgets whose Day start/end is set to “Default”.")
            }
        }
        .navigationTitle("Calendar Settings")
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
    }
}
