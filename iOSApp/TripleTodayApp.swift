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
    struct EventRef: Identifiable { let id: String; let start: Date }
    @Published var event: EventRef?
    @Published var habit: UUID?
}

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    private let store = EKEventStore()

    var body: some View {
        MainView(openHabit: router.habit)
            .onOpenURL { url in
                // Нажатие на календарный виджет (calshow:<дата>) — сразу в Calendar;
                // на виджет привычки (todaycalendarwidget://habit/<id>) — на её страницу.
                if url.scheme == "calshow" { UIApplication.shared.open(url) }
                if url.host == "habit", let id = UUID(uuidString: url.lastPathComponent) { router.habit = id }
            }
            .sheet(item: $router.event) { EventCard(ref: $0) }
            .task {
                if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                    _ = try? await store.requestFullAccessToEvents()
                }
                if !ReminderSync.hasAccess { _ = await ReminderSync.requestAccess() }
                // При каждом запуске: разрешение на уведомления (первый раз — с запросом) и синхронизация.
                await AlertScheduler.requestAuthorization()
                await HabitNotifier.sync()
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
                    await HabitNotifier.sync()
                    await AlertScheduler.sync()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
    }
}

/// Системная карточка события (как в Calendar) — по нажатию на уведомление, если так настроено.
struct EventCard: UIViewControllerRepresentable {
    let ref: AppRouter.EventRef

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = EKEventStore()
        let window = store.predicateForEvents(withStart: ref.start.addingTimeInterval(-60), end: ref.start.addingTimeInterval(60), calendars: nil)
        let controller = EKEventViewController()
        controller.event = store.events(matching: window).first { $0.eventIdentifier == ref.id } ?? store.event(withIdentifier: ref.id)
        controller.allowsEditing = true
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

/// Принимает действия из уведомлений, в том числе когда iOS запускает приложение в фоне.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AlertScheduler.registerCategory()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case HabitNotifier.doneAction, HabitNotifier.partialAction, HabitNotifier.overAction:
            await HabitNotifier.handle(action: response.actionIdentifier, userInfo: info)
            await MainActor.run { FilesBackup.write() }
        case UNNotificationDismissActionIdentifier:
            // Смахнули — возвращаем (тихо).
            await AlertScheduler.keepAfterOpening(response.notification)
        case UNNotificationDefaultActionIdentifier where info["habitID"] != nil:
            await AlertScheduler.keepAfterOpening(response.notification)
            if let raw = info["habitID"] as? String, let id = UUID(uuidString: raw) {
                await MainActor.run { AppRouter.shared.habit = id }
            }
        case AlertScheduler.deleteAction:
            AlertScheduler.deleteEvent(userInfo: info)
        case UNNotificationDefaultActionIdentifier:
            if CalendarSettings.keepAfterTap { await AlertScheduler.keepAfterOpening(response.notification) }
            if CalendarSettings.notificationTapOpensEvent,
               let id = info["eventID"] as? String, let start = info["start"] as? Double {
                await MainActor.run { AppRouter.shared.event = .init(id: id, start: Date(timeIntervalSinceReferenceDate: start)) }
            } else if let url = AlertScheduler.calendarURL(userInfo: info) {
                await UIApplication.shared.open(url)
            }
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
