import EventKit
import UserNotifications
import WidgetKit

/// Свои уведомления для событий с alert (вместо уведомлений Calendar, которые пользователь выключает).
/// Общие для iOS и macOS: на Mac их шлёт фоновое приложение Calendar Widget.
/// Уведомления расписываются заранее: при синхронизации все наши запланированные уведомления
/// заменяются актуальными на ближайшие дни.
enum AlertScheduler {
    static let category = "EVENT_ALERT"
    static let deleteAction = "DELETE_EVENT"
    private static let idPrefix = "alert|"
    /// iOS (и macOS) держит не больше 64 запланированных уведомлений на приложение; оставляем запас.
    private static let limit = 60

    /// Категория уведомлений о событиях — с кнопкой «Delete event».
    static func registerCategory() {
        let delete = UNNotificationAction(identifier: deleteAction, title: "Delete event", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "checkmark.circle.fill"))
        // customDismissAction: смахивание приходит в приложение — и уведомление возвращается.
        let event = UNNotificationCategory(identifier: category, actions: [delete], intentIdentifiers: [],
                                           options: [.customDismissAction])
        UNUserNotificationCenter.current().setNotificationCategories([event])
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Перечитывает события и пересоздаёт уведомления. Возвращает, сколько уведомлений
    /// запланировано (nil — нет доступа к календарю или уведомлениям, либо они выключены).
    @discardableResult
    static func sync(now: Date = Date()) async -> Int? {
        await removeLeftovers()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return nil }
        registerCategory()

        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard CalendarSettings.alertsEnabled else { return nil }
        let all = alerts(now: now)
        let future = all.filter { $0.fireDate > now }
        await notifyMovedIntoPast(all, now: now)
        // Запоминаем ещё не сработавшие alert — по ним видно, что событие потом перенесли раньше.
        AppGroup.defaults.set(Dictionary(future.map { ($0.key, $0.fireDate.timeIntervalSinceReferenceDate) }, uniquingKeysWith: min),
                              forKey: pendingKey)
        let requests = future.prefix(limit).map(\.request)
        for request in requests {
            do { try await center.add(request) } catch {
                SyncIssues.report("Couldn't schedule event notifications: \(error.localizedDescription)", once: true)
            }
        }
        await removeDeliveredForMovedEvents()
        return requests.count
    }

    /// Приложение шлёт только уведомления о событиях. Всё остальное, что осталось в очереди iOS
    /// от прежних версий (повторяющиеся напоминания привычек «habit|…», уведомления о долгом
    /// пропуске «skip|…», тестовые), — убираем: и запланированные, и уже показанные.
    private static func removeLeftovers() async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { !$0.hasPrefix(idPrefix) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
            .filter { $0.hasPrefix("habit|") || $0.hasPrefix("skip|") || $0.hasPrefix("skip-sample|") || $0 == "attachment-test" }
        if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
    }

    /// После нажатия или смахивания iOS убирает уведомление — кладём его обратно тихо
    /// (без баннера и звука), чтобы оно осталось в списке вместе с кнопками.
    static func keepAfterOpening(_ notification: UNNotification) async {
        guard let content = notification.request.content.mutableCopy() as? UNMutableNotificationContent else { return }
        content.sound = nil
        content.interruptionLevel = .passive
        let id = notification.request.identifier
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Убирает показанные уведомления, чьё событие перенесли на более позднее время
    /// (и удалённые события, если так настроено). Событие на месте или перенесённое
    /// раньше — уведомление остаётся.
    private static func removeDeliveredForMovedEvents() async {
        let movedLater = CalendarSettings.removeWhenMovedLater, deleted = CalendarSettings.removeWhenDeleted
        guard movedLater || deleted else { return }
        let center = UNUserNotificationCenter.current()
        let store = EKEventStore()
        var stale: [String] = []
        for note in await center.deliveredNotifications() where note.request.identifier.hasPrefix(idPrefix) {
            let info = note.request.content.userInfo
            guard let id = info["eventID"] as? String,
                  let startValue = info["start"] as? Double else { continue }
            let start = Date(timeIntervalSinceReferenceDate: startValue)
            // Повторения одного события имеют общий ID; ищем их рядом с прежней датой.
            let window = store.predicateForEvents(withStart: start.addingTimeInterval(-7 * 86400),
                                                  end: start.addingTimeInterval(60 * 86400), calendars: nil)
            let occurrences = store.events(matching: window).filter { $0.eventIdentifier == id }
            if occurrences.contains(where: { $0.startDate == start }) { continue }
            let nearest = occurrences.min { abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start)) }
            if let nearest {
                if movedLater && nearest.startDate > start { stale.append(note.request.identifier) }
            } else if deleted {
                stale.append(note.request.identifier)
            }
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    private struct Alert {
        let fireDate: Date
        let request: UNNotificationRequest
        /// Событие и номер alert — не меняются при переносе события.
        let key: String
    }

    /// Ещё не сработавшие alert с прошлой синхронизации: «событие|номер» → время.
    private static let pendingKey = "pendingAlertFires"

    /// Событие с alert перенесли раньше так, что время alert уже прошло, а уведомления не было:
    /// присылаем его сразу (если так настроено). Alert, сработавший сам в своё время, сюда не
    /// попадает: его прежнее время уже тоже в прошлом.
    private static func notifyMovedIntoPast(_ alerts: [Alert], now: Date) async {
        guard CalendarSettings.notifyMovedIntoPast,
              let stored = AppGroup.defaults.dictionary(forKey: pendingKey) as? [String: Double] else { return }
        let center = UNUserNotificationCenter.current()
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        for alert in alerts where alert.fireDate <= now {
            guard let was = stored[alert.key].map(Date.init(timeIntervalSinceReferenceDate:)), was > now, alert.fireDate < was else { continue }
            let id = alert.request.identifier + "|moved"
            guard !delivered.contains(id) else { continue }
            try? await center.add(UNNotificationRequest(identifier: id, content: alert.request.content, trigger: nil))
        }
    }

    /// Alert событий от суток назад до `alertDaysAhead` вперёд (и прошедшие — для переносов).
    private static func alerts(now: Date) -> [Alert] {
        let store = EKEventStore()
        let end = Calendar.current.date(byAdding: .day, value: CalendarSettings.alertDaysAhead, to: now)!
        // Захватываем и начавшиеся раньше события: их alert мог быть задан после начала.
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.status != .canceled }

        var alerts: [Alert] = []
        for event in events {
            for (index, alarm) in (event.alarms ?? []).enumerated() {
                let fire = alarm.absoluteDate ?? event.startDate.addingTimeInterval(alarm.relativeOffset)
                guard fire > start, fire < end else { continue }
                alerts.append(Alert(fireDate: fire, request: request(for: event, alarmIndex: index, fire: fire),
                                    key: "\(event.eventIdentifier ?? "")|\(index)"))
            }
        }
        return alerts.sorted { $0.fireDate < $1.fireDate }
    }

    private static func request(for event: EKEvent, alarmIndex: Int, fire: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.title ?? ""
        content.body = timeText(for: event) + (event.location.map { $0.isEmpty ? "" : "\n\($0)" } ?? "")
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = "events"
        content.userInfo = ["eventID": event.eventIdentifier ?? "",
                            "calendarID": event.calendar.calendarIdentifier,
                            "start": event.startDate.timeIntervalSinceReferenceDate]

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let id = "\(idPrefix)\(event.eventIdentifier ?? "")|\(event.startDate.timeIntervalSinceReferenceDate)|\(alarmIndex)"
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// «15:00 – 16:00», «All day» или с датой, если событие не сегодня.
    private static func timeText(for event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        let time = DateFormatter()
        time.dateFormat = "H:mm"
        let range = "\(time.string(from: event.startDate)) – \(time.string(from: event.endDate))"
        guard !Calendar.current.isDateInToday(event.startDate) else { return range }
        let day = DateFormatter()
        day.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return "\(day.string(from: event.startDate)), \(range)"
    }

    /// Удаляет то повторение события, к которому относилось уведомление.
    static func deleteEvent(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["eventID"] as? String,
              let start = (userInfo["start"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)) else { return }
        let store = EKEventStore()
        let window = store.predicateForEvents(withStart: start.addingTimeInterval(-60),
                                              end: start.addingTimeInterval(60), calendars: nil)
        guard let event = store.events(matching: window).first(where: { $0.eventIdentifier == id && $0.startDate == start })
                ?? store.event(withIdentifier: id) else {
            SyncIssues.report("The event was not found in Calendar — it may have already been deleted or moved.")
            return
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            SyncIssues.report("Couldn't delete “\(event.title ?? "")”: \(error.localizedDescription)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Calendar открывается на час раньше события — оно видно не у самого верха.
    static func calendarURL(userInfo: [AnyHashable: Any]) -> URL? {
        guard let start = userInfo["start"] as? Double else { return nil }
        return URL(string: "calshow:\(Int(start - 3600))")
    }
}
