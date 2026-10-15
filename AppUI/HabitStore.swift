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

    func move(from source: IndexSet, to destination: Int) {
        db.habits.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Поменять состояние дня. До Reminders доходит только отметка сегодняшнего дня
    /// выполненным (в любом виде) — тогда напоминание тоже отмечается выполненным.
    func set(_ id: UUID, day: Date, state: HabitDayState) {
        guard var habit = habit(id) else { return }
        habit.setState(state, day: day)
        update(habit)
        #if os(iOS)
        if state != .none && day == HabitDay.today() { ReminderSync.completeToday(habit) }
        #endif
    }

    private func persist() {
        HabitStorage.save(db)
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
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
