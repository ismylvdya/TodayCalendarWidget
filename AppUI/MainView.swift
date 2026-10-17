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

    /// Высота заголовка: одна строка или две.
    static func height(_ title: String, sideInset: CGFloat = PageTitle.sideInset) -> CGFloat {
        let full = UIScreen.main.bounds.width - 32
        let lines: CGFloat = split(title, firstWidth: full - 2 * sideInset).1.isEmpty ? 1 : 2
        return lines * font.lineHeight
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

/// Короткий заголовок в панели, когда большой ушёл под неё (как у стандартного большого
/// заголовка iOS), и плотнее, чем у системы, затухание содержимого под панелью.
struct CollapsingTitle: ViewModifier {
    let title: String
    /// Когда большой заголовок почти весь ушёл под панель, показываем короткий.
    let threshold: CGFloat
    /// Короткий заголовок уменьшается, пока не влезет в строку; это — наименьший масштаб.
    var minScale: CGFloat = 0.5
    @State private var away = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > threshold } action: { _, value in
                withAnimation(.easeInOut(duration: 0.2)) { away = value }
            }
            .overlay(alignment: .top) { TopFade() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(minScale)
                        .opacity(away ? 1 : 0)
                }
            }
    }
}

/// Затухание под панелью: фон страницы, плотный у верха и сходящий на нет к низу панели.
struct TopFade: View {
    var body: some View {
        GeometryReader { g in
            let top = g.safeAreaInsets.top
            // Только над панелью: ниже стоит большой заголовок, его не притеняем.
            LinearGradient(stops: [
                .init(color: Color(.systemGroupedBackground).opacity(0.85), location: 0),
                .init(color: Color(.systemGroupedBackground).opacity(0.5), location: 0.75),
                .init(color: Color(.systemGroupedBackground).opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: top)
            .offset(y: -top)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// `bigTitle` — текст большого заголовка (по нему — сколько в нём строк).
    func collapsingTitle(_ title: String, bigTitle: String? = nil, minScale: CGFloat = 0.5) -> some View {
        modifier(CollapsingTitle(title: title, threshold: PageTitle.height(bigTitle ?? title) * 0.75, minScale: minScale))
    }

    /// Страница-список с большим заголовком: заголовок рисуется поверх списка (на месте пустой
    /// строки `PageTitleRow`) и всегда виден — строку списка система иногда не рисовала
    /// (при обновлении и после него на её месте оставалась пустота).
    func listPageTitle(_ title: String, sideInset: CGFloat, rowY: CGFloat?) -> some View {
        modifier(FloatingPageTitle(title: title, sideInset: sideInset, rowY: rowY))
    }
}

/// Большой заголовок поверх списка: идёт за своей строкой, а когда её нет — за прокруткой.
struct FloatingPageTitle: ViewModifier {
    let title: String
    let sideInset: CGFloat
    /// Верх строки заголовка в списке (nil — ещё не известен).
    let rowY: CGFloat?
    @State private var offset: CGFloat = 0
    @State private var offsetAtRowY: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: PageTitleRow.space)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in offset = value }
            .onChange(of: rowY) { offsetAtRowY = offset }
            .overlay(alignment: .top) {
                if let rowY {
                    // Как содержимое страницы привычки: просто уезжает под панель и скрывается там,
                    // без отдельного затухания.
                    GeometryReader { g in
                        // Высота панели — из безопасной области самого чтения (без ignoresSafeArea,
                        // иначе она нулевая). Слой поднят на неё, чтобы маска накрывала и панель.
                        let top = g.safeAreaInsets.top
                        PageTitle(title, sideInset: sideInset)
                            .padding(.horizontal, 16)
                            .offset(y: rowY - (offset - offsetAtRowY))
                            .frame(width: g.size.width, height: g.size.height + top, alignment: .top)
                            // Как у содержимого под панелью на странице привычки: виден до низа
                            // панели, гаснет к кнопке «назад», у Dynamic Island его уже нет.
                            .mask(alignment: .top) {
                                VStack(spacing: 0) {
                                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.45),
                                                           .init(color: .black, location: 1)],
                                                   startPoint: .top, endPoint: .bottom)
                                        .frame(height: top)
                                    Color.black
                                }
                            }
                            .offset(y: -top)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

/// Место большого заголовка первой строкой списка или формы: сам заголовок невидим
/// (его рисует `listPageTitle` поверх списка), строка только держит место и сообщает положение.
struct PageTitleRow: View {
    static let space = "pageTitle"
    let title: String
    /// Подъём заголовка вложенных экранов до уровня заголовка на главном.
    var raise: CGFloat
    @Binding var y: CGFloat?
    init(_ title: String, raise: CGFloat = PageTitle.subpageRaise, y: Binding<CGFloat?>) {
        self.title = title; self.raise = raise; _y = y
    }

    var body: some View {
        // Вложенные экраны: первая строка не заходит под кнопку «назад», справа — так же.
        // Подъём — отрицательным верхним полем всего списка, а не строки: строка с
        // отрицательным отступом обрезала верх заголовка.
        PageTitle(title, sideInset: raise > 0 ? PageTitle.sideInset : 0)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { y = $0 }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
    }
}

/// Экраны приложения. Все переходы — через один тип маршрута: смешение переходов по значению
/// и по экрану в одном стеке сбрасывало навигацию.
enum Route: Hashable {
    case habit(UUID), archive, trash, habitSettings, calendarSettings
}

/// Главный экран: привычки, архив, настройки привычек и календаря.
struct MainView: View {
    @StateObject private var store = HabitStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var showingNewHabit = false
    /// Заметка к сегодняшнему дню из меню чекбокса.
    @State private var noteHabit: UUID?
    @State private var noteText = ""
    /// Новая причина из меню дня: для какой привычки и дня.
    @State private var reasonFor: (UUID, Date)?
    @State private var reasonText = ""
    /// Длинное название не влезает в стандартный заголовок — свой, с переносом перед «&».
    private let mainTitle = appName.replacingOccurrences(of: " & ", with: "\n& ")
    @State private var titleY: CGFloat?
    /// Открыть привычку по ссылке из виджета или уведомления.
    var openHabit: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Длинное название не влезает в стандартный заголовок — свой, с переносом перед «&».
                PageTitleRow(mainTitle, raise: 0, y: $titleY)
                Section {
                    // Порядок меняется удержанием и перетаскиванием строки.
                    ForEach(store.habits.filter { !$0.archived && !$0.isTrashed }) { habit in
                        HStack(spacing: 12) {
                            TodayCheckbox(habit: habit,
                                          tap: { store.set(habit.id, day: HabitDay.today(), state: habit.nextTap(habit.state(HabitDay.today()))) },
                                          setState: { store.set(habit.id, day: HabitDay.today(), state: $0) },
                                          editNote: { noteText = habit.note(HabitDay.today()) ?? ""; noteHabit = habit.id },
                                          reasons: store.reasons,
                                          setReason: { store.setReason(habit.id, day: HabitDay.today(), reason: $0) },
                                          newReason: { reasonText = ""; reasonFor = (habit.id, HabitDay.today()) })
                            NavigationLink(value: Route.habit(habit.id)) {
                                HabitRow(habit: habit, longGap: habit.longGap(reasons: store.reasons) != nil)
                            }
                        }
                    }
                    .onMove { store.moveActive(from: $0, to: $1) }
                    Button { showingNewHabit = true } label: { PlainLabel("New Habit", systemImage: "plus", tinted: true) }
                } header: {
                    RoundedHeader("Habits")
                }
                .listSectionSpacing(18)
                Section {
                    NavigationLink(value: Route.habitSettings) { PlainLabel("Habits on Reminders Settings", systemImage: "gear") }
                    let archived = store.habits.filter { $0.archived && !$0.isTrashed }
                    if !archived.isEmpty {
                        NavigationLink(value: Route.archive) {
                            HStack {
                                PlainLabel("Archive", systemImage: "archivebox")
                                Spacer()
                                Text("\(archived.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    let trashed = store.habits.filter(\.isTrashed)
                    if !trashed.isEmpty {
                        NavigationLink(value: Route.trash) {
                            HStack {
                                PlainLabel("Trash", systemImage: "trash")
                                Spacer()
                                Text("\(trashed.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(value: Route.calendarSettings) { PlainLabel("Calendar Enhancer Settings", systemImage: "gear") }
                } header: {
                    RoundedHeader("Calendar")
                } footer: {
                    // Внизу главной — версия со сборкой и подпись.
                    VStack(spacing: 2) {
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        Text("Vibecoded by chumbulev")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            // Потянуть вниз — на любой странице одинаково: база, Reminders, виджеты, уведомления.
            .refreshable { await store.forceRefresh() }
            // Заголовок выше на половину высоты его шрифта (34 pt).
            .contentMargins(.top, -PageTitle.font.pointSize / 2, for: .scrollContent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .listPageTitle(mainTitle, sideInset: 0, rowY: titleY)
            // Короткого заголовка в панели на главной нет — только затухание под ней. Невидимый
            // элемент держит панель той же высоты, что на других страницах: без него панель
            // сжималась, и заголовок с затуханием поднимались выше.
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
            .overlay(alignment: .top) { TopFade() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .habit(let id): HabitDetailView(store: store, habitID: id)
                case .archive: ArchiveView(store: store)
                case .trash: ArchiveView(store: store, trash: true)
                case .habitSettings: HabitSettingsView(store: store)
                case .calendarSettings: CalendarSettingsView(store: store)
                }
            }
            .sheet(isPresented: $showingNewHabit) { NewHabitView(store: store) }
            .alert(HabitDay.today().formatted(date: .abbreviated, time: .omitted),
                   isPresented: Binding(get: { noteHabit != nil }, set: { if !$0 { noteHabit = nil } })) {
                TextField("Note", text: $noteText)
                Button("Save") {
                    if let id = noteHabit, var h = store.habit(id) { h.setNote(noteText, day: HabitDay.today()); store.update(h) }
                    noteHabit = nil
                }
                Button("Cancel", role: .cancel) { noteHabit = nil }
            }
            .newReasonAlert(store: store, target: $reasonFor, text: $reasonText)
        }
        .task { await store.refresh() }
        // Возврат в приложение: перечитать базу (виджет мог отметить день) и Reminders.
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        // Ушла последняя привычка из архива или корзины (удалили, вернули, разархивировали) —
        // вместо пустого списка сразу на главную.
        .onChange(of: path) { leaveEmptyList() }
        .onChange(of: store.habits) { leaveEmptyList() }
        .onChange(of: openHabit) { _, id in if let id { path = [.habit(id)] } }
        .onAppear { if let openHabit { path = [.habit(openHabit)] } }
    }
}

extension MainView {
    private func leaveEmptyList() {
        let empty: Bool
        switch path.last {
        case .archive: empty = !store.habits.contains { $0.archived && !$0.isTrashed }
        case .trash: empty = !store.habits.contains(where: \.isTrashed)
        default: return
        }
        if empty { path.removeAll() }
    }
}

extension View {
    /// Новая причина из меню дня: добавляется в общий список и сразу ставится этому дню.
    func newReasonAlert(store: HabitStore, target: Binding<(UUID, Date)?>, text: Binding<String>) -> some View {
        alert("New Reason", isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })) {
            TextField("Reason", text: text)
            Button("Add") {
                if let (habit, day) = target.wrappedValue, let id = store.addReason(text.wrappedValue) {
                    store.setReason(habit, day: day, reason: id)
                }
                target.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { target.wrappedValue = nil }
        } message: {
            Text("Added to the reasons of all habits (Habits on Reminders Settings → Why Not Done).")
        }
    }
}

/// Строка с иконкой цвета текста (в списке иконка Label иначе красится акцентным цветом).
/// Иконка — по центру столбца шириной с сегодняшний день у привычек, текст — там же, где
/// начинаются названия привычек.
struct PlainLabel: View {
    @AppStorage(HabitSettings.Key.mainSquircle, store: AppGroup.defaults) private var squircle = true
    @AppStorage(HabitSettings.Key.mainSquircleSize, store: AppGroup.defaults) private var squircleSize = 32.0
    @AppStorage(HabitSettings.Key.mainCheckboxSize, store: AppGroup.defaults) private var checkboxSize = 30.0
    let title: String
    let systemImage: String
    /// Иконка цвета акцента (у кнопок), а не текста.
    var tinted = false
    init(_ title: String, systemImage: String, tinted: Bool = false) {
        self.title = title; self.systemImage = systemImage; self.tinted = tinted
    }

    var body: some View {
        HStack(spacing: 12) {
            // Размер — как у иконки Label в списке (она крупнее текста).
            Image(systemName: systemImage)
                .imageScale(.large)
                .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: squircle ? squircleSize : checkboxSize)
            Text(title)
        }
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

    /// Страницу — к началу (после слияния: видно итоговую сетку).
    func scrollPageToTop() {
        guard let page else { return }
        adjusting = true
        page.setContentOffset(CGPoint(x: 0, y: -page.adjustedContentInset.top), animated: true)
        adjusting = false
        lastY = -page.adjustedContentInset.top
    }
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

/// Привязанные напоминания (с кнопкой отвязать) и «Link a Reminder…» — в карточке привычки
/// и при создании новой.
struct ReminderLinksList: View {
    let links: [ReminderLink]
    let remove: (String) -> Void
    let add: () -> Void

    var body: some View {
        ForEach(links, id: \.reminderID) { link in
            HStack {
                ListDot(listID: link.listID)
                VStack(alignment: .leading) {
                    Text(link.titles.last ?? "Reminder")
                    if link.titles.count > 1 {
                        Text("Also known as: " + link.titles.dropLast().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(role: .destructive) { remove(link.reminderID) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
            }
            Divider()
        }
        Button(action: add) { Label("Link a Reminder…", systemImage: "link") }
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

/// Сегодняшний день слева от привычки — та же клетка, что в сетке на её странице: те же
/// отметки, значки и меню. Нажатие — следующая отметка, долгое нажатие — меню дня.
struct TodayCheckbox: View {
    /// Ширина столбца слева на главной — размер выбранного вида (день или чекбокс).
    static var size: CGFloat {
        CGFloat(HabitSettings.mainSquircle ? HabitSettings.mainSquircleSize : HabitSettings.mainCheckboxSize)
    }
    let habit: Habit
    let tap: () -> Void
    let setState: (HabitDayState) -> Void
    let editNote: () -> Void
    let reasons: [SkipReason]
    let setReason: (UUID?) -> Void
    let newReason: () -> Void
    @State private var longPresses = 0
    @AppStorage(HabitSettings.Key.mainSquircle, store: AppGroup.defaults) private var squircle = true
    @AppStorage(HabitSettings.Key.mainSquircleSize, store: AppGroup.defaults) private var squircleSize = 32.0
    @AppStorage(HabitSettings.Key.mainCheckboxSize, store: AppGroup.defaults) private var checkboxSize = 30.0

    var body: some View {
        if squircle { day } else { checkbox }
    }

    /// Круглый чекбокс (по выбору в настройках) — тот же, что в виджетах.
    private var checkbox: some View {
        let today = HabitDay.today()
        let state = habit.state(today)
        return Menu {
            DayMenuItems(habit: habit, day: today, style: HabitSettings.style, setState: setState, editNote: editNote,
                         reasons: reasons, setReason: setReason, newReason: newReason)
        } label: {
            RoundCheckbox(habit: habit, size: CGFloat(checkboxSize), today: today)
                .contentShape(Circle())
        } primaryAction: {
            tap()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in longPresses += 1 })
        .sensoryFeedback(.impact(weight: .light), trigger: state)
        .sensoryFeedback(.impact(weight: .medium), trigger: longPresses)
    }

    private var day: some View {
        let today = HabitDay.today()
        let state = habit.state(today)
        let size = CGFloat(squircleSize)
        // Сегодня знака вопроса нет (день ещё идёт), значок может быть только у заметки.
        let shape = DayShape(cell: size, hasNote: habit.note(today) != nil, hasQuestion: false)
        let extra = shape.overhang
        return Menu {
            DayMenuItems(habit: habit, day: today, style: HabitSettings.style, setState: setState, editNote: editNote,
                         reasons: reasons, setReason: setReason, newReason: newReason)
        } label: {
            HabitCell(state: state, isToday: true, color: habit.color, size: size, style: HabitSettings.style,
                      partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex, twiceIconHex: habit.twiceIconHex,
                      hasNote: habit.note(today) != nil, noteIconHex: habit.noteIconHex,
                      opaqueBackground: Color(.secondarySystemGroupedBackground))
                .frame(width: size + extra.width, height: size + extra.height, alignment: .topLeading)
                .contentShape(.interaction, shape)
                .contentShape(.contextMenuPreview, shape)
        } primaryAction: {
            tap()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in longPresses += 1 })
        .padding(.trailing, -extra.width)
        .padding(.bottom, -extra.height)
        .sensoryFeedback(.impact(weight: .light), trigger: state)
        .sensoryFeedback(.impact(weight: .medium), trigger: longPresses)
    }
}

/// Архив или корзина: список привычек, по нажатию — их страница.
struct ArchiveView: View {
    @ObservedObject var store: HabitStore
    var trash = false
    @State private var titleY: CGFloat?

    var body: some View {
        List {
            PageTitleRow(trash ? "Trash" : "Archive", y: $titleY)
            Section {
                ForEach(store.habits.filter { trash ? $0.isTrashed : $0.archived && !$0.isTrashed }) { habit in
                    NavigationLink(value: Route.habit(habit.id)) { HabitRow(habit: habit) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .listPageTitle(trash ? "Trash" : "Archive", sideInset: PageTitle.sideInset, rowY: titleY)
        .collapsingTitle(trash ? "Trash" : "Archive")
        .contentMargins(.top, -PageTitle.subpageRaise, for: .scrollContent)
        .refreshable { await store.forceRefresh() }
    }
}

struct HabitRow: View {
    let habit: Habit
    /// Идёт долгий пропуск по одной причине — восклицательный знак у названия.
    var longGap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(habit.title).font(.system(.body, design: .rounded).weight(.semibold))
                if longGap { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let done = habit.doneInWeek(of: HabitDay.today())
        let goal = habit.weeklyGoal > 0 ? "\(done)/\(habit.weeklyGoal)" : "\(done)"
        return "\(goal) this week · " + (habit.links.isEmpty ? "manual" : "Reminders")
    }
}

/// Плашка долгого пропуска на странице привычки: что случилось и что можно поменять.
struct LongGapBanner: View {
    let habitTitle: String
    let gap: LongGap
    let dismiss: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Long Gap").font(.system(.title3, design: .rounded).weight(.bold))
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .foregroundStyle(.orange)
                Text("\(habitTitle): “\(gap.reason.title)” \(gap.days) days in a row")
                    .font(.system(.headline, design: .rounded))
                Text(gap.reason.kind.diagnosis + " Change the habit, not your willpower:").font(.subheadline)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(gap.reason.kind.ways, id: \.self) { way in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(way)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Got It", action: dismiss).font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

// MARK: - Новая привычка

struct NewHabitView: View {
    @ObservedObject var store: HabitStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = "#3478F6"
    @State private var links: [ReminderLink] = []
    @State private var choosingReminder = false

    var body: some View {
        NavigationStack {
            // Те же карточки, что на странице привычки.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Card(title: "Reminders", footer: "Without a reminder the habit is marked only in this app and its widgets.") {
                        ReminderLinksList(links: links, remove: { id in links.removeAll { $0.reminderID == id } },
                                          add: { choosingReminder = true })
                    }
                    Card(footer: "Leave the name empty to use the reminder's title — it follows renames in Reminders.") {
                        InputRow(title: "Name", placeholder: links.last?.titles.last ?? "optional", text: $name)
                        Divider()
                        HexField(title: "Color", hex: $colorHex, alpha: false)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var habit = Habit(name: name.trimmingCharacters(in: .whitespaces), colorHex: Color(hex: colorHex) != nil ? colorHex : "#3478F6")
                        habit.links = links
                        store.add(habit)
                        Task { await store.refresh() }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && links.isEmpty)
                }
            }
            .sheet(isPresented: $choosingReminder) {
                ReminderPickerView(linked: Set(links.map(\.reminderID)), usedBy: store.reminderUsers(except: nil)) { picked in
                    if !links.contains(where: { $0.reminderID == picked.reminderID }) { links.append(picked) }
                }
            }
        }
    }
}

// MARK: - Карточки страницы привычки

/// Карточка как в сгруппированном списке: подзаголовок и белая подложка со скруглением.
/// Добавка к обычному промежутку 24 перед карточкой с подзаголовком — как в списках.
let cardHeaderGap: CGFloat = 5

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
        // Одна строка: название, hex и кружок системной палитры (со слайдерами).
        HStack {
            InputRow(title: title, placeholder: alpha ? "#RRGGBBAA" : "#RRGGBB", text: $hex, monospaced: true, capitalized: true)
            ColorPicker(title, selection: Binding(get: { Color(hex: hex) ?? .white },
                                                  set: { hex = alpha ? $0.hexString : String($0.hexString.prefix(7)) }),
                        supportsOpacity: alpha)
                .labelsHidden()
        }
    }
}

/// Свой цвет: переключатель, палитра и hex с прозрачностью.
/// Свой цвет: переключатель; включён — строка цвета (hex и палитра).
struct OwnColorField: View {
    let title: String
    let hex: String?
    var fallback = "#FFFFFFFF"
    /// С прозрачностью (#RRGGBBAA) или без.
    var alpha = true
    /// Строка неактивна целиком (например, своя отметка «дважды» у обычной привычки).
    var enabled = true
    let set: (String?) -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { hex != nil }, set: { set($0 ? fallback : nil) }))
            .disabled(!enabled)
        if let hex, enabled {
            HexField(title: "Color", hex: Binding(get: { hex }, set: { set($0) }), alpha: alpha)
                .padding(.leading, 20)
        }
    }
}

/// Выбор иконки приложения: четыре варианта в ряд, стрелка — под текущей.
/// iOS меняет иконку сразу (и сама показывает об этом сообщение); перезапуск не нужен.
struct AppIconPicker: View {
    /// nil — основная иконка, иначе имя альтернативной из каталога ресурсов.
    private static let icons: [(name: String?, preview: String)] = [
        (nil, "IconPreview-1"), ("AppIcon-2", "IconPreview-2"), ("AppIcon-3", "IconPreview-3"), ("AppIcon-4", "IconPreview-4"),
    ]
    @State private var current = UIApplication.shared.alternateIconName

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Icon")
            HStack(spacing: 10) {
                ForEach(Self.icons, id: \.preview) { icon in
                    VStack(spacing: 8) {
                        Image(icon.preview).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .frame(width: 60, height: 60)
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold)).foregroundStyle(.secondary)
                            .opacity(icon.name == current ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { select(icon.name) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ name: String?) {
        guard name != current else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            Task { @MainActor in
                if let error {
                    Toast.show("Couldn't change the icon: \(error.localizedDescription)", error: true)
                } else {
                    current = name
                    Toast.show("App icon changed")
                }
            }
        }
    }
}

/// Кнопка ⓘ с пояснением во всплывающем окне.
struct InfoButton: View {
    let text: String
    var tint: Color = Color(.tertiaryLabel)
    /// Окно примерно квадратное (высота ≈ ширине), а не по высоте текста.
    var tall = false
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: { Image(systemName: "info.circle").font(.body) }
            .buttonStyle(.borderless)
            .foregroundStyle(tint)
            .popover(isPresented: $shown) {
                // Цвет кнопки на текст не переходит: текст — обычный.
                ScrollView { Text(text).font(.callout).foregroundStyle(.primary).padding(20).frame(maxWidth: 360, alignment: .leading) }
                    .frame(minHeight: tall ? 213 : nil)
                    .presentationCompactAdaptation(.popover)
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
    @State private var choosingMerge = false
    @State private var mergeWith: Habit?
    @State private var editingTitle = false
    @FocusState private var titleFocused: Bool
    @State private var noteDay: Date?
    @State private var noteText = ""
    @State private var reasonFor: (UUID, Date)?
    @State private var reasonText = ""
    /// Закрыли плашку долгого пропуска — перерисовать страницу.
    @State private var longGapDismissals = 0
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

                    // Долгий пропуск по одной причине — плашка с советом над сеткой.
                    let _ = longGapDismissals
                    if let gap = habit.longGap(reasons: store.reasons) {
                        LongGapBanner(habitTitle: habit.title, gap: gap) {
                            AppGroup.defaults.set(gap.start, forKey: LongGap.dismissedKey(habitID))
                            withAnimation { longGapDismissals += 1 }
                        }
                    }

                    GrowingHistoryGrid(habit: habit, pageBottom: pageBottom, scrolls: scrolls,
                                       setState: { day, state in store.set(habitID, day: day, state: state) },
                                       editNote: { day in noteText = habit.note(day) ?? ""; noteDay = day },
                                       reasons: store.reasons,
                                       setReason: { day, reason in store.setReason(habitID, day: day, reason: reason) },
                                       newReason: { day in reasonText = ""; reasonFor = (habitID, day) })

                    // Заметка к привычке: поле во всю ширину, растёт по тексту.
                    if habit.showsNote {
                        TextField("Description", text: Binding(get: { habit.habitNote }, set: { var h = habit; h.habitNote = $0; store.update(h) }),
                                  axis: .vertical)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }

                    StatsCard(habit: habit)
                    // Подзаголовки карточек — на том же расстоянии от того, что выше, что и в списках
                    // (на главной от плашки до «Calendar» 34 pt до верха букв): 24 + 5.
                    settingsCard(habit).padding(.top, cardHeaderGap)
                    remindersCard(habit).padding(.top, cardHeaderGap)

                    Card {
                        HStack {
                            ShareLink(items: HabitCSV.files([habit], reasons: store.reasons, prefix: "\(habit.title) ")) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                            Spacer()
                            InfoButton(text: HabitCSV.formatInfo, tint: .accentColor)
                        }
                        if habit.isTrashed {
                            Divider()
                            Button {
                                store.restoreFromTrash(habitID)
                                Toast.show("Restored “\(habit.title)” from Trash")
                            } label: { Label("Restore from Trash", systemImage: "arrow.uturn.backward") }
                            Divider()
                            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                                // Диалог у самой кнопки (iOS 26 показывает его от того вида, к которому он привязан).
                                .confirmationDialog("Delete \(habit.title) permanently?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                                    Button("Delete Permanently", role: .destructive) {
                                        let title = habit.title
                                        dismiss(); store.delete(habitID)
                                        Toast.show("Deleted “\(title)”.\nA backup was saved.")
                                    }
                                } message: {
                                    Text("The habit and its history are deleted from this app (a backup is saved first). Reminders are not touched.")
                                }
                        } else {
                            Divider()
                            Button {
                                var h = habit; h.archived.toggle(); store.update(h)
                                Toast.show(h.archived ? "Archived “\(h.title)”" : "Unarchived “\(h.title)”")
                                if h.archived { dismiss() }
                            } label: {
                                Label(habit.archived ? "Unarchive Habit" : "Archive Habit", systemImage: "archivebox")
                            }
                            Divider()
                            HStack {
                                Button { choosingMerge = true } label: { Label("Merge This Habit With…", systemImage: "square.split.2x1") }
                                    .confirmationDialog("Merge “\(mergeWith?.title ?? "")” into “\(habit.title)”?",
                                                        isPresented: Binding(get: { mergeWith != nil }, set: { if !$0 { mergeWith = nil } }), titleVisibility: .visible) {
                                        Button("Merge") {
                                            if let other = mergeWith {
                                                store.merge(habitID, with: other.id)
                                                Toast.show("Merged “\(other.title)” into “\(habit.title)”")
                                                // Итоговая привычка — эта же страница: показываем её сначала.
                                                scrolls.scrollPageToTop()
                                            }
                                            mergeWith = nil
                                        }
                                    } message: {
                                        Text("“\(mergeWith?.title ?? "")” is deleted after its days, notes and reminders move here. A backup is saved first.")
                                    }
                                Spacer()
                                InfoButton(text: "Merging moves everything from the chosen habit into this one and deletes the chosen habit. A backup is saved first (habits-before-merge-….json in the backup folders).\n\n• Name: this habit's name.\n• Days: all marked days of both. If a day is marked in both, the stronger mark wins: Twice > Overdone > Done > Partially (not done means no mark).\n• Notes: kept from both; if a day has notes in both, they are joined.\n• Settings: a setting changed from its default wins; if both habits changed it, this habit's value wins.\n• Linked reminders: all of both.", tint: .accentColor)
                            }
                            Divider()
                            // Удаление — в корзину (вернуть или удалить насовсем можно оттуда).
                            Button(role: .destructive) {
                                store.trash(habitID)
                                Toast.show("Moved “\(habit.title)” to Trash")
                                dismiss()
                            } label: { Label("Move to Trash", systemImage: "trash") }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await store.forceRefresh() }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { pageBottom = $0 }
            .navigationBarTitleDisplayMode(.inline)
            .collapsingTitle(habit.title)
            .alert(noteDay.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Note",
                   isPresented: Binding(get: { noteDay != nil }, set: { if !$0 { noteDay = nil } })) {
                TextField("Note", text: $noteText)
                Button("Save") {
                    if let day = noteDay { var h = habit; h.setNote(noteText, day: day); store.update(h) }
                    noteDay = nil
                }
                Button("Cancel", role: .cancel) { noteDay = nil }
            }
            .newReasonAlert(store: store, target: $reasonFor, text: $reasonText)
            .sheet(isPresented: $choosingMerge) {
                HabitPickerView(habits: store.habits.filter { $0.id != habitID && !$0.isTrashed }) { mergeWith = $0 }
            }
            .sheet(isPresented: $choosingReminder) {
                ReminderPickerView(linked: Set(habit.links.map(\.reminderID)), usedBy: store.reminderUsers(except: habitID)) { picked in
                    var h = habit
                    if !h.links.contains(where: { $0.reminderID == picked.reminderID }) { h.links.append(picked) }
                    store.update(h)
                    Task { await store.refresh() }
                }
            }
        }
    }

    /// Настройки привычки — три плашки: о привычке, правила, свои цвета.
    private func settingsCard(_ habit: Habit) -> some View {
        VStack(spacing: 18) {
            Card(title: "Habit Settings") { aboutGroup(habit) }
            Card { rulesGroup(habit) }
            Card { colorsGroup(habit) }
        }
    }

    @ViewBuilder private func aboutGroup(_ habit: Habit) -> some View {
            InputRow(title: "Name", placeholder: habit.links.last?.titles.last ?? "Habit",
                     text: Binding(get: { habit.name }, set: { var h = habit; h.name = $0; store.update(h) }))
            Divider()
            HexField(title: "Color", hex: Binding(get: { String(habit.colorHex.prefix(7)) }, set: { var h = habit; h.colorHex = $0; store.update(h) }),
                     alpha: false)
            Divider()
            SelectRow(title: "Habit Type", options: [(false, "Good"), (true, "Bad")],
                      selection: Binding(get: { habit.harmful }, set: { var h = habit; h.harmful = $0; store.update(h) }))
            Divider()
            Toggle("Show Description", isOn: Binding(get: { habit.showsNote }, set: { var h = habit; h.showsNote = $0; store.update(h) }))
    }

    @ViewBuilder private func rulesGroup(_ habit: Habit) -> some View {
            // Выключили — дни «дважды» остаются в истории, но считаются и рисуются как сделанные.
            Toggle("Twice a day", isOn: Binding(get: { habit.twiceADay }, set: {
                var h = habit; h.twiceADay = $0
                if !$0 { h.weeklyGoal = min(h.weeklyGoal, 7) }
                store.update(h)
            }))
            Divider()
            // Правило для пропусков — одно из: подсветка пропусков сверх допуска или цель на неделю.
            SelectRow(title: "Skip rule:", options: Habit.Rule.allCases.map { ($0, $0.title) },
                      selection: Binding(get: { habit.rule }, set: { var h = habit; h.setRule($0); store.update(h) }))
            switch habit.rule {
            case .none:
                EmptyView()
            case .missed:
                // Пропуски сверх допустимого подсвечиваются (цвет — настройки привычек → Grid).
                // У вредной привычки пропуск — это хорошо: строка неактивна.
                ValueStepper("Allowed skips in a row:", shown: "\(habit.allowedSkips)", after: habit.allowedSkips == 1 ? "day" : "days",
                             value: Binding(get: { habit.allowedSkips }, set: { var h = habit; h.allowedSkips = $0; store.update(h) }), in: 0...14, step: 1)
                    .disabled(habit.harmful)
                    .padding(.leading, 20)
            case .goal:
                let countsTwice = habit.twiceADay && habit.goalCountsTwice
                ValueStepper("Times a week:", shown: "\(habit.weeklyGoal)",
                             value: Binding(get: { habit.weeklyGoal }, set: { var h = habit; h.weeklyGoal = $0; store.update(h) }),
                             in: 1...(countsTwice ? 14 : 7), step: 1)
                    .padding(.leading, 20)
                // Виден всегда; без «Twice a day» неактивен.
                Toggle("Count twice days as 2", isOn: Binding(get: { habit.goalCountsTwice }, set: {
                    var h = habit; h.goalCountsTwice = $0
                    if !$0 { h.weeklyGoal = min(h.weeklyGoal, 7) }
                    store.update(h)
                }))
                .disabled(!habit.twiceADay)
                .padding(.leading, 20)
            }
            Divider()
            // Причины несделанных дней: пункт меню дня, знаки вопроса и долгие пропуски.
            Toggle(isOn: Binding(get: { habit.asksWhyNotDone }, set: { var h = habit; h.asksWhyNotDone = $0; store.update(h) })) {
                HStack(spacing: 6) {
                    Text("Why Not Done")
                    InfoButton(text: habit.questionRuleInfo, tint: .primary, tall: true)
                }
            }
    }

    @ViewBuilder private func colorsGroup(_ habit: Habit) -> some View {
            // Подгруппа: заголовок — как обычная строка, переключатели под ним — с отступом.
            Text("Own color for")
            Group {
                OwnColorField(title: "Partially Done Icon", hex: habit.partialIconHex) { var h = habit; h.partialIconHex = $0; store.update(h) }
                OwnColorField(title: "Overdone Icon", hex: habit.overIconHex) { var h = habit; h.overIconHex = $0; store.update(h) }
                OwnColorField(title: "Twice Mark", hex: habit.twiceIconHex, enabled: habit.twiceADay) { var h = habit; h.twiceIconHex = $0; store.update(h) }
                OwnColorField(title: "Missed Days", hex: habit.missedHex, fallback: "#FF0000", alpha: false,
                              enabled: habit.rule == .missed && !habit.harmful) { var h = habit; h.missedHex = $0; store.update(h) }
                OwnColorField(title: "Note Icon", hex: habit.noteIconHex, fallback: "#8E8E93FF") { var h = habit; h.noteIconHex = $0; store.update(h) }
            }
            .padding(.leading, 20)
    }

    private func remindersCard(_ habit: Habit) -> some View {
        Card(title: "Reminders",
             footer: "Linking a new reminder keeps the whole history under this habit. Unlinking or deleting never changes Reminders.") {
            ReminderLinksList(links: habit.links, remove: { id in var h = habit; h.links.removeAll { $0.reminderID == id }; store.update(h) },
                              add: { choosingReminder = true })
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
    let reasons: [SkipReason]
    let setReason: (Date, UUID?) -> Void
    let newReason: (Date) -> Void

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
    /// Сколько недель в ленте сейчас: растёт вместе с `weekCount`, но не уменьшается, пока
    /// страница открыта.
    @State private var shownWeeks: Int?

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
        let missed = habit.missedDays(today: today)
        let questions = habit.questionDays(today: today)

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
                        ForEach(HabitGrid.weeks(count: shownWeeks ?? weekCount, endingAt: today), id: \.first) { week in
                            HStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { i in
                                    if let day = week[i] {
                                        dayCell(day, today: today, style: style, missed: missed.contains(HabitDay.key(day)), questions: questions).id(HabitDay.key(day))
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                            .background(alignment: .topLeading) {
                                MissedLinks(flags: week.map { $0.map { missed.contains(HabitDay.key($0)) } ?? false }, cell: cell, gap: gap,
                                            color: style.missedColor(habit.missedHex).opacity(style.missedLinkOpacity),
                                            cutDays: false)
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
            .onAppear { if shownWeeks == nil { shownWeeks = weekCount } }
            // Отметили день раньше самого раннего — сверху добавляются недели (лента всегда на
            // полгода раньше первой отметки), а прокрутка сдвигается ровно на их высоту: отмеченный
            // день остаётся на месте. Убрали раннюю отметку — лента, пока страница открыта, не
            // укорачивается (иначе всё под пальцем прыгнуло бы).
            .onChange(of: weekCount) { _, new in
                guard let shown = shownWeeks, new > shown else { return }
                let target = offset + CGFloat(new - shown) * (cell + gap)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    shownWeeks = new
                    position.scrollTo(y: target)
                }
            }
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

    private func cellView(_ day: Date, today: Date, style: HabitStyle, size: CGFloat, missed: Bool = false, questions: Set<String>) -> HabitCell {
        HabitCell(state: habit.state(day), isToday: day == today, color: habit.color, size: size, style: style,
                  partialIconHex: habit.partialIconHex, overIconHex: habit.overIconHex, twiceIconHex: habit.twiceIconHex,
                  missed: missed, missedHex: habit.missedHex, hasNote: habit.note(day) != nil,
                  needsReason: questions.contains(HabitDay.key(day)),
                  noteIconHex: habit.noteIconHex,
                  opaqueBackground: Color(.secondarySystemGroupedBackground))
    }

    private func dayCell(_ day: Date, today: Date, style: HabitStyle, missed: Bool, questions: Set<String>) -> some View {
        let state = habit.state(day)
        let note = habit.note(day)
        // Обычное меню кнопки, а не контекстное: день не поднимается и не прыгает при закрытии,
        // меню просто открывается рядом. Нажатие — отметка, долгое нажатие — меню.
        // Содержимое меню строится при каждом открытии — дата в шапке всегда этого дня.
        // Рамка кнопки — габариты дня со значком заметки (он выступает за клетку), а форма —
        // ровно контур: иначе при закрытии меню значок обрезался по скруглённому квадрату.
        let shape = DayShape(cell: cell, hasNote: note != nil, hasQuestion: questions.contains(HabitDay.key(day)))
        let extra = shape.overhang
        return Menu {
            DayMenuItems(habit: habit, day: day, style: style, setState: { setState(day, $0) }, editNote: { editNote(day) },
                         reasons: reasons, setReason: { setReason(day, $0) }, newReason: { newReason(day) })
        } label: {
            cellView(day, today: today, style: style, size: cell, missed: missed, questions: questions)
                .padding(.top, extra.top)
                .frame(width: cell + extra.width, height: extra.top + cell + extra.height, alignment: .topLeading)
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
        .padding(.top, -extra.top)
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
}

/// Меню дня — в сетке и у чекбокса на главной (для сегодняшнего дня): дата, «недоделано»
/// и «перевыполнено» (текущее — бледное и неактивно) и заметка.
struct DayMenuItems: View {
    let habit: Habit
    let day: Date
    let style: HabitStyle
    let setState: (HabitDayState) -> Void
    let editNote: () -> Void
    /// Общий список причин несделанного дня; выбрать (nil — снять) или создать новую.
    let reasons: [SkipReason]
    let setReason: (UUID?) -> Void
    let newReason: () -> Void

    var body: some View {
        let state = habit.state(day)
        let note = habit.note(day)
        Section(day.formatted(date: .complete, time: .omitted)) {
            if habit.asksWhyNotDone && state == .none && day <= HabitDay.today() { reasonMenu }
            // Сделано / не сделано — нажатием по дню; в меню — только недоделано и перевыполнено.
            ForEach([HabitDayState.partial, .over]) { option in
                Button { setState(option) } label: {
                    Label { Text(option.title) } icon: { menuIcon(option, style, dim: option == state) }
                }
                .disabled(option == state)
            }
        }
        Section {
            Button(action: editNote) { Label(note == nil ? "Add Note…" : "Edit Note…", systemImage: "doc") }
            if let note { Text(note) }
        }
    }

    /// «Why Not Done?» — вложенное меню причин (выбранная — с галочкой и подписью под пунктом).
    private var reasonMenu: some View {
        let current = habit.reason(day)
        return Menu {
            ForEach(reasons) { reason in
                Button { setReason(reason.id == current ? nil : reason.id) } label: {
                    if reason.id == current { Label(reason.title, systemImage: "checkmark") } else { Text(reason.title) }
                }
            }
            Divider()
            Button(action: newReason) { Label("New Reason…", systemImage: "plus") }
        } label: {
            Label {
                Text("Why Not Done?")
                if let title = reasons.first(where: { $0.id == current })?.title { Text(title) }
            } icon: { Image(systemName: "questionmark") }
        }
    }

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
    /// Значок заметки — у правого нижнего угла, знак вопроса — у правого верхнего.
    let hasNote: Bool
    let hasQuestion: Bool

    private var badge: CGFloat { max(8, cell * 0.3) }

    /// Насколько значки выступают за клетку: вправо, вниз (заметка) и вверх (вопрос).
    var overhang: (width: CGFloat, height: CGFloat, top: CGFloat) {
        (hasNote || hasQuestion ? badge * 0.46 : 0, hasNote ? badge * 0.36 : 0, hasQuestion ? badge * 0.36 : 0)
    }

    /// Клетка начинается на `overhang.top` ниже верха рамки.
    func path(in rect: CGRect) -> Path {
        let top = overhang.top
        var p = Path(roundedRect: CGRect(x: 0, y: top, width: cell, height: cell), cornerRadius: cell * 0.3, style: .continuous)
        let corner = CGSize(width: badge * 0.25, height: badge * 0.25)
        if hasNote {
            p.addRoundedRect(in: CGRect(x: cell - badge * 0.64, y: top + cell - badge * 0.96, width: badge * 1.1, height: badge * 1.32), cornerSize: corner)
        }
        if hasQuestion {
            p.addRoundedRect(in: CGRect(x: cell - badge * 0.64, y: top - badge * 0.36, width: badge * 1.1, height: badge * 1.32), cornerSize: corner)
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
                if habit.twiceADay { stat("Current twice streak", "\(s.twiceStreak) d") }
                stat("Longest streak", "\(s.longestStreak) d", detail: s.longestPeriod)
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

    private func stat(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }
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
    /// Период самой длинной серии: «(29.11–27.12)», с годом, если он не текущий.
    var longestPeriod: String?
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
        var run = 0, longestEnd = 0
        for back in stride(from: total - 1, through: 0, by: -1) {
            run = good(day(back)) ? run + 1 : 0
            if run > longestStreak { longestStreak = run; longestEnd = back }
        }
        if longestStreak > 0 {
            let start = day(longestEnd + longestStreak - 1), end = day(longestEnd)
            let year = cal.component(.year, from: today)
            let withYear = cal.component(.year, from: start) != year || cal.component(.year, from: end) != year
            let f = DateFormatter()
            f.dateFormat = withYear ? "dd.MM.yy" : "dd.MM"
            longestPeriod = longestStreak == 1 ? "(\(f.string(from: end)))" : "(\(f.string(from: start))–\(f.string(from: end)))"
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
    @State private var titleY: CGFloat?
    @AppStorage(HabitSettings.Key.dayCutoffHour, store: AppGroup.defaults) private var cutoff = 3
    @AppStorage(HabitSettings.Key.titleSize, store: AppGroup.defaults) private var titleSize = 24.0
    @AppStorage(HabitSettings.Key.widgetWeeks, store: AppGroup.defaults) private var weeks = 4.0
    @AppStorage(HabitSettings.Key.buttonSize, store: AppGroup.defaults) private var buttonSize = 40.0
    @AppStorage(HabitSettings.Key.squircleButton, store: AppGroup.defaults) private var squircleButton = true
    @AppStorage(HabitSettings.Key.mainSquircle, store: AppGroup.defaults) private var mainSquircle = true
    @AppStorage(HabitSettings.Key.mainSquircleSize, store: AppGroup.defaults) private var mainSquircleSize = 32.0
    @AppStorage(HabitSettings.Key.mainCheckboxSize, store: AppGroup.defaults) private var mainCheckboxSize = 30.0
    @AppStorage(HabitSettings.Key.buttonInset, store: AppGroup.defaults) private var buttonInset = HabitSettings.buttonInset
    @AppStorage(HabitSettings.Key.gridInset, store: AppGroup.defaults) private var gridInset = 18.0
    @AppStorage(HabitSettings.Key.undoneOpacity, store: AppGroup.defaults) private var undoneOpacity = 0.15
    @AppStorage(HabitSettings.Key.partialPattern, store: AppGroup.defaults) private var pattern = PartialPattern.icon.rawValue
    @AppStorage(HabitSettings.Key.undonePattern, store: AppGroup.defaults) private var undonePattern = UndonePattern.plain.rawValue
    @AppStorage(HabitSettings.Key.undoneSymbol, store: AppGroup.defaults) private var undoneSymbol = "xmark"
    @AppStorage(HabitSettings.Key.undoneIconScale, store: AppGroup.defaults) private var undoneIconScale = 0.4
    @AppStorage(HabitSettings.Key.undoneIconOpacity, store: AppGroup.defaults) private var undoneIconOpacity = 0.5
    @AppStorage(HabitSettings.Key.undoneOutlineWidth, store: AppGroup.defaults) private var undoneOutlineWidth = 0.08
    @AppStorage(HabitSettings.Key.stripeWidth, store: AppGroup.defaults) private var stripeWidth = 6.0
    @AppStorage(HabitSettings.Key.doneStripeOpacity, store: AppGroup.defaults) private var doneStripeOpacity = 1.0
    @AppStorage(HabitSettings.Key.undoneStripeOpacity, store: AppGroup.defaults) private var undoneStripeOpacity = 0.13
    @AppStorage(HabitSettings.Key.partialSymbol, store: AppGroup.defaults) private var partialSymbol = "tortoise.fill"
    @AppStorage(HabitSettings.Key.overSymbol, store: AppGroup.defaults) private var overSymbol = "bolt.fill"
    @AppStorage(HabitSettings.Key.partialIconScale, store: AppGroup.defaults) private var partialIconScale = 0.65
    @AppStorage(HabitSettings.Key.overIconScale, store: AppGroup.defaults) private var overIconScale = 0.65
    @AppStorage(HabitSettings.Key.overIconDarker, store: AppGroup.defaults) private var overDarker = true
    @AppStorage(HabitSettings.Key.overIconDarkness, store: AppGroup.defaults) private var overDarkness = 0.6
    @AppStorage(HabitSettings.Key.gridBottomMargin, store: AppGroup.defaults) private var gridBottomMargin = 1.0
    @AppStorage(HabitSettings.Key.missedHex, store: AppGroup.defaults) private var missedHex = HabitStyle.defaultMissedHex
    @AppStorage(HabitSettings.Key.missedOpacity, store: AppGroup.defaults) private var missedOpacity = 0.25
    @AppStorage(HabitSettings.Key.missedLinkOpacity, store: AppGroup.defaults) private var missedLinkOpacity = 0.1
    /// Что выбирают — отдельно от показа окна: закрываясь, окно сбрасывает показ раньше,
    /// чем приходит результат, и выбор терялся (ничего не происходило).
    @State private var picking = Picking.csv
    @State private var pickerShown = false
    @State private var backupFolder = FilesBackup.chosenFolder?.lastPathComponent
    @State private var pendingRestore: HabitDB?
    @AppStorage(HabitSettings.Key.twicePattern, store: AppGroup.defaults) private var twicePattern = TwicePattern.innerSquare.rawValue
    @AppStorage(HabitSettings.Key.twiceSymbol, store: AppGroup.defaults) private var twiceSymbol = "2.circle.fill"
    @AppStorage(HabitSettings.Key.twiceIconScale, store: AppGroup.defaults) private var twiceIconScale = 0.65
    @AppStorage(HabitSettings.Key.twiceInnerSize, store: AppGroup.defaults) private var twiceInnerSize = 0.55
    @AppStorage(HabitSettings.Key.twiceDarker, store: AppGroup.defaults) private var twiceDarker = true
    @AppStorage(HabitSettings.Key.twiceDarkness, store: AppGroup.defaults) private var twiceDarkness = 0.55
    @State private var hasAccess = ReminderSync.hasAccess

    private var previewStyle: HabitStyle {
        HabitStyle(undoneOpacity: undoneOpacity,
                   undonePattern: UndonePattern(rawValue: undonePattern) ?? .plain,
                   undoneSymbol: undoneSymbol.isEmpty ? "xmark" : undoneSymbol,
                   undoneIconScale: undoneIconScale, undoneIconOpacity: undoneIconOpacity,
                   undoneOutlineWidth: undoneOutlineWidth,
                   partialPattern: PartialPattern(rawValue: pattern) ?? .icon,
                   stripeWidth: stripeWidth, doneStripeOpacity: doneStripeOpacity, undoneStripeOpacity: undoneStripeOpacity,
                   partialSymbol: partialSymbol.isEmpty ? "tortoise.fill" : partialSymbol,
                   overSymbol: overSymbol.isEmpty ? "bolt.fill" : overSymbol,
                   partialIconScale: partialIconScale, overIconScale: overIconScale,
                   overIconDarker: overDarker, overIconDarkness: overDarkness,
                   twicePattern: TwicePattern(rawValue: twicePattern) ?? .innerSquare,
                   twiceSymbol: twiceSymbol.isEmpty ? "2.circle.fill" : twiceSymbol,
                   twiceIconScale: twiceIconScale, twiceInnerSize: twiceInnerSize,
                   twiceDarker: twiceDarker, twiceDarkness: twiceDarkness, missedHex: missedHex,
                   missedOpacity: missedOpacity, missedLinkOpacity: missedLinkOpacity)
    }

    /// Все состояния дня с текущими настройками; стрелки — под теми, к которым относится группа.
    private func preview(_ arrows: Set<HabitDayState>) -> some View {
        HStack(spacing: 10) {
            ForEach(HabitDayState.allCases) { state in
                VStack(spacing: 8) {
                    HabitCell(state: state, isToday: false, color: .blue, size: 40, style: previewStyle)
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold)).foregroundStyle(.secondary)
                        .opacity(arrows.contains(state) ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    /// Что выбирают в окне файлов: CSV для импорта, бэкап для восстановления или папку бэкапов.
    private enum Picking { case csv, backup, folder }

    var body: some View {
        Form {
            PageTitleRow("Habits on Reminders Settings", y: $titleY)

            // Синхронизация — потянуть вниз; здесь только запрос доступа, если его нет.
            if !hasAccess {
                Section {
                    Button { Task { hasAccess = await ReminderSync.requestAccess() } } label: {
                        Label("Allow Access to Reminders", systemImage: "lock.open")
                    }
                }
            }

            Section {
                Picker("Today", selection: $mainSquircle) {
                    Text("Today's Day").tag(true)
                    Text("Round Checkbox").tag(false)
                }
                // У каждого вида — свой размер.
                let size = mainSquircle ? $mainSquircleSize : $mainCheckboxSize
                VStack(alignment: .leading) {
                    ValueStepper("Size:", shown: "\(Int(size.wrappedValue))", after: "pt", value: size, in: 20...48, step: 1)
                    Slider(value: size, in: 20...48, step: 1)
                }
            } header: {
                RoundedHeader("Main Screen")
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
                Picker("Button", selection: $squircleButton) {
                    Text("Today's Day").tag(true)
                    Text("Round Checkbox").tag(false)
                }
                // У квадрата дня свой отступ от края по умолчанию: 14, у круглого чекбокса — 9.
                .onChange(of: squircleButton) { _, squircle in buttonInset = squircle ? 14 : 9 }
                ValueStepper("Button diameter:", shown: "\(Int(buttonSize))", after: "pt", value: $buttonSize, in: 24...60, step: 1)
                ValueStepper("Button inset:", shown: "\(Int(buttonInset))", after: "pt", value: $buttonInset, in: 0...24, step: 1)
                ValueStepper("Grid inset:", shown: "\(Int(gridInset))", after: "pt", value: $gridInset, in: 0...24, step: 1)
            } header: {
                RoundedHeader("Widgets")
            } footer: {
                Text("Title size is the default for all habit widgets (one line; two lines are a third smaller) — each widget can override it. Button inset is from the top and right edges; grid inset is from the bottom, left and right edges.")
            }

            Section {
                preview([.none, .partial])
                VStack(alignment: .leading) {
                    Text("Not done opacity: \(Int(undoneOpacity * 100))%")
                    Slider(value: $undoneOpacity, in: 0...1)
                }
            } header: {
                RoundedHeader("Grid")
            }
            // Три плашки группы Grid — ближе друг к другу, как список привычек и настройки на главной.
            .listSectionSpacing(18)

            Section {
                // Превью: два пропуска подряд с перемычкой, по левому краю.
                HStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { _ in HabitCell(state: .none, isToday: false, color: .blue, size: 40, style: previewStyle, missed: true) }
                }
                .background(alignment: .topLeading) {
                    MissedLinks(flags: [true, true], cell: 40, gap: 10, color: previewStyle.missedColor(nil).opacity(missedLinkOpacity))
                }
                .padding(.vertical, 4)
                HexField(title: "Missed days color", hex: Binding(get: { String(missedHex.prefix(7)) }, set: { missedHex = String($0.prefix(7)) }), alpha: false)
                VStack(alignment: .leading) {
                    Text("Missed days opacity: \(Int((missedOpacity * 100).rounded()))%")
                    Slider(value: $missedOpacity, in: 0...1)
                }
                VStack(alignment: .leading) {
                    Text("Between missed days opacity: \(Int((missedLinkOpacity * 100).rounded()))%")
                    Slider(value: $missedLinkOpacity, in: 0...1)
                }
            } footer: {
                Text("Not-done days in a row beyond what a habit allows (turned on in each habit's settings); neighbours in a week are joined.")
            }
            .listSectionSpacing(18)

            Section {
                VStack(alignment: .leading) {
                    Text("Bottom margin for Grid Feed: \(Int(gridBottomMargin)) pt")
                    Slider(value: $gridBottomMargin, in: -15...200, step: 1)
                }
            } footer: {
                Text("How close to the bottom of the screen the grid card on a habit page may grow.")
            }
            .listSectionSpacing(18)

            BannerSection()

            SkipReasonsSection(store: store)

            Section {
                preview([.none])
                Picker("Style", selection: $undonePattern) {
                    ForEach(UndonePattern.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if undonePattern == UndonePattern.icon.rawValue {
                    SymbolField(title: "Icon", symbol: $undoneSymbol)
                    VStack(alignment: .leading) {
                        Text("Icon size: \(Int(undoneIconScale * 100))% of the day")
                        Slider(value: $undoneIconScale, in: 0...1)
                    }
                }
                if undonePattern == UndonePattern.outline.rawValue {
                    VStack(alignment: .leading) {
                        Text("Outline width: \(Int((undoneOutlineWidth * 100).rounded()))% of the day")
                        Slider(value: $undoneOutlineWidth, in: 0.01...0.3)
                    }
                }
                if undonePattern != UndonePattern.plain.rawValue {
                    VStack(alignment: .leading) {
                        Text("\(undonePattern == UndonePattern.icon.rawValue ? "Icon" : "Outline") opacity: \(Int(undoneIconOpacity * 100))%")
                        Slider(value: $undoneIconOpacity, in: 0...1)
                    }
                }
            } header: {
                RoundedHeader("Not Done")
            } footer: {
                Text("Icon: any SF Symbol — xmark for a cross, circle.fill for a dot. Drawn in the habit color (the missed color on missed days).")
            }

            Section {
                preview([.partial])
                Picker("Style", selection: $pattern) {
                    ForEach(PartialPattern.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if pattern == PartialPattern.diagonal.rawValue {
                    ValueStepper("Stripe width:", shown: "\(Int(stripeWidth))", after: "pt", value: $stripeWidth, in: 4...16, step: 1)
                    VStack(alignment: .leading) {
                        Text("Done stripes opacity: \(Int(doneStripeOpacity * 100))%")
                        Slider(value: $doneStripeOpacity, in: 0...1)
                    }
                    VStack(alignment: .leading) {
                        Text("Not done stripes opacity: \(Int(undoneStripeOpacity * 100))%")
                        Slider(value: $undoneStripeOpacity, in: 0...1)
                    }
                }
                if pattern == PartialPattern.icon.rawValue {
                    SymbolField(title: "Icon", symbol: $partialSymbol)
                    VStack(alignment: .leading) {
                        Text("Icon size: \(Int(partialIconScale * 100))% of the day")
                        Slider(value: $partialIconScale, in: 0...1)
                    }
                }
            } header: {
                RoundedHeader("Partially Done")
            } footer: {
                Text("Icon style: the day has the not-done color and the icon the done color. Each habit can set its own icon color.")
            }

            Section {
                preview([.over])
                SymbolField(title: "Icon", symbol: $overSymbol)
                VStack(alignment: .leading) {
                    Text("Icon size: \(Int(overIconScale * 100))% of the day")
                    Slider(value: $overIconScale, in: 0...1)
                }
                Toggle("Icon darker than the day", isOn: $overDarker)
                if overDarker {
                    VStack(alignment: .leading) {
                        Text("Darker by: \(Int(overDarkness * 100))%")
                        Slider(value: $overDarkness, in: 0...1)
                    }
                }
            } header: {
                RoundedHeader("Overdone")
            } footer: {
                Text("Off: the icon has the not-done (lighter) color. On: the habit color mixed with black. Each habit can set its own icon color.")
            }

            Section {
                preview([.twice])
                Picker("Style", selection: $twicePattern) {
                    ForEach(TwicePattern.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if twicePattern == TwicePattern.icon.rawValue {
                    SymbolField(title: "Icon", symbol: $twiceSymbol)
                    VStack(alignment: .leading) {
                        Text("Icon size: \(Int(twiceIconScale * 100))% of the day")
                        Slider(value: $twiceIconScale, in: 0...1)
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("Inner square size: \(Int((twiceInnerSize * 100).rounded()))% of the day")
                        Slider(value: $twiceInnerSize, in: 0...1)
                    }
                }
                Toggle("Darker than the day", isOn: $twiceDarker)
                if twiceDarker {
                    VStack(alignment: .leading) {
                        Text("Darker by: \(Int(twiceDarkness * 100))%")
                        Slider(value: $twiceDarkness, in: 0...1)
                    }
                }
            } header: {
                RoundedHeader("Twice a Day")
            } footer: {
                Text("For habits with “Twice a day” on: tapping a day done once marks it done twice. Off: the mark has the not-done (lighter) color. Each habit can set its own mark color.")
            }

            Section {
                HStack {
                    ShareLink(items: HabitCSV.files(store.habits.filter { !$0.isTrashed }, reasons: store.reasons)) { Label("Export All Habits (CSV)", systemImage: "square.and.arrow.up") }
                    Spacer()
                    InfoButton(text: HabitCSV.formatInfo, tint: .accentColor)
                }
                HStack {
                    Button { picking = .csv; pickerShown = true } label: { Label("Import CSV…", systemImage: "square.and.arrow.down") }
                    Spacer()
                    InfoButton(text: "Reads:\n• this app's CSV: pick both habits.csv and habit_days.csv (or only habit_days.csv for habits you already have); the older single-file CSV (habit_id, habit_name, date, status, note) too;\n• Loop Habit Tracker: Checkmarks.csv (Date, then a column per habit; YES_MANUAL counts as done, YES_AUTO / NO / SKIP / UNKNOWN as not marked) or one habit's Checkmarks.csv (Date, Value, Notes — the habit is named after its folder);\n• any CSV with a date column (date, day…) and a habit name column (habit, name, task…), optionally a status (done / yes / true / 1, partial, over, twice; no / false / 0 = not marked) and a note.\n\nHabits are matched by ID, then by name; others are created. Days already marked and existing notes are kept. Dates: yyyy-MM-dd, dd.MM.yyyy, MM/dd/yyyy and similar.", tint: .accentColor)
                }
            } header: {
                RoundedHeader("Export & Import")
            } footer: {
                Text("Import also reads Loop Habit Tracker and other trackers' CSV.")
            }

            Section {
                Button { picking = .folder; pickerShown = true } label: {
                    HStack {
                        Label("Backup Folder", systemImage: "folder")
                        Spacer()
                        Text(backupFolder ?? "On iPhone only").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if backupFolder != nil {
                    Button(role: .destructive) { FilesBackup.setFolder(nil); backupFolder = nil; Toast.show("Backups stay on iPhone only") } label: {
                        Label("Stop Backing Up to This Folder", systemImage: "folder.badge.minus").foregroundStyle(.red)
                    }
                }
                Button { picking = .backup; pickerShown = true } label: { Label("Restore from Backup…", systemImage: "clock.arrow.circlepath") }
                    .confirmationDialog("Replace all habits with this backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                        titleVisibility: .visible) {
                        Button("Restore \(pendingRestore?.habits.count ?? 0) Habits", role: .destructive) {
                            if let db = pendingRestore { store.restore(db); Toast.show("Restored \(db.habits.count) habits") }
                            pendingRestore = nil
                        }
                    } message: {
                        Text("The current habits are kept in habits-previous.json in the backup folders.")
                    }
            } header: {
                HStack {
                    RoundedHeader("Backup")
                    Spacer()
                    InfoButton(text: "Where: always in Files → On My iPhone → Habits on Reminders, and also in your folder if you choose one (for example a folder in iCloud Drive).\n\nFiles in each folder:\n• habits.json — the current database.\n• habits-previous.json — the database before the last change.\n• habits-daily.json — the database before the first change of the day (an independent copy of the previous day).\n• habits-before-….json — a copy saved before a suspiciously big change (10+ marked days or 2+ habits gone, or 2+ habits lost all linked reminders at once), before a merge and before a restore. Never overwritten. You also get an alert and a notification about a big change.\n• habits.csv and habit_days.csv — all habits as CSV.\n• settings.json — all settings.\n\nDatabase format (JSON): a list of habits, each with its id, name, color, linked reminders and settings, and the marked days as dates “yyyy-MM-dd”: completions (all marked days), partialDays, overDays and twiceDays (which of them are partially done, overdone, twice), removedDays (unmarked by hand), notes (date → text).\n\nCSV format: habits.csv — habit_id, habit_name; habit_days.csv — habit_id, date (yyyy-MM-dd), status (done, partial, over, twice or none), note, skip_reason.\n\nRestore from Backup… replaces all habits with a chosen habits*.json; the current ones go to habits-previous.json first.")
                }
            }
        }
        .fileImporter(isPresented: $pickerShown,
                      allowedContentTypes: picking == .folder ? [.folder] : picking == .backup ? [.json] : [.commaSeparatedText, .plainText, .text],
                      allowsMultipleSelection: picking == .csv) { result in
            let mode = picking
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result { Toast.show("Couldn't open: \(error.localizedDescription)", error: true) }
                return
            }
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
            switch mode {
            case .folder:
                FilesBackup.setFolder(url)
                backupFolder = FilesBackup.chosenFolder?.lastPathComponent
                if let backupFolder { Toast.show("Backing up to “\(backupFolder)”") }
            case .backup:
                if let data = try? Data(contentsOf: url), let db = FilesBackup.decode(data) ?? (try? JSONDecoder().decode(HabitDB.self, from: data)) {
                    pendingRestore = db
                } else {
                    Toast.show("This file isn't a habits backup", error: true)
                }
            case .csv:
                // Можно выбрать сразу обе таблицы (привычки и дни).
                let files = urls.map { url in
                    (text: (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? "",
                     fileName: url.pathComponents.suffix(2).joined(separator: "/"))
                }
                let imported = HabitCSV.parse(files: files)
                if imported.isEmpty {
                    Toast.show("No habits found in this file", error: true)
                } else {
                    let result = store.importCSV(imported)
                    Toast.show("Imported \(result.days) days into \(imported.count) habits (\(result.habits) new)")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .listPageTitle("Habits on Reminders Settings", sideInset: PageTitle.sideInset, rowY: titleY)
        .collapsingTitle("Habits on Reminders Settings")
        .contentMargins(.top, -PageTitle.subpageRaise, for: .scrollContent)
        .refreshable { await store.forceRefresh() }
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// Имя SF Symbol текстом и сам символ.
/// Плашка сверху после действий: ширина и форма углов.
struct BannerSection: View {
    @AppStorage(ToastSettings.Key.width, store: AppGroup.defaults) private var width = ToastSettings.defaultWidth
    @AppStorage(ToastSettings.Key.corners, store: AppGroup.defaults) private var corners = ToastSettings.Corners.round.rawValue

    var body: some View {
        Section {
            // Одно значение — ширина в pt: ползунком или кнопками ±1.
            VStack(alignment: .leading) {
                ValueStepper("Banner width:", shown: "\(Int(width))", after: "pt", value: $width,
                             in: ToastSettings.widthRange, step: 1)
                Slider(value: $width, in: ToastSettings.widthRange, step: 1)
            }
            Picker("Corners", selection: $corners) {
                ForEach(ToastSettings.Corners.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Button("Show Banner") { Toast.show("This is how banners look after an action.\nA long message shows two lines first.\nTap the banner to read all of it, tap again to fold it.\nSwipe it up to close.") }
        } header: {
            RoundedHeader("Banner")
        } footer: {
            Text("The banner at the top after an action: up to two lines — tap it to show the whole text, tap again to fold it. It closes after 10 seconds (unless opened) or when swiped up.")
        }
    }
}

/// Причины несделанных дней: общий список для всех привычек, значок вопроса и уведомление
/// о повторяющейся причине.
struct SkipReasonsSection: View {
    @ObservedObject var store: HabitStore
    @AppStorage(HabitSettings.Key.reasonAlertDays, store: AppGroup.defaults) private var alertDays = 3.0
    @State private var newTitle = ""

    private static let info = """
    Pick a reason from the menu of a not-done day (hold it, or today's checkbox) → Why Not Done?

    Each reason has a kind (after Tiny Habits: a habit happens when prompt, ability and motivation meet):
    • Prompt — nothing reminded you: forgot, no cue.
    • Ability — too hard or no time.
    • Motivation — didn't want to.
    • Excused — sick, travel: not a reason to change anything, never counts as a long gap.
    • Other — anything else.

    When the latest not-done days in a row share one non-excused reason, the habit gets an exclamation mark and its page suggests what to change for that kind.
    """

    var body: some View {
        Section {
            ValueStepper("Long gap after", shown: alertDays == 0 ? "off" : "\(Int(alertDays))",
                         after: alertDays == 0 ? "" : "days", value: $alertDays, in: 0...14, step: 1)
            // Подгруппа, как «Own color for»: заголовок обычной строкой, причины под ним —
            // с отступом и без разделителей.
            HStack {
                Text("Skip Reasons")
                Spacer()
                InfoButton(text: Self.info, tint: .accentColor)
            }
            .listRowSeparator(.hidden, edges: .bottom)
            ForEach(store.reasons) { reason in
                HStack {
                    TextField("Reason", text: Binding(get: { reason.title }, set: { var r = reason; r.title = $0; store.updateReason(r) }))
                    Picker("Kind", selection: Binding(get: { reason.kind }, set: { var r = reason; r.kind = $0; store.updateReason(r) })) {
                        ForEach(SkipKind.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    // Удалить — как привязанное напоминание: красный минус справа.
                    Button(role: .destructive) {
                        if let i = store.reasons.firstIndex(where: { $0.id == reason.id }) { store.deleteReasons(at: [i]) }
                    } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                }
                // С отступом подгруппы и плотнее обычных строк.
                .listRowInsets(EdgeInsets(top: 2, leading: 36, bottom: 2, trailing: 16))
                .listRowSeparator(.hidden)
            }
            .onDelete { store.deleteReasons(at: $0) }
            .onMove { store.moveReasons(from: $0, to: $1) }
            HStack {
                TextField("New Reason", text: $newTitle).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill") }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 20)
            .listRowSeparator(.hidden, edges: .top)
        } header: {
            RoundedHeader("Why Not Done")
        } footer: {
            Text("Turned on in each habit's settings.")
        }
    }

    private func add() {
        if store.addReason(newTitle) != nil { newTitle = "" }
    }
}

struct SymbolField: View {
    let title: String
    @Binding var symbol: String

    var body: some View {
        HStack {
            InputRow(title: title, placeholder: "SF Symbol", text: $symbol, monospaced: true)
            Image(systemName: symbol.isEmpty ? "questionmark" : symbol).foregroundStyle(.secondary).frame(width: 22)
        }
    }
}

// MARK: - Настройки календаря

struct CalendarSettingsView: View {
    @ObservedObject var store: HabitStore
    @State private var titleY: CGFloat?
    @AppStorage(CalendarSettings.Key.alertsEnabled, store: AppGroup.defaults) private var alertsEnabled = true
    @AppStorage(CalendarSettings.Key.keepAfterTap, store: AppGroup.defaults) private var keepAfterTap = true
    @AppStorage(CalendarSettings.Key.keepAfterSwipe, store: AppGroup.defaults) private var keepAfterSwipe = true
    @AppStorage(CalendarSettings.Key.notifyMovedIntoPast, store: AppGroup.defaults) private var notifyMovedIntoPast = true
    @AppStorage(CalendarSettings.Key.removeWhenMovedLater, store: AppGroup.defaults) private var removeMovedLater = true
    @AppStorage(CalendarSettings.Key.removeWhenDeleted, store: AppGroup.defaults) private var removeDeleted = true
    @AppStorage(CalendarSettings.Key.staleLabelMinutes, store: AppGroup.defaults) private var staleMinutes = 30
    @AppStorage(CalendarSettings.Key.cursorHex, store: AppGroup.defaults) private var cursorHex = CalendarSettings.defaultCursorHex
    @AppStorage(CalendarSettings.Key.cursorOverEventOpacity, store: AppGroup.defaults) private var cursorOverEvent = 0.7
    @AppStorage(CalendarSettings.Key.bellOpacityLight, store: AppGroup.defaults) private var bellLight = 0.5
    @AppStorage(CalendarSettings.Key.bellOpacityDark, store: AppGroup.defaults) private var bellDark = 0.7
    @AppStorage(CalendarSettings.Key.bellHexLight, store: AppGroup.defaults) private var bellHexLight = ""
    @AppStorage(CalendarSettings.Key.bellHexDark, store: AppGroup.defaults) private var bellHexDark = ""
    @AppStorage(CalendarSettings.Key.bellSize, store: AppGroup.defaults) private var bellSize = 9.0
    @AppStorage(CalendarSettings.Key.bellInsetTop, store: AppGroup.defaults) private var bellInsetTop = 3.0
    @AppStorage(CalendarSettings.Key.bellInsetRight, store: AppGroup.defaults) private var bellInsetRight = 3.0
    @AppStorage(CalendarSettings.Key.defaultDayStart, store: AppGroup.defaults) private var dayStart = 6
    @AppStorage(CalendarSettings.Key.defaultDayEnd, store: AppGroup.defaults) private var dayEnd = 24

    var body: some View {
        Form {
            PageTitleRow("Calendar Enhancer Settings", y: $titleY)
            Section {
                Toggle("Alert Notifications", isOn: $alertsEnabled)
                Toggle("Keep Notification After Tap", isOn: $keepAfterTap)
                Toggle("Keep Notification After Swipe", isOn: $keepAfterSwipe)
            } header: {
                RoundedHeader("Notifications")
            } footer: {
                Text("Notifications for events with alerts are scheduled \(CalendarSettings.alertDaysAhead) days ahead.")
            }
            .listSectionSpacing(18)
            Section {
                Toggle("Notify When Event Moves Earlier Than Now", isOn: $notifyMovedIntoPast)
                Toggle("Remove When Event Moves Later", isOn: $removeMovedLater)
                Toggle("Remove When Event Is Deleted", isOn: $removeDeleted)
            } footer: {
                Text("If an event is moved so that its alert time has already passed, the alert notification comes right away.")
            }
            .listSectionSpacing(18)
            Section {
                AppIconPicker()
            }
            Section {
                Picker("Default Day Start", selection: $dayStart) { ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) } }
                Picker("Default Day End", selection: $dayEnd) { ForEach(0...24, id: \.self) { Text("\($0):00").tag($0) } }
                ValueStepper("Show “synced N min ago” after", shown: "\(staleMinutes)", after: "min", value: $staleMinutes, in: 5...240, step: 5)
                HexField(title: "Cursor Color", hex: Binding(get: { cursorHex == "#E9534CFF" ? CalendarSettings.defaultCursorHex : cursorHex },
                                                             set: { cursorHex = String($0.prefix(7)) }), alpha: false)
                VStack(alignment: .leading) {
                    Text("Cursor over events: \(Int((cursorOverEvent * 100).rounded()))%")
                    Slider(value: $cursorOverEvent, in: 0...1)
                }
                // Пусто — цвет календаря события.
                HexField(title: "Alert bell color, light", hex: $bellHexLight, alpha: false)
                VStack(alignment: .leading) {
                    Text("Alert bell opacity, light: \(Int((bellLight * 100).rounded()))%")
                    Slider(value: $bellLight, in: 0...1)
                }
                HexField(title: "Alert bell color, dark", hex: $bellHexDark, alpha: false)
                VStack(alignment: .leading) {
                    Text("Alert bell opacity, dark: \(Int((bellDark * 100).rounded()))%")
                    Slider(value: $bellDark, in: 0...1)
                }
                ValueStepper("Alert bell size:", shown: "\(Int(bellSize))", after: "pt", value: $bellSize, in: 5...16, step: 1)
                ValueStepper("Bell from top:", shown: "\(Int(bellInsetTop))", after: "pt", value: $bellInsetTop, in: 0...10, step: 1)
                ValueStepper("Bell from right:", shown: "\(Int(bellInsetRight))", after: "pt", value: $bellInsetRight, in: 0...10, step: 1)
            } header: {
                RoundedHeader("Widget")
            } footer: {
                Text("Default Day Start and End apply to calendar widgets whose Day start/end is set to “Default”. An empty bell color means the event's calendar color. On events too short for the bell it gets smaller and stays centered between the top and bottom edges.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .listPageTitle("Calendar Enhancer Settings", sideInset: PageTitle.sideInset, rowY: titleY)
        .collapsingTitle("Calendar Enhancer Settings")
        .contentMargins(.top, -PageTitle.subpageRaise, for: .scrollContent)
        .refreshable { await store.forceRefresh() }
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
    }
}
