import AppKit
import EventKit
import ServiceManagement
import SwiftUI
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
    /// Значок в строке меню: настройки и выход.
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Запуск при входе в систему — по умолчанию включён (выключить можно в меню).
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        }
        setUpStatusItem()
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

    // MARK: Строка меню

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(named: "MenuBarIcon") {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.toolTip = "Calendar Enhancer"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Calendar Enhancer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for entry in menu.items where entry.action == #selector(openPreferences) { entry.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLaunchAtLogin(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView { [weak self] in
                WidgetCenter.shared.reloadAllTimelines()
                Task { await self?.syncAlerts() }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Calendar Enhancer Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Галочка «Launch at Login» — по текущему состоянию (его можно поменять и в Системных настройках).
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleLaunchAtLogin(_:)) }?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
