import Foundation
#if os(iOS)
import EventKit
import WidgetKit

/// Связь трекера привычек с Reminders.
/// Из Reminders в базу: выполненные напоминания становятся отметками в истории.
/// Из трекера в Reminders: только одно действие — отметить сегодняшнее напоминание выполненным.
enum ReminderSync {
    /// Одно хранилище на весь процесс: напоминания из EventKit живут, пока живо хранилище,
    /// из которого их достали (временное хранилище приводило к вылету).
    static let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Незавершённые напоминания из всех списков — для привязки к привычке.
    static func openReminders() async -> [EKReminder] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await fetch(predicate).sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    /// Подтягивает выполненные напоминания в историю привычек.
    static func sync(_ db: inout HabitDB, now: Date = Date()) async {
        guard hasAccess else { return }
        // Первая синхронизация — за два года, дальше — с запасом от прошлой.
        let since = db.lastReminderSync.map { $0.addingTimeInterval(-3 * 86400) }
            ?? Calendar.current.date(byAdding: .year, value: -2, to: now)!

        for i in db.habits.indices where !db.habits[i].links.isEmpty {
            // Обновляем запомненные названия: переименование в Reminders не ломает поиск копий.
            for j in db.habits[i].links.indices {
                let link = db.habits[i].links[j]
                if let reminder = store.calendarItem(withIdentifier: link.reminderID) as? EKReminder {
                    if let title = reminder.title, !link.titles.contains(title) { db.habits[i].links[j].titles.append(title) }
                    db.habits[i].links[j].listID = reminder.calendar.calendarIdentifier
                }
            }
            let links = db.habits[i].links
            let lists = store.calendars(for: .reminder).filter { list in links.contains { $0.listID == list.calendarIdentifier } }
            guard !lists.isEmpty else { continue }
            let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: now, calendars: lists)
            for reminder in await fetch(predicate) {
                guard let done = reminder.completionDate,
                      links.contains(where: { matches(reminder, $0) }) else { continue }
                let key = HabitDay.dayKey(forMoment: done)
                if !db.habits[i].removedDays.contains(key) { db.habits[i].completions.insert(key) }
            }
        }
        db.lastReminderSync = now
    }

    private static func matches(_ reminder: EKReminder, _ link: ReminderLink) -> Bool {
        if reminder.calendarItemIdentifier == link.reminderID { return true }
        return reminder.calendar.calendarIdentifier == link.listID && link.titles.contains(reminder.title ?? "")
    }

    /// Отмечает выполненными привязанные напоминания на сегодня (или просроченные).
    /// Единственное, что трекер меняет в Reminders.
    static func completeToday(_ habit: Habit, now: Date = Date()) {
        guard hasAccess else { return }
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        for link in habit.links {
            guard let reminder = store.calendarItem(withIdentifier: link.reminderID) as? EKReminder,
                  !reminder.isCompleted else { continue }
            if let due = reminder.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }), due >= endOfToday { continue }
            reminder.isCompleted = true
            try? store.save(reminder, commit: true)
        }
    }

    private static func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }
}
#endif

/// Отметка «сегодня выполнено» — из виджета и из приложения.
enum HabitActions {
    static func markToday(habitID: UUID, now: Date = Date()) {
        var marked: Habit?
        HabitStorage.update { db in
            guard let i = db.habits.firstIndex(where: { $0.id == habitID }) else { return }
            // Уже отмечено (в любом виде) — ничего не меняем.
            if db.habits[i].state(HabitDay.today(now)) == .none { db.habits[i].set(HabitDay.today(now), done: true) }
            marked = db.habits[i]
        }
        #if os(iOS)
        if let marked { ReminderSync.completeToday(marked, now: now) }
        #endif
    }
}
