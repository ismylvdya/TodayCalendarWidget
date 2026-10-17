import AppIntents
import EventKit
import EventKitUI
import SwiftUI
import UserNotifications
import WidgetKit

/// iOS-приложение: привычки, настройки, доступ к календарю (виджет сам запросить его
/// не может) и уведомления для событий с alert.
@main
struct TripleTodayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Заголовки экранов — скруглённым шрифтом, как названия списков в Reminders.
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: rounded(30, .bold)]
        UINavigationBar.appearance().titleTextAttributes = [.font: rounded(17, .semibold)]
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Куда перейти после нажатия на уведомление или виджет.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var habit: UUID?
    /// Ошибка синхронизации или удаления — показывается алертом.
    @Published var issue: String?
    /// Плашка сверху: итог действия (слияние, удаление, импорт…).
    @Published var toast: Toast?
}

/// Плашка об успехе или ошибке действия — сверху экрана, исчезает сама.
struct Toast: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool

    @MainActor static func show(_ text: String, error: Bool = false) {
        withAnimation(.spring(duration: 0.35)) { AppRouter.shared.toast = Toast(text: text, isError: error) }
    }
}

/// Ширина и форма углов плашки — в настройках.
enum ToastSettings {
    enum Key {
        static let width = "toastWidth"
        static let corners = "toastCorners"
    }
    enum Corners: String, CaseIterable, Identifiable {
        case round, squircle
        var id: String { rawValue }
        var title: String { self == .round ? "Round" : "Squircle" }
    }
    /// Ширина по умолчанию: кнопка «назад» слева остаётся открытой.
    static let defaultWidth = 255.0
    static var widthRange: ClosedRange<Double> { 160...Double(UIScreen.main.bounds.width) - 16 }
}

struct ToastView: View {
    let toast: Toast
    @AppStorage(ToastSettings.Key.width, store: AppGroup.defaults) private var width = ToastSettings.defaultWidth
    @AppStorage(ToastSettings.Key.corners, store: AppGroup.defaults) private var corners = ToastSettings.Corners.round.rawValue

    private var shape: AnyShape {
        corners == ToastSettings.Corners.squircle.rawValue
            ? AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) : AnyShape(Capsule())
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .orange : .green)
            Text(toast.text).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
        }
        // Ровно заданной ширины, а не по тексту (иначе ширина менялась скачками — по переносам).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: shape)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        // Под плашкой и ещё примерно на 31 pt вокруг — системное размытие, мягко сходящее на нет.
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .padding(-31)
                .mask(shape.padding(-18).blur(radius: 14))
                .allowsHitTesting(false)
        }
        // Уже экрана: кнопка «назад» слева остаётся открытой, текст переносится в высоту.
        .frame(width: min(max(width, ToastSettings.widthRange.lowerBound), ToastSettings.widthRange.upperBound))

    }
}

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    private let store = EKEventStore()

    var body: some View {
        MainView(openHabit: router.habit)
            .overlay(alignment: .top) {
                if let toast = router.toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // Висит 10 секунд; раньше — нажатием или смахиванием вверх.
                        .onTapGesture { withAnimation { router.toast = nil } }
                        .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                            if value.translation.height < -10 { withAnimation { router.toast = nil } }
                        })
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(10))
                            if router.toast?.id == toast.id { withAnimation { router.toast = nil } }
                        }
                }
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { router.issue != nil }, set: { if !$0 { router.issue = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(router.issue ?? "")
            }
            .onOpenURL { url in
                // Нажатие на календарный виджет (calshow:<дата>) — сразу в Calendar;
                // на виджет привычки (todaycalendarwidget://habit/<id>) — на её страницу.
                if url.scheme == "calshow" { UIApplication.shared.open(url) }
                if url.host == "habit", let id = UUID(uuidString: url.lastPathComponent) { router.habit = id }
            }
            .task {
                if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                    _ = try? await store.requestFullAccessToEvents()
                }
                if !ReminderSync.hasAccess { _ = await ReminderSync.requestAccess() }
                // При каждом запуске: разрешение на уведомления (первый раз — с запросом) и синхронизация.
                await AlertScheduler.requestAuthorization()
                await AlertScheduler.sync()
                WidgetCenter.shared.reloadAllTimelines()
                FilesBackup.write()
            }
            .onAppear {
                #if DEBUG
                DebugSeed.runIfRequested(store: store)
                Task {
                    await DebugSeed.seedAlertIfRequested(store: store)
                    await DebugSeed.moveSeededIfRequested(store: store)
                await DebugSeed.seedReminderIfRequested()
                await DebugSeed.dumpRemindersIfRequested()
                await DebugSeed.testAttachmentIfRequested()
                }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                // Открытие приложения — заодно повод сразу обновить виджеты и уведомления.
                guard phase == .active else { return }
                WidgetCenter.shared.reloadAllTimelines()
                Task {
                        await AlertScheduler.sync()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
    }
}

/// Принимает действия из уведомлений, в том числе когда iOS запускает приложение в фоне.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Несколько ошибок подряд — в одном алерте.
        SyncIssues.handler = { message in
            Task { @MainActor in
                let router = AppRouter.shared
                router.issue = router.issue.map { $0.contains(message) ? $0 : $0 + "\n\n" + message } ?? message
            }
        }
        AlertScheduler.registerCategory()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            // Смахнули — возвращаем (тихо), если так настроено.
            if CalendarSettings.keepAfterSwipe { await AlertScheduler.keepAfterOpening(response.notification) }
        case AlertScheduler.deleteAction:
            AlertScheduler.deleteEvent(userInfo: info)
        case UNNotificationDefaultActionIdentifier:
            if CalendarSettings.keepAfterTap { await AlertScheduler.keepAfterOpening(response.notification) }
            // Всегда Calendar — на дне события, за час до него.
            if let url = AlertScheduler.calendarURL(userInfo: info) { await UIApplication.shared.open(url) }
        default:
            break
        }
    }

    /// Уведомление, пришедшее при открытом приложении, тоже показываем.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

// MARK: - Команды

/// Действие для автоматизации в Командах (например, «Calendar закрыт»): перечитать события
/// и пересоздать уведомления, не открывая приложение.
struct SyncAlertsIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Alerts"
    static var description = IntentDescription("Re-reads calendar events and reschedules alert notifications.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await AlertScheduler.sync()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TodayCalendarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SyncAlertsIntent(), phrases: ["Sync alerts in \(.applicationName)"],
                    shortTitle: "Sync Alerts", systemImageName: "bell.badge")
    }
}

#if DEBUG
/// Для проверки в симуляторе: запуск с аргументом `-SeedSampleEvents` добавляет
/// в календарь по умолчанию тестовые события на сегодня (один раз).
enum DebugSeed {
    /// `-DumpReminders`: печатает напоминания (открытые и выполненные за неделю) и привязки привычек.
    static func dumpRemindersIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-DumpReminders") else { return }
        let store = ReminderSync.store
        store.reset()
        func line(_ r: EKReminder) -> String {
            let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            return "\(r.calendarItemIdentifier) '\(r.title ?? "")' due=\(String(describing: due)) done=\(r.isCompleted) "
                + "doneAt=\(String(describing: r.completionDate)) mod=\(String(describing: r.lastModifiedDate)) rec=\(r.recurrenceRules?.count ?? 0)"
        }
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: Date().addingTimeInterval(-7 * 86400), ending: Date(), calendars: nil)
        for (name, p) in [("OPEN", open), ("DONE", done)] {
            let items: [EKReminder] = await withCheckedContinuation { c in store.fetchReminders(matching: p) { c.resume(returning: $0 ?? []) } }
            for r in items { print("DUMP \(name) \(line(r))") }
        }
        for h in HabitStorage.load().habits { for l in h.links { print("DUMP LINK '\(h.name)' \(l.reminderID) lastDue=\(l.lastDue ?? "nil") titles=\(l.titles)") } }
    }

    static func runIfRequested(store: EKEventStore) {
        guard ProcessInfo.processInfo.arguments.contains("-SeedSampleEvents"),
              EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { return }
        let day = Calendar.current.startOfDay(for: Date())
        let existing = store.events(matching: store.predicateForEvents(withStart: day, end: day.addingTimeInterval(86400), calendars: nil))
        guard existing.isEmpty else { return }
        let samples: [(String, Double, Double, Bool)] = [
            ("pay bills", 0, 24, true), ("workout", 7.5, 0.5, false), ("call", 10, 1, false),
            ("long workshop", 11, 2.5, false), ("meeting", 12, 3, false), ("call mom", 18, 0.5, false),
            ("market?", 19, 1, false),
        ]
        for (title, start, duration, allDay) in samples {
            let ev = EKEvent(eventStore: store)
            ev.title = title
            ev.calendar = calendar
            ev.isAllDay = allDay
            ev.startDate = day.addingTimeInterval(start * 3600)
            ev.endDate = ev.startDate.addingTimeInterval(duration * 3600 - (allDay ? 1 : 0))
            try? store.save(ev, span: .thisEvent, commit: false)
        }
        try? store.commit()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `-SeedAlertEvent`: событие через 5 минут с alert через 40 секунд — для проверки уведомлений.
    static func seedAlertIfRequested(store: EKEventStore) async {
        guard ProcessInfo.processInfo.arguments.contains("-SeedAlertEvent"),
              let calendar = store.defaultCalendarForNewEvents else { return }
        let ev = EKEvent(eventStore: store)
        ev.title = "Buy groceries"
        ev.location = "Whole Foods"
        ev.calendar = calendar
        ev.startDate = Date().addingTimeInterval(5 * 60)
        ev.endDate = ev.startDate.addingTimeInterval(30 * 60)
        ev.addAlarm(EKAlarm(absoluteDate: Date().addingTimeInterval(40)))
        try? store.save(ev, span: .thisEvent, commit: true)
        await AlertScheduler.requestAuthorization()
        await AlertScheduler.sync()
    }

    /// `-SeedReminder`: ежедневное повторяющееся напоминание «Read 20 pages» — для проверки привязки.
    static func seedReminderIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-SeedReminder") else { return }
        let store = ReminderSync.store
        guard await ReminderSync.requestAccess(), let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Read 20 pages"
        reminder.calendar = list
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        try? store.save(reminder, commit: true)
    }

    /// `-TestAttachment`: через 5 секунд уведомление с PNG-вложением на прозрачном фоне.
    static func testAttachmentIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-TestAttachment") else { return }
        await AlertScheduler.requestAuthorization()
        let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .bold)
        let symbol = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)!
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat(); format.opaque = false; format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).pngData { _ in
            symbol.draw(in: CGRect(x: 20, y: 20, width: 160, height: 160))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("habit-test.png")
        try? png.write(to: url)
        let content = UNMutableNotificationContent()
        content.title = "📥 инбокс разобрать"
        content.body = "2/3 this week"
        if let attachment = try? UNNotificationAttachment(identifier: "img", url: url) { content.attachments = [attachment] }
        let request = UNNotificationRequest(identifier: "attachment-test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// `-MoveSeededLater`: сдвигает тестовые «Buy groceries» на час позже и синхронизирует.
    static func moveSeededIfRequested(store: EKEventStore) async {
        guard ProcessInfo.processInfo.arguments.contains("-MoveSeededLater") else { return }
        let now = Date()
        let events = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                                      end: now.addingTimeInterval(3 * 3600), calendars: nil))
        for ev in events where ev.title == "Buy groceries" {
            ev.startDate = ev.startDate.addingTimeInterval(3600)
            ev.endDate = ev.endDate.addingTimeInterval(3600)
            try? store.save(ev, span: .thisEvent, commit: true)
        }
        await AlertScheduler.sync()
    }
}
#endif
