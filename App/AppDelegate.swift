import AppKit
import EventKit
import ServiceManagement
import UserNotifications
import WidgetKit

/// Фоновый агент: доступ к календарю, автозапуск, обновление виджета, открытие Calendar по клику
/// и уведомления о событиях с alert (как в iOS: с кнопкой «Delete event», настройки — по умолчанию).
@main
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let store = EKEventStore()
    private var lastFingerprint = ""
    private var lastReload = Date.distantPast
    private var lastAlertSync = Date.distantPast
    private var timer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? SMAppService.mainApp.register()
        UNUserNotificationCenter.current().delegate = self
        AlertScheduler.registerCategory()
        SyncIssues.handler = { message in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Calendar Enhancer"
                alert.informativeText = message
                alert.runModal()
            }
        }
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { self.start(granted: granted) }
        }
    }

    private func start(granted: Bool) {
        guard granted else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Нет доступа к календарю"
            alert.informativeText = "Разрешите Calendar Enhancer полный доступ к календарям в Системных настройках → Конфиденциальность и безопасность → Календари, затем перезапустите приложение."
            alert.runModal()
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            return
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh(force: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        refresh(force: true)
        Task { await AlertScheduler.requestAuthorization(); await self.syncAlerts() }
    }

    /// Уведомления пересоздаются при изменении событий и не реже раза в 15 минут.
    @MainActor private func syncAlerts() async {
        lastAlertSync = Date()
        await AlertScheduler.sync()
    }

    /// Перезагружает виджет, если события изменились, и не реже раза в 15 минут —
    /// чтобы виджет считал данные свежими и не показывал подпись «N min ago».
    private func refresh(force: Bool) {
        let fingerprint = CalendarData.fingerprint(CalendarData.upcomingEvents(store: store))
        let stale = Date().timeIntervalSince(lastReload) >= 15 * 60
        if force || fingerprint != lastFingerprint || Date().timeIntervalSince(lastAlertSync) >= 15 * 60 {
            Task { await syncAlerts() }
        }
        guard force || stale || fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        lastReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Клик по виджету: Calendar открывается на сегодняшнем дне. Если управлять
    /// Calendar не разрешено, он просто открывается.
    func application(_ application: NSApplication, open urls: [URL]) {
        openCalendar(at: Date())
    }

    /// Calendar на дне `date`, на час раньше него — нужное время видно не у самого верха.
    private func openCalendar(at date: Date) {
        let offset = Int(date.timeIntervalSinceNow) - 3600
        let script = NSAppleScript(source: """
            tell application "Calendar"
                activate
                view calendar at ((current date) + (\(offset)))
            end tell
            """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }

    // MARK: Уведомления

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            // Закрыли — возвращаем (тихо), если так настроено.
            if CalendarSettings.keepAfterSwipe { await AlertScheduler.keepAfterOpening(response.notification) }
        case AlertScheduler.deleteAction:
            AlertScheduler.deleteEvent(userInfo: info)
        case UNNotificationDefaultActionIdentifier:
            if CalendarSettings.keepAfterTap { await AlertScheduler.keepAfterOpening(response.notification) }
            // Нажатие — Calendar на дне события, за час до него.
            let start = (info["start"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date()
            await MainActor.run { openCalendar(at: start) }
        default:
            break
        }
    }

    /// Уведомление при работающем приложении (оно работает всегда) — тоже показываем.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
