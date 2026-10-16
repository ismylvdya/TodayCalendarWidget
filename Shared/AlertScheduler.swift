#if os(iOS)
import EventKit
import UserNotifications
import WidgetKit

/// Свои уведомления для событий с alert (вместо уведомлений Calendar, которые пользователь выключает).
/// Уведомления расписываются заранее: при синхронизации все наши запланированные уведомления
/// заменяются актуальными на ближайшие дни.
enum AlertScheduler {
    static let category = "EVENT_ALERT"
    static let deleteAction = "DELETE_EVENT"
    private static let idPrefix = "alert|"
    /// iOS держит не больше 64 запланированных уведомлений на приложение; оставляем запас.
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

    /// Перечитывает события и пересоздаёт уведомления.
    static func sync(now: Date = Date()) async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        registerCategory()

        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard CalendarSettings.alertsEnabled else { return }
        let requests = upcomingAlerts(now: now).prefix(limit).map(\.request)
        for request in requests {
            do { try await center.add(request) } catch {
                SyncIssues.report("Couldn't schedule event notifications: \(error.localizedDescription)", once: true)
            }
        }
        await removeDeliveredForMovedEvents()
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
    }

    private static func upcomingAlerts(now: Date) -> [Alert] {
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
                guard fire > now, fire < end else { continue }
                alerts.append(Alert(fireDate: fire, request: request(for: event, alarmIndex: index, fire: fire)))
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

    /// Calendar на дне и времени события, к которому относилось уведомление.
    static func calendarURL(userInfo: [AnyHashable: Any]) -> URL? {
        guard let start = userInfo["start"] as? Double else { return nil }
        return URL(string: "calshow:\(Int(start))")
    }
}

#endif
