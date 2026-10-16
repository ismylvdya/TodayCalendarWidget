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
        guard hasAccess else {
            if db.habits.contains(where: { !$0.links.isEmpty }) {
                SyncIssues.report("No access to Reminders — completed reminders can't be added to habits. Allow access in Settings → Apps → Habits on Reminders.", once: true)
            }
            return
        }
        // Долгоживущее хранилище кэширует напоминания — перечитываем свежие.
        store.reset()
        // Первая синхронизация — за два года, дальше — с запасом от прошлой.
        let since = db.lastReminderSync.map { $0.addingTimeInterval(-3 * 86400) }
            ?? Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let lastSync = db.lastReminderSync ?? .distantPast

        /// Засчитать день. Снятый в трекере день не возвращается от уже виденных выполнений,
        /// но новое выполнение (после прошлой синхронизации) — свежее действие: оно засчитывается
        /// всегда. Иначе однажды снятый день (например, сегодня при проверке) больше никогда
        /// не отмечался из Reminders.
        func credit(_ i: Int, _ key: String, fresh: Bool) {
            if fresh { db.habits[i].removedDays.remove(key) }
            if !db.habits[i].removedDays.contains(key) { db.habits[i].completions.insert(key) }
        }

        for i in db.habits.indices where !db.habits[i].links.isEmpty {
            // Обновляем запомненные названия: переименование в Reminders не ломает поиск копий.
            for j in db.habits[i].links.indices {
                let link = db.habits[i].links[j]
                guard let reminder = store.calendarItem(withIdentifier: link.reminderID) as? EKReminder else {
                    // Сообщаем только о текущей привязке активной привычки (прежние могли удалить намеренно).
                    if j == db.habits[i].links.indices.last, !db.habits[i].archived, !db.habits[i].isTrashed { SyncIssues.report("The reminder “\(link.titles.last ?? "")” linked to “\(db.habits[i].title)” was not found in Reminders — it may have been deleted.", once: true) }
                    continue
                }
                if let title = reminder.title, !link.titles.contains(title) { db.habits[i].links[j].titles.append(title) }
                db.habits[i].links[j].listID = reminder.calendar.calendarIdentifier
                // Повторяющееся напоминание при выполнении переезжает на следующий срок,
                // не оставляя выполненной копии: ловим сдвиг срока вперёд.
                if let due = reminder.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }) {
                    let dueKey = HabitDay.key(due)
                    // Засчитываем, только если срок ушёл на другой (более поздний) день, а прежний
                    // был не позже сегодняшнего: перенос «на позже сегодня» не считается.
                    if let last = link.lastDue, dueKey > last, last <= HabitDay.key(now) {
                        credit(i, HabitDay.dayKey(forMoment: min(reminder.lastModifiedDate ?? now, now)), fresh: true)
                    }
                    db.habits[i].links[j].lastDue = dueKey
                }
            }
            let links = db.habits[i].links
            let lists = store.calendars(for: .reminder).filter { list in links.contains { $0.listID == list.calendarIdentifier } }
            guard !lists.isEmpty else { continue }
            let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: now, calendars: lists)
            // Выполнения по дням: у «Twice a day» два за день (два напоминания или одно,
            // выполненное дважды) — день «дважды».
            var perDay: [String: (count: Int, fresh: Bool)] = [:]
            for reminder in await fetch(predicate) {
                guard let done = reminder.completionDate,
                      links.contains(where: { matches(reminder, $0) }) else { continue }
                let key = HabitDay.dayKey(forMoment: done)
                credit(i, key, fresh: done > lastSync)
                let old = perDay[key] ?? (0, false)
                perDay[key] = (old.count + 1, old.fresh || done > lastSync)
            }
            if db.habits[i].twiceADay {
                for (key, day) in perDay where day.count >= 2 && day.fresh && db.habits[i].completions.contains(key) {
                    db.habits[i].partialDays.remove(key)
                    db.habits[i].overDays.remove(key)
                    db.habits[i].twiceDays.insert(key)
                }
            }
        }
        db.lastReminderSync = now
    }

    private static func matches(_ reminder: EKReminder, _ link: ReminderLink) -> Bool {
        if reminder.calendarItemIdentifier == link.reminderID { return true }
        return reminder.calendar.calendarIdentifier == link.listID && link.titles.contains(reminder.title ?? "")
    }

    /// Отмечает выполненными `count` привязанных напоминаний на сегодня (или просроченных) —
    /// по одному, начиная с самого раннего срока: одна отметка в трекере — одно напоминание.
    /// Единственное, что трекер меняет в Reminders.
    static func completeNext(_ habit: Habit, count: Int = 1, now: Date = Date()) {
        guard hasAccess, count > 0 else { return }
        for _ in 0..<count { completeEarliest(habit, now: now) }
    }

    private static func completeEarliest(_ habit: Habit, now: Date) {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        // Повторяющееся напоминание после выполнения переезжает на следующий срок — перечитываем.
        store.reset()
        let open: [(EKReminder, Date)] = habit.links.compactMap { link in
            guard let reminder = store.calendarItem(withIdentifier: link.reminderID) as? EKReminder,
                  !reminder.isCompleted else { return nil }
            let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantPast
            return due < endOfToday ? (reminder, due) : nil
        }
        guard let reminder = open.min(by: { $0.1 < $1.1 })?.0 else { return }
        do {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        } catch {
            SyncIssues.report("Couldn't complete “\(reminder.title ?? "")” in Reminders: \(error.localizedDescription)")
        }
    }

    private static func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { items in
                if items == nil { SyncIssues.report("Couldn't read reminders from Reminders.", once: true) }
                continuation.resume(returning: items ?? [])
            }
        }
    }
}
#endif

/// Отметка сегодняшнего дня — из виджета, уведомления и приложения.
enum HabitActions {
    /// Кнопка виджета: как нажатие по дню (у «Twice a day» — сделано, дважды, снять).
    static func toggleToday(habitID: UUID, now: Date = Date()) {
        guard let habit = HabitStorage.load().habits.first(where: { $0.id == habitID }) else { return }
        mark(habitID: habitID, state: habit.nextTap(habit.state(HabitDay.today(now))), now: now)
    }

    /// Отметить «выполнено», если сегодня ещё не отмечено.
    static func markToday(habitID: UUID, now: Date = Date()) {
        guard let habit = HabitStorage.load().habits.first(where: { $0.id == habitID }),
              habit.state(HabitDay.today(now)) == .none else { return }
        mark(habitID: habitID, state: .done, now: now)
    }

    /// Поставить сегодня состояние `state`; на каждый новый раз в Reminders отмечается
    /// выполненным одно напоминание.
    static func mark(habitID: UUID, state: HabitDayState, now: Date = Date()) {
        var marked: Habit?
        var added = 0
        HabitStorage.update { db in
            guard let i = db.habits.firstIndex(where: { $0.id == habitID }) else { return }
            let today = HabitDay.today(now)
            let before = db.habits[i].state(today).units
            db.habits[i].setState(state, day: today)
            added = state.units - before
            marked = db.habits[i]
        }
        #if os(iOS)
        if let marked, added > 0 { ReminderSync.completeNext(marked, count: added, now: now) }
        #endif
    }
}
