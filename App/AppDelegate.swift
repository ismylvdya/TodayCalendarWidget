import AppKit
import EventKit
import ServiceManagement
import WidgetKit

/// Фоновый агент: доступ к календарю, автозапуск, обновление виджета, открытие Calendar по клику.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = EKEventStore()
    private var lastFingerprint = ""
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
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { self.start(granted: granted) }
        }
    }

    private func start(granted: Bool) {
        guard granted else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Нет доступа к календарю"
            alert.informativeText = "Разрешите TodayCalendarWidget полный доступ к календарям в Системных настройках → Конфиденциальность и безопасность → Календари, затем перезапустите приложение."
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
    }

    private func refresh(force: Bool) {
        let fingerprint = CalendarData.fingerprint(CalendarData.todayEvents(store: store))
        guard force || fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        WidgetCenter.shared.reloadAllTimelines()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}
