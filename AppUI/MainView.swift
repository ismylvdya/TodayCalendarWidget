import EventKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// Подзаголовок раздела скруглённым шрифтом — как названия списков в Reminders.
/// Цвет везде один (как в заголовках списков на главной), начало — на 34 pt от края экрана,
/// как у чекбокса на главной (18 pt от края плашки): в списке заголовок и так отступает на 16.
struct RoundedHeader: View {
    let title: String
    var inset: CGFloat = 2
    init(_ title: String, inset: CGFloat = 2) { self.title = title; self.inset = inset }

    var body: some View {
        Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(Color(.tertiaryLabel)).textCase(nil)
            .padding(.leading, inset)
    }
}

/// Заголовок страницы: крупно, по центру — одинаковый на всех экранах.
struct PageTitle: View {
    /// На вложенных экранах заголовок ниже, чем на главном (из-за кнопки «назад»).
    static let subpageRaise: CGFloat = 20
    /// Отступ первой строки заголовка от краёв содержимого на вложенных экранах — до правого
    /// края кнопки «назад» (и столько же справа). Следующие строки — на всю ширину.
    static let sideInset: CGFloat = 46
    static let font = UIFont.systemFont(ofSize: 34, weight: .bold).rounded

    let title: String
    var sideInset: CGFloat = 0
    init(_ title: String, sideInset: CGFloat = 0) { self.title = title; self.sideInset = sideInset }

    var body: some View {
        // Ширина содержимого страницы: экран без полей по 16.
        let full = UIScreen.main.bounds.width - 32
        let (first, rest) = Self.split(title, firstWidth: full - 2 * sideInset)
        VStack(spacing: 0) {
            Text(first).padding(.horizontal, sideInset)
            if !rest.isEmpty { Text(rest) }
        }
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// Первая строка — столько слов, сколько помещается в `firstWidth` (или до явного переноса);
    /// остальное — второй частью.
    static func split(_ title: String, firstWidth: CGFloat) -> (String, String) {
        if let nl = title.firstIndex(of: "\n") {
            return (String(title[..<nl]), String(title[title.index(after: nl)...]))
        }
        let words = title.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var first = words.first ?? ""
        var i = 1
        while i < words.count {
            let candidate = first + " " + words[i]
            if (candidate as NSString).size(withAttributes: [.font: font]).width > firstWidth { break }
            first = candidate; i += 1
        }
        return (first, words[i...].joined(separator: " "))
    }
}

extension UIFont {
    var rounded: UIFont {
        fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}

/// Заголовок страницы первой строкой списка или формы.
struct PageTitleRow: View {
    let title: String
    /// Подъём заголовка вложенных экранов до уровня заголовка на главном.
    var raise: CGFloat
    init(_ title: String, raise: CGFloat = PageTitle.subpageRaise) { self.title = title; self.raise = raise }

    var body: some View {
        // Вложенные экраны: первая строка не заходит под кнопку «назад», справа — так же.
        // Подъём — отрицательным верхним полем всего списка (.pageTitleRaise()), а не строки:
        // строка с отрицательным отступом обрезала верх заголовка.
        PageTitle(title, sideInset: raise > 0 ? PageTitle.sideInset : 0)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
    }
}

/// Экраны приложения. Все переходы — через один тип маршрута: смешение переходов по значению
/// и по экрану в одном стеке сбрасывало навигацию.
enum Route: Hashable {
    case habit(UUID), archive, habitSettings, calendarSettings
}

/// Главный экран: привычки, архив, настройки привычек и календаря.
struct MainView: View {
    @StateObject private var store = HabitStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var showingNewHabit = false
    /// Открыть привычку по ссылке из виджета или уведомления.
    var openHabit: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Длинное название не влезает в стандартный заголовок — свой, с переносом перед «&».
                PageTitleRow(appName.replacingOccurrences(of: " & ", with: "\n& "), raise: 0)
                Section {
                    // Порядок меняется удержанием и перетаскиванием строки.
                    ForEach(store.habits.filter { !$0.archived }) { habit in
                        HStack(spacing: 12) {
                            TodayCheckbox(habit: habit) {
                                store.set(habit.id, day: HabitDay.today(), state: habit.nextTap(habit.state(HabitDay.today())))
                            }
                            NavigationLink(value: Route.habit(habit.id)) { HabitRow(habit: habit) }
                        }
                    }
                    .onMove { store.moveActive(from: $0, to: $1) }
                    Button { showingNewHabit = true } label: { Label("New Habit", systemImage: "plus") }
                } header: {
                    RoundedHeader("Habits")
                }
                .listSectionSpacing(18)
                Section {
                    NavigationLink(value: Route.habitSettings) { PlainLabel("Habits on Reminders Settings", systemImage: "gear") }
                    let archived = store.habits.filter(\.archived)
                    if !archived.isEmpty {
                        NavigationLink(value: Route.archive) {
                            HStack {
                                PlainLabel("Archive", systemImage: "archivebox")
                                Spacer()
                                Text("\(archived.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(value: Route.calendarSettings) { PlainLabel("Calendar Enhancer Settings", systemImage: "gear") }
                } header: {
                    RoundedHeader("Calendar")
                }
            }
            // Потянуть вниз — на любой странице одинаково: база, Reminders, виджеты, уведомления.
            .refreshable { await store.forceRefresh() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .habit(let id): HabitDetailView(store: store, habitID: id)
                case .archive: ArchiveView(store: store)
                case .habitSettings: HabitSettingsView(store: store)
                case .calendarSettings: CalendarSettingsView(store: store)
                }
            }
            .sheet(isPresented: $showingNewHabit) { NewHabitView(store: store) }
        }
        .task { await store.refresh() }
        // Возврат в приложение: перечитать базу (виджет мог отметить день) и Reminders.
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        .onChange(of: openHabit) { _, id in if let id { path = [.habit(id)] } }
        .onAppear { if let openHabit { path = [.habit(openHabit)] } }
    }
}

/// Строка с иконкой цвета текста (в списке иконка Label иначе красится акцентным цветом).
struct PlainLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }

    var body: some View {
        Label { Text(title) } icon: { Image(systemName: systemImage).foregroundStyle(.primary) }
    }
}

/// Вложенная прокрутка страницы привычки. Высота сетки = от её прокрутки до конца ленты,
/// поэтому свернуть сетку = докрутить её вниз. Сдвиги страницы вниз, пока сетка выше
/// обычной, забираются у страницы и отдаются сетке (прямо в UIKit: программная прокрутка
/// SwiftUI во время жеста не срабатывает).
final class NestedScrolls {
    weak var grid: UIScrollView?
    /// Обычная высота подложки сетки.
    var gridBase: CGFloat = 0
    private weak var page: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var lastY: CGFloat = 0
    private var adjusting = false

    func attachPage(_ scrollView: UIScrollView) {
        guard scrollView !== page else { return }
        page = scrollView
        lastY = scrollView.contentOffset.y
        observation = scrollView.observe(\.contentOffset) { [weak self] sv, _ in self?.pageMoved(sv) }
    }

    private func pageMoved(_ page: UIScrollView) {
        guard !adjusting else { return }
        let y = page.contentOffset.y
        let top = -page.adjustedContentInset.top
        // Только прокрутка вниз и только ниже верха страницы (не отскок после «потянуть вниз»).
        let delta = y - max(lastY, top)
        lastY = y
        guard delta > 0, let grid else { return }
        // Сколько ещё докрутить сетку, чтобы её высота стала обычной.
        let rest = grid.contentSize.height + grid.adjustedContentInset.bottom - gridBase - grid.contentOffset.y
        let take = min(delta, max(0, rest))
        guard take > 0.5 else { return }
        adjusting = true
        grid.contentOffset.y += take
        page.contentOffset.y = y - take
        adjusting = false
        lastY = page.contentOffset.y
    }
}

/// Находит ближайший UIScrollView над собой (прокрутку, внутри которой стоит).
struct ScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.found = found
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) { view.found = found }

    final class FinderView: UIView {
        var found: (UIScrollView) -> Void = { _ in }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let v = view, !(v is UIScrollView) { view = v.superview }
            if let scroll = view as? UIScrollView { found(scroll) }
        }
    }
}

/// Степпер, у которого меняющееся значение в названии — в серой плашке, как поле ввода
/// (только не редактируется).
struct ValueStepper<V: Strideable>: View {
    let before: String
    let shown: String
    var after = ""
    @Binding var value: V
    let range: ClosedRange<V>
    let step: V.Stride

    init(_ before: String, shown: String, after: String = "", value: Binding<V>, in range: ClosedRange<V>, step: V.Stride) {
        self.before = before; self.shown = shown; self.after = after
        _value = value; self.range = range; self.step = step
    }

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack(spacing: 6) {
                Text(before)
                Text(shown).monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(.tertiarySystemFill)))
                if !after.isEmpty { Text(after) }
            }
        }
    }
}

/// Кружок цвета списка Reminders (значков списков EventKit не отдаёт).
struct ListDot: View {
    let listID: String

    var body: some View {
        if let list = ReminderSync.store.calendar(withIdentifier: listID) {
            Circle().fill(Color(cgColor: list.cgColor)).frame(width: 8, height: 8)
        }
    }
}

/// Чекбокс «сегодня выполнено» слева от привычки, как в Reminders.
/// У «Twice a day»: сделано — заполненный, дважды — заполненный в окружности.
struct TodayCheckbox: View {
    let habit: Habit
    let tap: () -> Void

    var body: some View {
        let state = habit.state(HabitDay.today())
        let twice = habit.twiceADay && state == .twice
        Button(action: tap) {
            ZStack {
                if twice {
                    Circle().strokeBorder(habit.color, lineWidth: 2.25).frame(width: 30, height: 30)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                } else {
                    Image(systemName: state == .none ? "circle" : "checkmark.circle.fill").font(.system(size: 24))
                }
            }
            .frame(width: 30, height: 30)
            .foregroundStyle(habit.color)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: state)
    }
}

struct ArchiveView: View {
    @ObservedObject var store: HabitStore

    var body: some View {
        List {
            PageTitleRow("Archive")
            Section {
                ForEach(store.habits.filter(\.archived)) { habit in
                    NavigationLink(value: Route.habit(habit.id)) { HabitRow(habit: habit) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, -PageTitle.subpageRaise, for: .scrollContent)
        .refreshable { await store.forceRefresh() }
    }
}

struct HabitRow: View {
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(habit.title).font(.system(.body, design: .rounded).weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
                    Button { choosingReminder = true } label: {
                        if let link {
                            HStack { ListDot(listID: link.listID); Text("Linked: \(link.titles.last ?? "")") }
                        } else {
                            Label("Link a Reminder…", systemImage: "link")
                        }
                    }
                } footer: {
                    Text("Without a reminder the habit is marked only in this app, its notifications and widgets.")
                }
                Section {
                    InputRow(title: "Name", placeholder: link?.titles.last ?? "optional", text: $name)
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
            .sheet(isPresented: $choosingReminder) {
                ReminderPickerView(linked: Set(store.habits.flatMap(\.links).map(\.reminderID) + [link?.reminderID].compactMap { $0 })) { link = $0 }
            }
        }
    }
}

// MARK: - Карточки страницы привычки

/// Карточка как в сгруппированном списке: подзаголовок и белая подложка со скруглением.
struct Card<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { RoundedHeader(title, inset: 18) }
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            if let footer { Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4) }
        }
    }
}

/// Строка ввода текста: название настройки слева, поле ввода в рамке справа.
struct InputRow: View {
    let title: String
    var placeholder = ""
    @Binding var text: String
    var monospaced = false
    var capitalized = false

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField(placeholder, text: $text)
                .font(monospaced ? .body.monospaced() : .body)
                .textInputAutocapitalization(capitalized ? .characters : .never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(.tertiarySystemFill)))
                .frame(maxWidth: 170)
        }
    }
}

/// Строка выбора в том же виде, что InputRow: название слева, плашка с меню справа.
struct SelectRow<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Menu {
                ForEach(options, id: \.0) { value, label in
                    Button { selection = value } label: {
                        if value == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection }?.1 ?? "")
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(.tertiarySystemFill)))
                .frame(maxWidth: 170)
            }
            .tint(.primary)
        }
    }
}

/// Поле для цвета «#RRGGBBAA» с образцом.
struct HexField: View {
    let title: String
    @Binding var hex: String
    /// С прозрачностью (#RRGGBBAA) или без (#RRGGBB).
    var alpha = true

    var body: some View {
        HStack {
            InputRow(title: title, placeholder: alpha ? "#RRGGBBAA" : "#RRGGBB", text: $hex, monospaced: true, capitalized: true)
            Circle().fill(Color(hex: hex) ?? .clear).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3)))
        }
    }
}

/// Свой цвет: переключатель, палитра и hex с прозрачностью.
struct OwnColorField: View {
    let title: String
    let hex: String?
    var fallback = "#FFFFFFFF"
    let set: (String?) -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { hex != nil }, set: { set($0 ? fallback : nil) }))
        if let hex {
            ColorPicker("Color", selection: Binding(get: { Color(hex: hex) ?? .white }, set: { set($0.hexString) }), supportsOpacity: true)
            HexField(title: "Hex", hex: Binding(get: { hex }, set: { if Color(hex: $0) != nil { set($0) } }))
        }
    }
}

/// Время напоминаний привычки (до 5 в день).
// MARK: - Страница привычки

struct HabitDetailView: View {
    @ObservedObject var store: HabitStore
    let habitID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var choosingReminder = false
    @State private var editingTitle = false
    @FocusState private var titleFocused: Bool
    @State private var noteDay: Date?
    @State private var noteText = ""
    /// Нижняя граница видимой области страницы — до неё может расти подложка сетки.
    @State private var pageBottom: CGFloat = 800
    /// Прокрутки страницы и сетки (UIKit): пока сетка раскрыта больше обычного, прокрутка
    /// страницы вниз сначала сворачивает её, и только потом листает страницу.
    @State private var scrolls = NestedScrolls()

    var body: some View {
        if let habit = store.habit(habitID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Заголовок — это и есть название: редактируется прямо здесь.
                    // Без своего названия в поле стоит название напоминания (обычным цветом); пока текст
                    // совпадает с ним, своё название не сохраняется — и следует переименованиям в Reminders.
                    Group {
                        if editingTitle {
                            // Название без переносов строк: Return просто закрывает клавиатуру.
                            TextField("Habit", text: Binding(get: { habit.title }, set: { raw in
                                let new = raw.replacingOccurrences(of: "\n", with: "")
                                var h = habit
                                h.name = new == h.links.last?.titles.last ? "" : new
                                store.update(h)
                                if raw.contains("\n") { titleFocused = false }
                            }), axis: .vertical)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .focused($titleFocused)
                                .onChange(of: titleFocused) { _, focused in if !focused { editingTitle = false } }
                                .onAppear { titleFocused = true }
                                .padding(.horizontal, PageTitle.sideInset)
                        } else {
                            // Нажатие — редактирование.
                            PageTitle(habit.title, sideInset: PageTitle.sideInset)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTitle = true }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, -PageTitle.subpageRaise)
                    .background(ScrollViewFinder { scrolls.attachPage($0) })

                    GrowingHistoryGrid(habit: habit, pageBottom: pageBottom, scrolls: scrolls,
                                       setState: { day, state in store.set(habitID, day: day, state: state) },
                                       editNote: { day in noteText = habit.note(day) ?? ""; noteDay = day })

                    // Заметка к привычке: поле во всю ширину, растёт по тексту.
                    if habit.showsNote {
                        TextField("Description", text: Binding(get: { habit.habitNote }, set: { var h = habit; h.habitNote = $0; store.update(h) }),
                                  axis: .vertical)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }

                    StatsCard(habit: habit)
                    settingsCard(habit)
                    remindersCard(habit)

                    Card {
                        ShareLink(item: HabitCSV.file([habit], name: "\(habit.title).csv")) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                        Divider()
                        Button {
                            var h = habit; h.archived.toggle(); store.update(h)
                            if h.archived { dismiss() }
                        } label: {
                            Label(habit.archived ? "Unarchive Habit" : "Archive Habit", systemImage: "archivebox")
                        }
                        Divider()
                        Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete Habit", systemImage: "trash") }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await store.forceRefresh() }
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
                ReminderPickerView(linked: Set(store.habits.flatMap(\.links).map(\.reminderID))) { picked in
                    var h = habit
                    if !h.links.contains(where: { $0.reminderID == picked.reminderID }) { h.links.append(picked) }
                    store.update(h)
                    Task { await store.refresh() }
                }
            }
        }
    }

    private func settingsCard(_ habit: Habit) -> some View {
        Card(title: "Habit Settings") {
            InputRow(title: "Name", placeholder: habit.links.last?.titles.last ?? "Habit",
                     text: Binding(get: { habit.name }, set: { var h = habit; h.name = $0; store.update(h) }))
            Divider()
            ColorPicker("Color", selection: Binding(get: { habit.color }, set: { var h = habit; h.colorHex = $0.hexString; store.update(h) }),
                        supportsOpacity: false)
            Divider()
            SelectRow(title: "Habit Type", options: [(false, "Good"), (true, "Bad")],
                      selection: Binding(get: { habit.harmful }, set: { var h = habit; h.harmful = $0; store.update(h) }))
            Divider()
            // Выключили — дни «дважды» остаются в истории, но считаются и рисуются как сделанные.
            Toggle("Twice a day", isOn: Binding(get: { habit.twiceADay }, set: {
                var h = habit; h.twiceADay = $0
                if !$0 { h.weeklyGoal = min(h.weeklyGoal, 7) }
                store.update(h)
            }))
            Divider()
            ValueStepper("Weekly goal:", shown: habit.weeklyGoal == 0 ? "off" : "\(habit.weeklyGoal)", after: habit.weeklyGoal == 0 ? "" : "times",
                         value: Binding(get: { habit.weeklyGoal }, set: { var h = habit; h.weeklyGoal = $0; store.update(h) }), in: 0...(habit.twiceADay ? 14 : 7), step: 1)
            Divider()
            Toggle("Show Description", isOn: Binding(get: { habit.showsNote }, set: { var h = habit; h.showsNote = $0; store.update(h) }))
            Divider()
            // Подгруппа: заголовок — как обычная строка, переключатели под ним — с отступом.
            Text("Own color for")
            Group {
                OwnColorField(title: "Partially Done Icon", hex: habit.partialIconHex) { var h = habit; h.partialIconHex = $0; store.update(h) }
                Divider()
                OwnColorField(title: "Overdone Icon", hex: habit.overIconHex) { var h = habit; h.overIconHex = $0; store.update(h) }
                Divider()
                if habit.twiceADay {
                    OwnColorField(title: "Twice Mark", hex: habit.twiceIconHex) { var h = habit; h.twiceIconHex = $0; store.update(h) }
                    Divider()
                }
                OwnColorField(title: "Note Icon", hex: habit.noteIconHex, fallback: "#8E8E93FF") { var h = habit; h.noteIconHex = $0; store.update(h) }
            }
            .padding(.leading, 20)

        }
    }

    private func remindersCard(_ habit: Habit) -> some View {
        Card(title: "Reminders",
             footer: "Linking a new reminder keeps the whole history under this habit. Unlinking or deleting never changes Reminders.") {
            ForEach(habit.links, id: \.reminderID) { link in
                HStack {
                    ListDot(listID: link.listID)
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
            Button { choosingReminder = true } label: { Label("Link a Reminder…", systemImage: "link") }
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
    /// Связь с прокруткой страницы (сворачивание раскрытой сетки).
    let scrolls: NestedScrolls
    let setState: (Date, HabitDayState) -> Void
    let editNote: (Date) -> Void

    private let gap: CGFloat = 6
    private let pad: CGFloat = 16
    /// Недель видно полностью; над ними — ещё одна, растворяющаяся.
    private let baseWeeks = 4
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
    /// Счётчик нажатий по дням — для отклика вибрацией.
    @State private var taps = 0
    /// Счётчик долгих нажатий — вибрация при открытии меню (у обычного меню своей нет).
    @State private var longPresses = 0

    private var cell: CGFloat { max(10, (width - 2 * pad - 6 * gap) / 7) }

    private var weekCount: Int {
        let first = ([habit.createdAt] + habit.completions.compactMap(HabitDay.date)).min() ?? Date()
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: HabitGrid.weekStart(first), to: HabitDay.today()).weekOfYear ?? 0
        return max(weeks + 1, baseWeeks) + 26   // запас ранних недель, чтобы было куда листать
    }

    var body: some View {
        let header: CGFloat = 20
        // N недель целиком и над ними (N+1)-я, растворяющаяся (как в виджете); строка дней
        // недели — сразу над верхом (N+1)-й недели.
        // Подложка ниже на четверть недели: сетка поднята, затухание сверху — на прежнем месте.
        let base = CGFloat(baseWeeks) * (cell + gap) + cell + pad - (cell + gap) / 4
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
                    // Лента заканчивается за полгода до первой отметки.
                    Text("Half a year before the first marked day")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .background(ScrollViewFinder { scrolls.grid = $0 })
                    // Недели и дни опознаются по дате, а не по номеру: иначе контекстное меню
                    // показывало чужую дату и ставило отметку не на тот день.
                    VStack(spacing: gap) {
                        ForEach(HabitGrid.weeks(count: weekCount, endingAt: today), id: \.first) { week in
                            HStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { i in
                                    if let day = week[i] {
                                        dayCell(day, today: today, style: style).id(HabitDay.key(day))
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: taps)
                    .sensoryFeedback(.impact(weight: .medium), trigger: longPresses)
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
            .onChange(of: base, initial: true) { scrolls.gridBase = base }
            .mask(edgeFade(top: offset > 1, bottom: contentHeight + bottomInset - offset - height > 1))
        }
        .padding(.top, pad)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { cardTop = $0 }
    }

    private func cellView(_ day: Date, today: Date, style: HabitStyle, size: CGFloat) -> HabitCell {
        HabitCell(state: habit.state(day), isToday: day == today, color: habit.color, size: size, style: style,
                  partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex, twiceIconHex: habit.twiceIconHex,
                  hasNote: habit.note(day) != nil,
                  noteIconHex: habit.noteIconHex,
                  opaqueBackground: Color(.secondarySystemGroupedBackground))
    }

    private func dayCell(_ day: Date, today: Date, style: HabitStyle) -> some View {
        let state = habit.state(day)
        let note = habit.note(day)
        // Обычное меню кнопки, а не контекстное: день не поднимается и не прыгает при закрытии,
        // меню просто открывается рядом. Нажатие — отметка, долгое нажатие — меню.
        // Содержимое меню строится при каждом открытии — дата в шапке всегда этого дня.
        // Рамка кнопки — габариты дня со значком заметки (он выступает за клетку), а форма —
        // ровно контур: иначе при закрытии меню значок обрезался по скруглённому квадрату.
        let shape = DayShape(cell: cell, hasNote: note != nil)
        let extra = shape.overhang
        return Menu {
            Section(day.formatted(date: .complete, time: .omitted)) {
                // Текущее состояние — бледное (пункт неактивен: выбрать его снова ничего не меняет).
                // «Дважды» в меню нет — только повторным нажатием.
                ForEach(HabitDayState.allCases.filter { $0 != .twice }) { option in
                    Button { setState(day, option) } label: {
                        Label { Text(option.title) } icon: { menuIcon(option, style, dim: option == state) }
                    }
                    .disabled(option == state)
                }
            }
            Section {
                Button { editNote(day) } label: { Label(note == nil ? "Add Note…" : "Edit Note…", systemImage: "doc") }
                if let note { Text(note) }
            }
        } label: {
            cellView(day, today: today, style: style, size: cell)
                .frame(width: cell + extra.width, height: cell + extra.height, alignment: .topLeading)
                .contentShape(.interaction, shape)
                .contentShape(.contextMenuPreview, shape)
        } primaryAction: {
            taps += 1
            setState(day, habit.nextTap(state))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        // Долгое нажатие открывает меню — отмечаем его вибрацией, как у контекстного меню.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in longPresses += 1 })
        .contentShape(.interaction, shape)
        .contentShape(.contextMenuPreview, shape)
        .contentShape(.hoverEffect, shape)
        .padding(.trailing, -extra.width)
        .padding(.bottom, -extra.height)
    }

    /// Сетка растворяется у краёв подложки, если за краем есть ещё недели. Сверху — как в виджете:
    /// 100% на уровне верха N-й недели, 0 — на высоту недели выше (со сдвигом на зазор).
    private func edgeFade(top: Bool, bottom: Bool) -> some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [
                .init(color: top ? .clear : .black, location: 0),
                .init(color: top ? .clear : .black, location: gap / (cell + gap)),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom).frame(height: cell + gap)
            Color.black
            LinearGradient(colors: [.black, bottom ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
        }
    }

    /// Иконка пункта меню одного размера для всех состояний: «не сделано» и «сделано» —
    /// скруглённые квадраты как клетки дней, остальные — иконки из настроек.
    /// `dim` — текущее состояние: иконка бледная (система бледнит у неактивного пункта только текст).
    /// Нарисованные иконки меню: тело сетки пересчитывается часто, а меню строится у каждого дня —
    /// без кэша рисование тормозило открытие меню.
    @MainActor private static var menuImages: [String: UIImage] = [:]

    @MainActor private func menuUIImage(_ state: HabitDayState, _ style: HabitStyle, dim: Bool) -> UIImage? {
        let key = "\(state)|\(style.partialSymbol)|\(style.overSymbol)|\(dim)"
        if let cached = Self.menuImages[key] { return cached }
        let image = drawMenuImage(state, style, dim: dim)
        Self.menuImages[key] = image
        return image
    }

    @MainActor private func drawMenuImage(_ state: HabitDayState, _ style: HabitStyle, dim: Bool) -> UIImage? {
        let side: CGFloat = 22
        let squircle = RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
        let content: AnyView = switch state {
        case .none: AnyView(squircle.strokeBorder(lineWidth: 2))
        case .done: AnyView(squircle.fill())
        case .partial: AnyView(Image(systemName: style.partialSymbol).resizable().scaledToFit())
        case .over: AnyView(Image(systemName: style.overSymbol).resizable().scaledToFit())
        case .twice: AnyView(squircle.fill())
        }
        let renderer = ImageRenderer(content: content.foregroundStyle(.black).frame(width: side, height: side))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        // Текущее состояние — бледная иконка, остальные — цвета текста меню.
        return dim ? image.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) : image.withRenderingMode(.alwaysTemplate)
    }

    @MainActor private func menuIcon(_ state: HabitDayState, _ style: HabitStyle, dim: Bool = false) -> Image {
        // Шаблонная картинка — цвета текста меню (в тёмной теме белая); текущее — бледная.
        menuUIImage(state, style, dim: dim).map { Image(uiImage: $0) } ?? Image(systemName: "square")
    }
}

/// Контур дня: скруглённый квадрат и, если есть заметка, значок за правым нижним углом
/// (как в HabitCell: значок размером 0.3 клетки, с прозрачной обводкой).
struct DayShape: Shape {
    let cell: CGFloat
    let hasNote: Bool

    private var badge: CGFloat { max(8, cell * 0.3) }

    /// Насколько значок заметки выступает за клетку вправо и вниз.
    var overhang: CGSize { hasNote ? CGSize(width: badge * 0.46, height: badge * 0.36) : .zero }

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: CGRect(x: 0, y: 0, width: cell, height: cell), cornerRadius: cell * 0.3, style: .continuous)
        if hasNote {
            let x = cell - badge * 0.64, y = cell - badge * 0.96
            p.addRoundedRect(in: CGRect(x: x, y: y, width: badge * 1.1, height: badge * 1.32),
                             cornerSize: CGSize(width: badge * 0.25, height: badge * 0.25))
        }
        return p
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
                if habit.twiceADay { stat("Twice streak", "\(s.twiceStreak) d") }
            }
            HStack {
                stat("Last 7 days", percent(s.last7))
                stat("Last 30 days", percent(s.last30))
                stat("All time", percent(s.allTime))
            }
            HStack {
                stat("Done days", "\(s.doneDays)")
                if habit.twiceADay { stat("Twice", "\(s.twiceDays)") }
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
    /// Только у «Twice a day»: дни «дважды» и их текущая серия.
    var twiceDays = 0, twiceStreak = 0
    var byWeekday: [(String, Int)] = []
    var byMonth: [(String, Int)] = []

    init(habit: Habit) {
        let cal = Calendar.current
        let today = HabitDay.today()
        let done = Set(habit.completions)
        func isDone(_ d: Date) -> Bool { done.contains(HabitDay.key(d)) }
        func day(_ back: Int) -> Date { cal.date(byAdding: .day, value: -back, to: today)! }

        let dates = done.compactMap(HabitDay.date).sorted()
        let start = cal.startOfDay(for: ([habit.createdAt] + dates).min() ?? today)
        let total = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1

        // Серии: у полезной привычки — дни подряд, когда она была; у вредной — когда её не было.
        func good(_ d: Date) -> Bool { habit.harmful ? !isDone(d) : isDone(d) }
        // Текущая: от сегодня (или вчера, если сегодня ещё не засчитано) назад, не раньше начала.
        var i = good(today) ? 0 : 1
        while i < total, good(day(i)) { currentStreak += 1; i += 1 }
        var run = 0
        for back in stride(from: total - 1, through: 0, by: -1) {
            run = good(day(back)) ? run + 1 : 0
            longestStreak = max(longestStreak, run)
        }

        // Проценты — от максимума: у «Twice a day» день «дважды» — 100%, один раз — 50%.
        let perDay = Double(habit.twiceADay ? 2 : 1)
        func units(_ back: Int) -> Int { habit.units(day(back)) }
        last7 = Double((0..<7).reduce(0) { $0 + units($1) }) / (7 * perDay)
        last30 = Double((0..<30).reduce(0) { $0 + units($1) }) / (30 * perDay)
        allTime = Double((0..<total).reduce(0) { $0 + units($1) }) / (Double(max(1, total)) * perDay)

        if habit.twiceADay {
            func twice(_ d: Date) -> Bool { habit.state(d) == .twice }
            var j = twice(today) ? 0 : 1
            while j < total, twice(day(j)) { twiceStreak += 1; j += 1 }
            twiceDays = habit.twiceDays.intersection(done).count
        }

        doneDays = done.count
        partialDays = habit.partialDays.count
        overDays = habit.overDays.count
        thisWeek = habit.doneInWeek(of: today)

        let symbols = HabitGrid.weekdaySymbols()
        // По дням недели — в разах: у «Twice a day» день «дважды» даёт 2.
        var counts = Array(repeating: 0, count: 7)
        for d in dates {
            let index = (cal.component(.weekday, from: d) - cal.firstWeekday + 7) % 7
            counts[index] += max(1, habit.units(d))
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
    @AppStorage(HabitSettings.Key.buttonInset, store: AppGroup.defaults) private var buttonInset = 12.0
    @AppStorage(HabitSettings.Key.gridInset, store: AppGroup.defaults) private var gridInset = 16.0
    @AppStorage(HabitSettings.Key.undoneOpacity, store: AppGroup.defaults) private var undoneOpacity = 0.15
    @AppStorage(HabitSettings.Key.partialPattern, store: AppGroup.defaults) private var pattern = PartialPattern.icon.rawValue
    @AppStorage(HabitSettings.Key.stripeWidth, store: AppGroup.defaults) private var stripeWidth = 6.0
    @AppStorage(HabitSettings.Key.doneStripeOpacity, store: AppGroup.defaults) private var doneStripeOpacity = 1.0
    @AppStorage(HabitSettings.Key.undoneStripeOpacity, store: AppGroup.defaults) private var undoneStripeOpacity = 0.13
    @AppStorage(HabitSettings.Key.partialSymbol, store: AppGroup.defaults) private var partialSymbol = "tortoise.fill"
    @AppStorage(HabitSettings.Key.overSymbol, store: AppGroup.defaults) private var overSymbol = "bolt.fill"
    @AppStorage(HabitSettings.Key.partialIconScale, store: AppGroup.defaults) private var partialIconScale = 0.65
    @AppStorage(HabitSettings.Key.overIconScale, store: AppGroup.defaults) private var overIconScale = 0.65
    @AppStorage(HabitSettings.Key.overIconDarker, store: AppGroup.defaults) private var overDarker = true
    @AppStorage(HabitSettings.Key.overIconDarkness, store: AppGroup.defaults) private var overDarkness = 0.65
    @AppStorage(HabitSettings.Key.gridBottomMargin, store: AppGroup.defaults) private var gridBottomMargin = 1.0
    @AppStorage(HabitSettings.Key.twicePattern, store: AppGroup.defaults) private var twicePattern = TwicePattern.innerSquare.rawValue
    @AppStorage(HabitSettings.Key.twiceSymbol, store: AppGroup.defaults) private var twiceSymbol = "2.circle.fill"
    @AppStorage(HabitSettings.Key.twiceIconScale, store: AppGroup.defaults) private var twiceIconScale = 0.65
    @AppStorage(HabitSettings.Key.twiceInnerSize, store: AppGroup.defaults) private var twiceInnerSize = 0.55
    @AppStorage(HabitSettings.Key.twiceDarker, store: AppGroup.defaults) private var twiceDarker = true
    @AppStorage(HabitSettings.Key.twiceDarkness, store: AppGroup.defaults) private var twiceDarkness = 0.65
    @State private var hasAccess = ReminderSync.hasAccess

    private var previewStyle: HabitStyle {
        HabitStyle(undoneOpacity: undoneOpacity, partialPattern: PartialPattern(rawValue: pattern) ?? .icon,
                   stripeWidth: stripeWidth, doneStripeOpacity: doneStripeOpacity, undoneStripeOpacity: undoneStripeOpacity,
                   partialSymbol: partialSymbol.isEmpty ? "tortoise.fill" : partialSymbol,
                   overSymbol: overSymbol.isEmpty ? "bolt.fill" : overSymbol,
                   partialIconScale: partialIconScale, overIconScale: overIconScale,
                   overIconDarker: overDarker, overIconDarkness: overDarkness,
                   twicePattern: TwicePattern(rawValue: twicePattern) ?? .innerSquare,
                   twiceSymbol: twiceSymbol.isEmpty ? "2.circle.fill" : twiceSymbol,
                   twiceIconScale: twiceIconScale, twiceInnerSize: twiceInnerSize,
                   twiceDarker: twiceDarker, twiceDarkness: twiceDarkness)
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
            PageTitleRow("Habits on Reminders Settings")

            // Синхронизация — потянуть вниз; здесь только запрос доступа, если его нет.
            if !hasAccess {
                Section {
                    Button { Task { hasAccess = await ReminderSync.requestAccess() } } label: {
                        Label("Allow Access to Reminders", systemImage: "lock.open")
                    }
                }
            }

            Section {
                ValueStepper("A day ends at", shown: cutoff == 0 ? "midnight" : "\(cutoff):00", after: cutoff == 0 ? "" : "at night",
                             value: $cutoff, in: 0...6, step: 1)
            } header: {
                RoundedHeader("End of Day")
            } footer: {
                Text("Marks made before this hour count for the previous day.")
            }

            Section {
                ValueStepper("Title size:", shown: "\(Int(titleSize))", after: "pt", value: $titleSize, in: 12...36, step: 1)
                ValueStepper("Weeks shown:", shown: "\(Int(weeks))", value: $weeks, in: 1...8, step: 1)
                ValueStepper("Button diameter:", shown: "\(Int(buttonSize))", after: "pt", value: $buttonSize, in: 24...60, step: 1)
                ValueStepper("Button inset:", shown: "\(Int(buttonInset))", after: "pt", value: $buttonInset, in: 0...24, step: 1)
                ValueStepper("Grid inset:", shown: "\(Int(gridInset))", after: "pt", value: $gridInset, in: 0...24, step: 1)
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
                preview
            } header: {
                RoundedHeader("Days")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Bottom margin: \(Int(gridBottomMargin)) pt")
                    Slider(value: $gridBottomMargin, in: -15...200, step: 1)
                }
            } header: {
                RoundedHeader("Habit Page Grid")
            } footer: {
                Text("Bottom margin: how close to the bottom of the screen the grid card may grow.")
            }

            Section {
                Picker("Style", selection: $pattern) {
                    ForEach(PartialPattern.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if pattern == PartialPattern.diagonal.rawValue {
                    ValueStepper("Stripe width:", shown: "\(Int(stripeWidth))", after: "pt", value: $stripeWidth, in: 4...16, step: 1)
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
                            presets: ["bolt.fill", "star.fill", "flame.fill", "plus", "sparkles", "crown.fill", "heart.fill", "trophy.fill"])
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
                Picker("Style", selection: $twicePattern) {
                    ForEach(TwicePattern.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if twicePattern == TwicePattern.icon.rawValue {
                    SymbolField(title: "Icon", symbol: $twiceSymbol,
                                presets: ["2.circle.fill", "2.square.fill", "checkmark.circle.fill", "circle.circle.fill", "plus.circle.fill", "star.fill", "flame.fill", "repeat"])
                    VStack(alignment: .leading) {
                        Text("Icon size: \(Int(twiceIconScale * 100))% of the day")
                        Slider(value: $twiceIconScale, in: 0.2...0.9)
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("Inner square size: \(Int((twiceInnerSize * 100).rounded()))% of the day")
                        Slider(value: $twiceInnerSize, in: 0.2...0.85)
                    }
                }
                Toggle("Darker than the day", isOn: $twiceDarker)
                if twiceDarker {
                    VStack(alignment: .leading) {
                        Text("Darker by: \(Int(twiceDarkness * 100))%")
                        Slider(value: $twiceDarkness, in: 0.05...0.9)
                    }
                }
                preview
            } header: {
                RoundedHeader("Twice a Day")
            } footer: {
                Text("For habits with “Twice a day” on: tapping a day done once marks it done twice. Off: the mark has the not-done (lighter) color. Each habit can set its own mark color.")
            }

            Section {
                ShareLink(item: HabitCSV.file(store.habits, name: "habits.csv")) { Label("Export All Habits (CSV)", systemImage: "square.and.arrow.up") }
            } header: {
                RoundedHeader("Export")
            } footer: {
                Text("Columns: habit_id, habit_name, date, status, note. Each habit keeps one ID even after relinking reminders.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, -PageTitle.subpageRaise, for: .scrollContent)
        .refreshable { await store.forceRefresh() }
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
                InputRow(title: title, placeholder: "SF Symbol", text: $symbol, monospaced: true)
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
    @ObservedObject var store: HabitStore
    @AppStorage(CalendarSettings.Key.alertsEnabled, store: AppGroup.defaults) private var alertsEnabled = true
    @AppStorage(CalendarSettings.Key.keepAfterTap, store: AppGroup.defaults) private var keepAfterTap = true
    @AppStorage(CalendarSettings.Key.removeWhenMovedLater, store: AppGroup.defaults) private var removeMovedLater = true
    @AppStorage(CalendarSettings.Key.removeWhenDeleted, store: AppGroup.defaults) private var removeDeleted = true
    @AppStorage(CalendarSettings.Key.notificationTapOpensEvent, store: AppGroup.defaults) private var tapOpensEvent = false
    @AppStorage(CalendarSettings.Key.staleLabelMinutes, store: AppGroup.defaults) private var staleMinutes = 30
    @AppStorage(CalendarSettings.Key.cursorHex, store: AppGroup.defaults) private var cursorHex = CalendarSettings.defaultCursorHex
    @AppStorage(CalendarSettings.Key.cursorOverEventOpacity, store: AppGroup.defaults) private var cursorOverEvent = 0.7
    @AppStorage(CalendarSettings.Key.defaultDayStart, store: AppGroup.defaults) private var dayStart = 6
    @AppStorage(CalendarSettings.Key.defaultDayEnd, store: AppGroup.defaults) private var dayEnd = 24

    var body: some View {
        Form {
            PageTitleRow("Calendar Enhancer Settings")
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
                ValueStepper("Show “synced N min ago” after", shown: "\(staleMinutes)", after: "min", value: $staleMinutes, in: 5...240, step: 5)
                HexField(title: "Cursor Color", hex: Binding(get: { cursorHex == "#E9534CFF" ? CalendarSettings.defaultCursorHex : cursorHex },
                                                             set: { cursorHex = String($0.prefix(7)) }), alpha: false)
                VStack(alignment: .leading) {
                    Text("Cursor over events: \(Int((cursorOverEvent * 100).rounded()))%")
                    Slider(value: $cursorOverEvent, in: 0.1...1)
                }
            } header: {
                RoundedHeader("Widget")
            } footer: {
                Text("Default Day Start and End apply to calendar widgets whose Day start/end is set to “Default”.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, -PageTitle.subpageRaise, for: .scrollContent)
        .refreshable { await store.forceRefresh() }
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
    }
}
