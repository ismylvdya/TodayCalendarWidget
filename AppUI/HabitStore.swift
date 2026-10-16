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
    func forceRefresh() async {
        await refresh()
        #if os(iOS)
        await AlertScheduler.sync()
        #endif
        WidgetCenter.shared.reloadAllTimelines()
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

    func delete(_ id: UUID) {
        db.habits.removeAll { $0.id == id }
        persist()
    }

    /// Перестановка в списке активных привычек (архивные остаются на своих местах в конце).
    func moveActive(from source: IndexSet, to destination: Int) {
        var active = db.habits.filter { !$0.archived }
        active.move(fromOffsets: source, toOffset: destination)
        db.habits = active + db.habits.filter(\.archived)
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
