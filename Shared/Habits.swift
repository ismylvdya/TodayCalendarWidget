import Foundation
import SwiftUI

// MARK: - Модель

/// Состояние дня в истории привычки.
enum HabitDayState: String, CaseIterable, Identifiable {
    case none, partial, done, over, twice
    var id: String { rawValue }
    /// Сколько раз сделано: дважды — 2, любая другая отметка — 1.
    var units: Int { self == .none ? 0 : self == .twice ? 2 : 1 }
    var title: String {
        switch self {
        case .none: "Not Done"
        case .partial: "Partially Done"
        case .done: "Done"
        case .over: "Overdone"
        case .twice: "Twice a Day"
        }
    }
}

/// Привычка — со своим постоянным ID. Напоминания из Reminders к ней только привязываются:
/// старое удалили, новое привязали — история продолжается под тем же ID.
struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Своё название; пусто — берётся название привязанного напоминания.
    var name: String
    var colorHex = "#3478F6FF"
    /// Привязанные напоминания (текущее и прежние). Пусто — привычка отмечается только вручную.
    var links: [ReminderLink] = []
    /// Дни выполнения, «yyyy-MM-dd» (включая недоделанные и перевыполненные).
    var completions: Set<String> = []
    /// Из выполненных — недоделанные и перевыполненные.
    var partialDays: Set<String> = []
    var overDays: Set<String> = []
    /// Из выполненных — сделанные дважды (только у привычек «Twice a day»).
    var twiceDays: Set<String> = []
    /// Дни, снятые вручную: синхронизация с Reminders их больше не добавляет.
    var removedDays: Set<String> = []
    /// Цвета иконок недоделанного и перевыполненного дня; nil — по умолчанию
    /// (недоделано — цвет выполненного дня, перевыполнено — цвет невыполненного).
    var partialIconHex: String?
    var overIconHex: String?
    /// Свой цвет значка заметки; nil — по умолчанию.
    var noteIconHex: String?
    /// Цель: сколько раз в неделю (0 — без цели).
    var weeklyGoal = 0
    /// Заметки к дням.
    var notes: [String: String] = [:]
    /// Причины несделанных дней: день → ID причины из общего списка (`HabitDB.reasons`).
    var skipReasons: [String: UUID] = [:]
    /// Заметка к самой привычке и показывать ли её поле (текст сохраняется и при скрытом поле).
    var habitNote = ""
    var showsNote = true
    /// Вредная привычка: серии считаются по дням, когда её НЕ было.
    var harmful = false
    /// Делается дважды в день: нажатие по сделанному один раз дню ставит «дважды».
    var twiceADay = false
    /// Свой цвет отметки «дважды»; nil — по умолчанию.
    var twiceIconHex: String?
    /// Подсвечивать пропуски: несделанные дни подряд сверх `allowedSkips` (цвет — общий).
    var highlightMissed = false
    var allowedSkips = 1
    /// Свой цвет пропусков; nil — общий.
    var missedHex: String?
    /// В архиве: нет в списке и виджетах, история сохраняется.
    var archived = false
    /// В корзине (с какого момента): нет ни в списке, ни в архиве, ни в виджетах; оттуда — вернуть
    /// или удалить насовсем.
    var trashedAt: Date?
    var isTrashed: Bool { trashedAt != nil }
    var createdAt = Date()

    init(name: String, colorHex: String = "#3478F6FF") {
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) ?? .blue }

    /// sRGB-компоненты цвета привычки.
    var rgb: [Double] {
        var s = colorHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt64(s.prefix(6), radix: 16) else { return [0.2, 0.47, 0.96] }
        return [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255]
    }

    /// Название для показа.
    var title: String {
        let custom = name.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? (links.last?.titles.last ?? "Habit") : custom
    }

    func isDone(_ day: Date) -> Bool { completions.contains(HabitDay.key(day)) }

    func note(_ day: Date) -> String? { notes[HabitDay.key(day)] }

    mutating func setNote(_ text: String, day: Date) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[HabitDay.key(day)] = trimmed.isEmpty ? nil : trimmed
    }

    /// Сколько дней отмечено на неделе, в которую входит `day`.
    func doneInWeek(of day: Date) -> Int {
        // У «Twice a day» цель — в разах: день «дважды» даёт 2.
        HabitGrid.weeks(count: 1, endingAt: day).first?.compactMap { $0 }.reduce(0) { $0 + units($1) } ?? 0
    }

    func state(_ day: Date) -> HabitDayState {
        let key = HabitDay.key(day)
        guard completions.contains(key) else { return .none }
        // Привычку переключили с «Twice a day» на обычную — такие дни просто сделанные.
        if twiceADay && twiceDays.contains(key) { return .twice }
        if overDays.contains(key) { return .over }
        if partialDays.contains(key) { return .partial }
        return .done
    }

    /// Отметить или снять день вручную.
    mutating func set(_ day: Date, done: Bool) {
        setState(done ? .done : .none, day: day)
    }

    mutating func setState(_ state: HabitDayState, day: Date) {
        let key = HabitDay.key(day)
        partialDays.remove(key)
        overDays.remove(key)
        twiceDays.remove(key)
        if state == .none {
            completions.remove(key)
            removedDays.insert(key)
            return
        }
        completions.insert(key)
        removedDays.remove(key)
        if state == .partial { partialDays.insert(key) }
        if state == .over { overDays.insert(key) }
        if state == .twice { twiceDays.insert(key) }
    }

    /// Состояние после нажатия по дню (в сетке, виджете, чекбоксе). У привычки «Twice a day»:
    /// не сделано → сделано → дважды (в т.ч. из недоделано/перевыполнено) → не сделано.
    func nextTap(_ state: HabitDayState) -> HabitDayState {
        guard twiceADay else { return state == .none ? .done : .none }
        switch state {
        case .none: return .done
        case .twice: return .none
        default: return .twice
        }
    }

    /// Сегодня сделано полностью (у «Twice a day» — дважды): кнопка виджета снимает отметку.
    func isComplete(_ day: Date) -> Bool {
        twiceADay ? state(day) == .twice : state(day) != .none
    }

    /// Пропуски сверх допустимого: несделанные дни подряд (от первой отметки до вчера), если их
    /// больше `allowedSkips`, — подсвечиваются все дни такой серии. У вредной привычки не считаются.
    func missedDays(today: Date = HabitDay.today()) -> Set<String> {
        guard highlightMissed, !harmful,
              let first = completions.compactMap(HabitDay.date).min() else { return [] }
        let cal = Calendar.current
        var missed: Set<String> = [], run: [String] = []
        var day = first
        while day < today {
            let key = HabitDay.key(day)
            if completions.contains(key) {
                if run.count > allowedSkips { missed.formUnion(run) }
                run = []
            } else {
                run.append(key)
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        if run.count > allowedSkips { missed.formUnion(run) }
        return missed
    }

    /// Сколько раз сделано за день (у «Twice a day» дважды — 2).
    func units(_ day: Date) -> Int { twiceADay ? state(day).units : (isDone(day) ? 1 : 0) }

    // Старые файлы базы без новых полей тоже читаются.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#3478F6FF"
        links = try c.decodeIfPresent([ReminderLink].self, forKey: .links) ?? []
        completions = try c.decodeIfPresent(Set<String>.self, forKey: .completions) ?? []
        partialDays = try c.decodeIfPresent(Set<String>.self, forKey: .partialDays) ?? []
        overDays = try c.decodeIfPresent(Set<String>.self, forKey: .overDays) ?? []
        twiceDays = try c.decodeIfPresent(Set<String>.self, forKey: .twiceDays) ?? []
        removedDays = try c.decodeIfPresent(Set<String>.self, forKey: .removedDays) ?? []
        partialIconHex = try c.decodeIfPresent(String.self, forKey: .partialIconHex)
        overIconHex = try c.decodeIfPresent(String.self, forKey: .overIconHex)
        noteIconHex = try c.decodeIfPresent(String.self, forKey: .noteIconHex)
        weeklyGoal = try c.decodeIfPresent(Int.self, forKey: .weeklyGoal) ?? 0
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        skipReasons = try c.decodeIfPresent([String: UUID].self, forKey: .skipReasons) ?? [:]
        habitNote = try c.decodeIfPresent(String.self, forKey: .habitNote) ?? ""
        showsNote = try c.decodeIfPresent(Bool.self, forKey: .showsNote) ?? true
        harmful = try c.decodeIfPresent(Bool.self, forKey: .harmful) ?? false
        twiceADay = try c.decodeIfPresent(Bool.self, forKey: .twiceADay) ?? false
        twiceIconHex = try c.decodeIfPresent(String.self, forKey: .twiceIconHex)
        highlightMissed = try c.decodeIfPresent(Bool.self, forKey: .highlightMissed) ?? false
        allowedSkips = try c.decodeIfPresent(Int.self, forKey: .allowedSkips) ?? 1
        missedHex = try c.decodeIfPresent(String.self, forKey: .missedHex)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        trashedAt = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Привязка к напоминанию. Названия запоминаются все, какие были: выполненные копии
/// повторяющегося напоминания узнаются по названию в том же списке.
struct ReminderLink: Codable, Hashable {
    var reminderID: String
    var listID: String
    var titles: [String]
    /// Последний известный срок повторяющегося напоминания («yyyy-MM-dd»): если срок
    /// сдвинулся вперёд — напоминание выполнили (iOS 26 не оставляет выполненных копий).
    var lastDue: String?
}

struct HabitDB: Codable {
    var habits: [Habit] = []
    var lastReminderSync: Date?
    /// Свой список причин несделанных дней; nil — начальный (`reasons`).
    var skipReasonPool: [SkipReason]?
}

enum HabitDay {
    /// «Сегодня» для привычек: до часа отсечки ночью ещё идёт вчерашний день.
    static func today(_ now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(HabitSettings.dayCutoffHour) * 3600))
    }

    /// День, которому засчитывается отметка, сделанная в момент `moment`.
    static func dayKey(forMoment moment: Date) -> String { key(today(moment)) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String {
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func date(_ key: String) -> Date? {
        formatter.timeZone = .current
        return formatter.date(from: key)
    }
}

// MARK: - Хранение

/// База привычек — JSON-файл в общей папке приложения и виджета.
enum HabitStorage {
    private static var url: URL { AppGroup.containerURL.appendingPathComponent("habits.json") }

    /// Загружает базу; при первом запуске создаёт тестовую привычку.
    static func load() -> HabitDB {
        if let data = try? Data(contentsOf: url) {
            if let db = try? JSONDecoder().decode(HabitDB.self, from: data) { return db }
            // База есть, но не читается: не затираем её новой — откладываем копию и сообщаем.
            let copy = url.deletingLastPathComponent().appendingPathComponent("habits-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: copy)
            SyncIssues.report("The habit database could not be read. A copy was saved as \(copy.lastPathComponent).")
        }
        let db = HabitDB(habits: [TestHabit.make()])
        save(db)
        return db
    }

    static func save(_ db: HabitDB) {
        do {
            try JSONEncoder().encode(db).write(to: url, options: .atomic)
        } catch {
            SyncIssues.report("Habits could not be saved: \(error.localizedDescription)")
        }
    }

    static func update(_ change: (inout HabitDB) -> Void) {
        var db = load()
        change(&db)
        save(db)
    }
}

/// Тестовая привычка: случайные отметки за последний месяц (одинаковые при каждом создании).
enum TestHabit {
    static func make(now: Date = Date()) -> Habit {
        var habit = Habit(name: "Test habit", colorHex: "#3478F6FF")
        var rng = SeededRandom(seed: 42)
        let cal = Calendar.current
        for offset in 1...30 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            if rng.next() % 100 < 45 { habit.completions.insert(HabitDay.key(day)) }
        }
        habit.createdAt = cal.date(byAdding: .day, value: -30, to: now) ?? now
        return habit
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}

// MARK: - CSV

enum HabitCSV {
    /// «habit_id,habit_name,date,status,note» — по строке на каждый отмеченный день или день
    /// с заметкой; status: done, partial, over, twice или none (только заметка).
    static func make(_ habits: [Habit]) -> String {
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["habit_id,habit_name,date,status,note"]
        for habit in habits {
            for day in habit.completions.union(habit.notes.keys).sorted() {
                let status = !habit.completions.contains(day) ? "none"
                    : habit.twiceDays.contains(day) ? "twice"
                    : habit.overDays.contains(day) ? "over" : habit.partialDays.contains(day) ? "partial" : "done"
                rows.append("\(habit.id.uuidString),\(quoted(habit.title)),\(day),\(status),\(quoted(habit.notes[day] ?? ""))")
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func file(_ habits: [Habit], name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? make(habits).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Импорт

    /// Привычка из чужого (или своего) CSV.
    struct Imported {
        var id: UUID?
        var name: String
        var states: [String: HabitDayState] = [:]
        var notes: [String: String] = [:]
    }

    /// Понимает форматы:
    /// - свой (`habit_id,habit_name,date,status,note`);
    /// - Loop Habit Tracker: общий `Checkmarks.csv` (`Date,Привычка1,Привычка2,…`, значения
    ///   YES_MANUAL / YES_AUTO / NO / SKIP / UNKNOWN или числа) и файл одной привычки
    ///   (`Date,Value,Notes` — название берётся из имени папки или файла);
    /// - любой «длинный» CSV: столбец даты и столбец названия привычки, необязательно — статус и заметка.
    static func parse(_ text: String, fileName: String) -> [Imported] {
        let rows = csvRows(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }), rows.count > 1 else { return [] }
        let body = rows.dropFirst()
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        func cell(_ row: [String], _ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil } ?? "" }

        guard let dateCol = column(["date", "day", "entry_date", "completed_date", "datetime"]) else { return [] }
        let nameCol = column(["habit_name", "habit", "name", "task", "title", "habit name"])
        let idCol = column(["habit_id"])
        let statusCol = column(["status", "value", "state", "completed", "result", "count", "quantity"])
        let noteCol = column(["note", "notes", "comment"])

        var result: [String: Imported] = [:]
        var order: [String] = []
        func add(_ name: String, id: UUID?, date: String, status: String, note: String) {
            guard let key = dayKey(date) else { return }
            let tag = id?.uuidString ?? name.lowercased()
            if result[tag] == nil { result[tag] = Imported(id: id, name: name); order.append(tag) }
            if let state = state(status, defaultDone: statusCol == nil) { result[tag]!.states[key] = state }
            if !note.isEmpty { result[tag]!.notes[key] = note }
        }

        if let nameCol {
            // Длинный формат: строка — день одной привычки.
            for row in body {
                add(cell(row, nameCol), id: UUID(uuidString: cell(row, idCol)), date: cell(row, dateCol),
                    status: cell(row, statusCol), note: cell(row, noteCol))
            }
        } else if header.count <= 3, statusCol != nil {
            // Loop: файл одной привычки (Date,Value,Notes).
            let name = habitName(fromFile: fileName)
            for row in body { add(name, id: nil, date: cell(row, dateCol), status: cell(row, statusCol), note: cell(row, noteCol)) }
        } else {
            // Loop: Checkmarks.csv — столбец на привычку.
            let names = rows.first!
            for row in body {
                for i in names.indices where i != dateCol && !names[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    add(names[i].trimmingCharacters(in: .whitespaces), id: nil, date: cell(row, dateCol), status: cell(row, i), note: "")
                }
            }
        }
        return order.compactMap { result[$0] }.filter { !$0.name.isEmpty || $0.id != nil }
    }

    /// Статус дня из чужих обозначений; nil — день не отмечен.
    private static func state(_ raw: String, defaultDone: Bool) -> HabitDayState? {
        let s = raw.lowercased()
        if s.isEmpty { return defaultDone ? .done : nil }
        switch s {
        case "done", "yes", "y", "true", "x", "✓", "completed", "complete", "yes_manual", "checked": return .done
        case "partial", "partially", "partially done": return .partial
        case "over", "overdone": return .over
        case "twice": return .twice
        // YES_AUTO у Loop — день засчитан частотой, а не отмечен.
        case "no", "n", "false", "none", "yes_auto", "skip", "unknown", "-", "missed", "failed": return nil
        default:
            if let number = Double(s.replacingOccurrences(of: ",", with: ".")) { return number > 0 ? .done : nil }
            return nil
        }
    }

    /// «yyyy-MM-dd» из распространённых форматов дат (время отбрасывается).
    private static func dayKey(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "dd.MM.yyyy", "MM/dd/yyyy", "dd/MM/yyyy", "yyyyMMdd"]
        let candidates = [String(s.prefix(10)), String(s.prefix(8)), s]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            f.dateFormat = format
            for c in candidates { if let d = f.date(from: c) { return HabitDay.key(d) } }
        }
        return nil
    }

    /// «001 Meditate/Checkmarks.csv» → «Meditate».
    private static func habitName(fromFile path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        var name = parts.count > 1 ? parts[parts.count - 2] : (parts.last ?? "Imported")
        if name.lowercased().hasSuffix(".csv") { name = String(name.dropLast(4)) }
        if let range = name.range(of: #"^\d+\s+"#, options: .regularExpression) { name.removeSubrange(range) }
        return name.isEmpty || name.lowercased() == "checkmarks" ? "Imported habit" : name
    }

    /// Строки CSV с учётом кавычек и переносов внутри них; разделитель — запятая или точка с запятой.
    private static func csvRows(_ text: String) -> [[String]] {
        let firstLine = text.prefix { $0 != "\n" }
        let separator: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" {
                quoted = true
            } else if c == separator {
                row.append(field); field = ""
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

// MARK: - Сетка по неделям

enum HabitGrid {
    /// Начало недели, в которую входит `date`, по настройкам системы.
    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Недели (старые сверху), каждая — 7 дней; дни после `today` равны nil.
    static func weeks(count: Int, endingAt today: Date, calendar: Calendar = .current) -> [[Date?]] {
        let last = weekStart(today, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        return (0..<count).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: last)!
            return (0..<7).map { i in
                let day = calendar.date(byAdding: .day, value: i, to: start)!
                return day > todayStart ? nil : day
            }
        }
    }

    /// Буквы дней недели в порядке системы (M T W …).
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

/// Ошибки синхронизации, сохранения и удаления. Приложение показывает их алертом;
/// в виджете сообщать некому — там они пропускаются.
enum SyncIssues {
    static var handler: (String) -> Void = { _ in }
    /// Уже показанные (за запуск): одна и та же проблема не всплывает при каждой синхронизации.
    private static var shown: Set<String> = []

    static func report(_ message: String, once: Bool = false) {
        if once { guard shown.insert(message).inserted else { return } }
        handler(message)
    }
}
