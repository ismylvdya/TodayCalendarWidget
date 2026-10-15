import AppIntents
import EventKit
import SwiftUI
import UserNotifications
import WidgetKit

/// iOS-приложение: доступ к календарю (виджет сам запросить его не может) и уведомления
/// для событий с alert.
@main
struct TripleTodayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AccessView()
                // Нажатие на виджет может прийти сюда (calshow:<дата>) — сразу открываем Calendar.
                .onOpenURL { url in
                    if url.scheme == "calshow" { UIApplication.shared.open(url) }
                }
        }
    }
}

struct AccessView: View {
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    @Environment(\.scenePhase) private var scenePhase
    private let store = EKEventStore()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: status == .fullAccess ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(status == .fullAccess ? .green : .orange)
            Text("TodayCalendarWidget").font(.title.bold())
            if status == .fullAccess {
                Text("Calendar access granted. Add the Double Today widget to your Home Screen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("The widget needs full access to your calendars.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(status == .notDetermined ? "Allow Calendar Access" : "Open Settings") { requestAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .onAppear {
            if status == .notDetermined { requestAccess() }
            #if DEBUG
            DebugSeed.runIfRequested(store: store)
            Task {
                await DebugSeed.seedAlertIfRequested(store: store)
                await DebugSeed.moveSeededIfRequested(store: store)
            }
            #endif
        }
        // При каждом запуске: спросить разрешение на уведомления (первый раз — с запросом,
        // дальше — без) и пересоздать уведомления.
        .task {
            await AlertScheduler.requestAuthorization()
            await AlertScheduler.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            // Открытие приложения — заодно повод сразу обновить виджет.
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func requestAccess() {
        if status == .notDetermined {
            store.requestFullAccessToEvents { _, _ in
                DispatchQueue.main.async { refresh() }
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await AlertScheduler.requestAuthorization()
            await AlertScheduler.sync()
        }
    }
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
        case AlertScheduler.deleteAction:
            AlertScheduler.deleteEvent(userInfo: info)
        case UNNotificationDefaultActionIdentifier:
            await AlertScheduler.keepAfterOpening(response.notification)
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
