import SwiftUI
import WidgetKit

/// База привычек для интерфейса приложения: загрузка, сохранение, обновление виджетов.
@MainActor
final class HabitStore: ObservableObject {
    @Published private(set) var db = HabitStorage.load()

    var habits: [Habit] { db.habits }

    func habit(_ id: UUID) -> Habit? { db.habits.first { $0.id == id } }

    /// Перечитать базу (виджет мог отметить день) и подтянуть отметки из Reminders.
    func refresh() async {
        var fresh = HabitStorage.load()
        #if os(iOS)
        await ReminderSync.sync(&fresh)
        #endif
        db = fresh
        persist()
    }

    /// Потянуть вниз в списке: всё заново — база, Reminders, виджеты и уведомления о событиях.
    /// Итог — плашкой сверху: что изменилось в привычках, сколько уведомлений расписано.
    func forceRefresh() async {
        let before = db.habits
        await refresh()
        var parts = [Self.habitChanges(from: before, to: db.habits)]
        #if os(iOS)
        if !ReminderSync.hasAccess && db.habits.contains(where: { !$0.links.isEmpty }) { parts.append("no access to Reminders") }
        if let alerts = await AlertScheduler.sync() { parts.append(alerts == 0 ? "no upcoming event alerts" : alerts == 1 ? "1 event alert scheduled" : "\(alerts) event alerts scheduled") }
        #endif
        WidgetCenter.shared.reloadAllTimelines()
        parts.append("widgets reloaded")
        Toast.show(parts.joined(separator: " · "))
    }

    /// «+2 days, −1 day in 2 habits» — отметки, пришедшие из Reminders и виджетов.
    private static func habitChanges(from old: [Habit], to new: [Habit]) -> String {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0, removed = 0, changed = 0, habits = 0
        for habit in new {
            guard let was = oldByID[habit.id] else { continue }
            let a = habit.completions.subtracting(was.completions).count
            let r = was.completions.subtracting(habit.completions).count
            let c = habit.completions.intersection(was.completions).filter { key in
                HabitDay.date(key).map { habit.state($0) != was.state($0) } ?? false
            }.count
            added += a; removed += r; changed += c
            if a + r + c > 0 { habits += 1 }
        }
        guard habits > 0 else { return "Habits up to date" }
        func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        var items: [String] = []
        if added > 0 { items.append("+" + days(added)) }
        if removed > 0 { items.append("−" + days(removed)) }
        if changed > 0 { items.append(days(changed) + " changed") }
        return "Habits: " + items.joined(separator: ", ") + (habits == 1 ? " in 1 habit" : " in \(habits) habits")
    }

    func add(_ habit: Habit) {
        db.habits.append(habit)
        persist()
    }

    func update(_ habit: Habit) {
        guard let i = db.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        db.habits[i] = habit
        persist()
    }

    /// В корзину и обратно (история не трогается).
    func trash(_ id: UUID) {
        guard var habit = habit(id) else { return }
        habit.trashedAt = Date()
        update(habit)
    }

    func restoreFromTrash(_ id: UUID) {
        guard var habit = habit(id) else { return }
        habit.trashedAt = nil
        update(habit)
    }

    /// Удаление насовсем (из корзины) — перед ним снимок базы в папки бэкапов.
    func delete(_ id: UUID) {
        FilesBackup.snapshot("before-delete")
        FilesBackup.expectBigChange = true
        db.habits.removeAll { $0.id == id }
        persist()
    }

    /// Перестановка в списке активных привычек (архивные остаются на своих местах в конце).
    func moveActive(from source: IndexSet, to destination: Int) {
        var active = db.habits.filter { !$0.archived && !$0.isTrashed }
        active.move(fromOffsets: source, toOffset: destination)
        db.habits = active + db.habits.filter { $0.archived || $0.isTrashed }
        persist()
    }

    /// Поменять состояние дня. До Reminders доходит только отметка сегодняшнего дня: на каждый
    /// новый раз (сделано — один, дважды — ещё один) выполненным отмечается одно напоминание.
    func set(_ id: UUID, day: Date, state: HabitDayState) {
        guard var habit = habit(id) else { return }
        let added = state.units - habit.state(day).units
        habit.setState(state, day: day)
        update(habit)
        if added > 0 && day == HabitDay.today() { ReminderSync.completeNext(habit, count: added) }
    }

    // MARK: Причины несделанных дней

    var reasons: [SkipReason] { db.reasons }

    /// Причина дня (nil — снять). Одна причина несколько дней подряд — уведомление.
    func setReason(_ id: UUID, day: Date, reason: UUID?) {
        guard var habit = habit(id) else { return }
        habit.setReason(reason, day: day)
        update(habit)
        #if os(iOS)
        if reason != nil { SkipPatternAlert.checkAfterSetting(habit, day: day, reasons: db.reasons) }
        #endif
    }

    /// Новая причина в общем списке; пустое название — nil.
    @discardableResult
    func addReason(_ title: String, kind: SkipKind = .other) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let same = db.reasons.first(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) { return same.id }
        let reason = SkipReason(title: trimmed, kind: kind)
        db.reasons.append(reason)
        persist()
        return reason.id
    }

    func updateReason(_ reason: SkipReason) {
        guard let i = db.reasons.firstIndex(where: { $0.id == reason.id }) else { return }
        db.reasons[i] = reason
        persist()
    }

    /// Удалённая причина снимается и со всех дней.
    func deleteReasons(at offsets: IndexSet) {
        let ids = Set(offsets.map { db.reasons[$0].id })
        db.reasons.remove(atOffsets: offsets)
        for i in db.habits.indices { db.habits[i].skipReasons = db.habits[i].skipReasons.filter { !ids.contains($0.value) } }
        persist()
    }

    func moveReasons(from source: IndexSet, to destination: Int) {
        db.reasons.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Импорт из CSV: привычки узнаются по ID или названию, остальные создаются.
    /// Уже отмеченные дни и заметки не перезаписываются. Возвращает (новых привычек, добавленных дней).
    func importCSV(_ imported: [HabitCSV.Imported]) -> (habits: Int, days: Int) {
        var created = 0, days = 0
        for item in imported {
            var index = item.id.flatMap { id in db.habits.firstIndex { $0.id == id } }
                ?? db.habits.firstIndex { !$0.isTrashed && $0.title.caseInsensitiveCompare(item.name) == .orderedSame }
            if index == nil {
                var habit = Habit(name: item.name)
                if let id = item.id { habit.id = id }
                habit.createdAt = item.states.keys.compactMap(HabitDay.date).min() ?? Date()
                db.habits.append(habit)
                index = db.habits.count - 1
                created += 1
            }
            let i = index!
            for (key, state) in item.states where !db.habits[i].completions.contains(key) {
                guard let day = HabitDay.date(key) else { continue }
                if state == .twice { db.habits[i].twiceADay = true }
                db.habits[i].setState(state, day: day)
                days += 1
            }
            for (key, note) in item.notes where db.habits[i].notes[key] == nil { db.habits[i].notes[key] = note }
        }
        persist()
        return (created, days)
    }

    /// Восстановление всей базы из бэкапа (текущая уходит в habits-previous.json).
    func restore(_ restored: HabitDB) {
        FilesBackup.snapshot("before-restore")
        FilesBackup.expectBigChange = true
        db = restored
        persist()
    }

    /// Привычки, к которым привязано каждое напоминание (кроме привычки `except`).
    func reminderUsers(except id: UUID?) -> [String: [Habit]] {
        var users: [String: [Habit]] = [:]
        for habit in db.habits where habit.id != id && !habit.isTrashed {
            for link in habit.links { users[link.reminderID, default: []].append(habit) }
        }
        return users
    }

    /// Слияние: всё из привычки `secondID` переходит в `firstID`, вторая удаляется. Перед этим —
    /// снимок базы. Название — от первой. День, отмеченный в обеих, получает более сильную
    /// отметку (дважды > перевыполнено > сделано > недоделано). Настройка, изменённая только
    /// в одной привычке, берётся оттуда; изменённая в обеих — от первой.
    func merge(_ firstID: UUID, with secondID: UUID) {
        guard firstID != secondID, let a = habit(firstID), let b = habit(secondID) else { return }
        FilesBackup.snapshot("before-merge")
        FilesBackup.expectBigChange = true

        let base = Habit(name: "")
        func pick<T: Equatable>(_ key: WritableKeyPath<Habit, T>) -> T { a[keyPath: key] != base[keyPath: key] ? a[keyPath: key] : b[keyPath: key] }
        var m = a
        m.name = a.title
        m.colorHex = pick(\.colorHex)
        m.harmful = pick(\.harmful)
        m.twiceADay = pick(\.twiceADay)
        m.weeklyGoal = pick(\.weeklyGoal)
        m.showsNote = pick(\.showsNote)
        m.habitNote = pick(\.habitNote)
        m.partialIconHex = pick(\.partialIconHex)
        m.overIconHex = pick(\.overIconHex)
        m.twiceIconHex = pick(\.twiceIconHex)
        m.noteIconHex = pick(\.noteIconHex)
        m.missedHex = pick(\.missedHex)
        m.highlightMissed = pick(\.highlightMissed)
        m.allowedSkips = pick(\.allowedSkips)
        m.createdAt = min(a.createdAt, b.createdAt)
        m.links = a.links + b.links.filter { link in !a.links.contains { $0.reminderID == link.reminderID } }

        // Отметка дня по сырым данным (без учёта «Twice a day» у привычки).
        func rank(_ h: Habit, _ key: String) -> Int {
            guard h.completions.contains(key) else { return 0 }
            if h.twiceDays.contains(key) { return 5 }
            if h.overDays.contains(key) { return 4 }
            if h.partialDays.contains(key) { return 2 }
            return 3
        }
        m.completions = a.completions.union(b.completions)
        m.partialDays = []; m.overDays = []; m.twiceDays = []
        for key in m.completions {
            switch max(rank(a, key), rank(b, key)) {
            case 5: m.twiceDays.insert(key)
            case 4: m.overDays.insert(key)
            case 2: m.partialDays.insert(key)
            default: break
            }
        }
        m.removedDays = a.removedDays.union(b.removedDays).subtracting(m.completions)
        m.skipReasons = b.skipReasons.merging(a.skipReasons) { own, _ in own }
        for (key, note) in b.notes {
            if let own = m.notes[key], own != note { m.notes[key] = own + " / " + note } else { m.notes[key] = note }
        }

        guard let i = db.habits.firstIndex(where: { $0.id == firstID }) else { return }
        db.habits[i] = m
        db.habits.removeAll { $0.id == secondID }
        persist()
    }

    private func persist() {
        HabitStorage.save(db)
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitGoalWidget")
        FilesBackup.write()
    }
}

extension Color {
    /// «#RRGGBBAA» для хранения.
    var hexString: String {
        let c = resolve(in: EnvironmentValues())
        func byte(_ v: Float) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue), byte(c.opacity))
    }
}
