import Foundation
#if os(iOS)
import UserNotifications
#endif

/// Почему день не сделан. Виды — из Tiny Habits (BJ Fogg): поведение = мотивация + способность +
/// подсказка; если привычка не случается, ищут, чего не хватило, — подсказки, способности или
/// мотивации, и меняют саму привычку, а не винят себя. «Уважительная» — болезнь, поездка:
/// не повод что-то менять.
enum SkipKind: String, Codable, CaseIterable, Identifiable {
    case prompt, ability, motivation, excused, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .prompt: "Prompt — forgot, no cue"
        case .ability: "Ability — too hard, no time"
        case .motivation: "Motivation — didn't want to"
        case .excused: "Excused — sick, travel"
        case .other: "Other"
        }
    }

    /// Совет в уведомлении о повторяющейся причине.
    var tip: String {
        switch self {
        case .prompt: "The habit has no reliable cue. Tie it to something you already do every day: “After I …, I will …”."
        case .ability: "The habit is too hard right now. Shrink it to a two-minute version or move it to an easier time."
        case .motivation: "Make it more attractive — pair it with something you enjoy — or ask whether this habit still matters to you."
        case .excused, .other: "The same thing keeps getting in the way — change the habit's time, size or cue instead of pushing harder."
        }
    }
}

struct SkipReason: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var kind: SkipKind = .other

    /// Начальный список. ID постоянные: дни ссылаются на причину по ID.
    static let defaults: [SkipReason] = [
        SkipReason(id: UUID(uuidString: "5D1C0001-0000-4000-8000-000000000001")!, title: "Forgot", kind: .prompt),
        SkipReason(id: UUID(uuidString: "5D1C0001-0000-4000-8000-000000000002")!, title: "No time", kind: .ability),
        SkipReason(id: UUID(uuidString: "5D1C0001-0000-4000-8000-000000000003")!, title: "Too tired", kind: .ability),
        SkipReason(id: UUID(uuidString: "5D1C0001-0000-4000-8000-000000000004")!, title: "Didn't feel like it", kind: .motivation),
        SkipReason(id: UUID(uuidString: "5D1C0001-0000-4000-8000-000000000005")!, title: "Sick", kind: .excused),
        SkipReason(id: UUID(uuidString: "5D1C0001-0000-4000-8000-000000000006")!, title: "Traveling", kind: .excused),
    ]

    init(id: UUID = UUID(), title: String, kind: SkipKind = .other) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = (try? c.decodeIfPresent(SkipKind.self, forKey: .kind)) ?? .other
    }
}

extension HabitDB {
    /// Общий для всех привычек список причин (пока не меняли — начальный).
    var reasons: [SkipReason] {
        get { skipReasonPool ?? SkipReason.defaults }
        set { skipReasonPool = newValue }
    }
}

extension Habit {
    func reason(_ day: Date) -> UUID? { skipReasons[HabitDay.key(day)] }

    mutating func setReason(_ reason: UUID?, day: Date) { skipReasons[HabitDay.key(day)] = reason }

    /// Несделанный прошедший день хорошей привычки без причины — на нём значок вопроса.
    /// Не спрашиваем о днях до появления причин в приложении, до создания привычки
    /// и о неделях, где цель на неделю уже выполнена.
    func needsReason(_ day: Date, today: Date = HabitDay.today()) -> Bool {
        guard HabitSettings.askWhyNotDone, !harmful, day < today, state(day) == .none, reason(day) == nil,
              day >= HabitSettings.reasonsSince, day >= Calendar.current.startOfDay(for: createdAt) else { return false }
        return weeklyGoal == 0 || doneInWeek(of: day) < weeklyGoal
    }

    /// Сколько несделанных дней подряд, заканчивая `day`, — с одной и той же причиной.
    func reasonStreak(endingAt day: Date) -> Int {
        guard let reason = reason(day) else { return 0 }
        var count = 0, d = day
        while state(d) == .none, self.reason(d) == reason {
            count += 1
            d = Calendar.current.date(byAdding: .day, value: -1, to: d)!
        }
        return count
    }
}

#if os(iOS)
/// Уведомление: одна причина несколько дней подряд — пора менять привычку, а не себя.
enum SkipPatternAlert {
    /// Уведомление на серию шлём один раз: помним её первый день.
    private static func sentKey(_ habit: Habit, _ reason: UUID) -> String { "skipAlert|\(habit.id)|\(reason)" }

    static func checkAfterSetting(_ habit: Habit, day: Date, reasons: [SkipReason]) {
        let need = HabitSettings.reasonAlertDays
        guard need > 0, let id = habit.reason(day), let reason = reasons.first(where: { $0.id == id }),
              reason.kind != .excused else { return }
        let streak = habit.reasonStreak(endingAt: day)
        guard streak >= need else { return }
        // Первый день серии — конец серии может сдвигаться, начало у неё одно.
        let start = HabitDay.key(Calendar.current.date(byAdding: .day, value: -(streak - 1), to: day)!)
        let key = sentKey(habit, id)
        guard AppGroup.defaults.string(forKey: key) != start else { return }
        AppGroup.defaults.set(start, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "\(habit.title): “\(reason.title)” \(streak) days in a row"
        content.body = reason.kind.tip
        content.sound = .default
        content.userInfo = ["habitID": habit.id.uuidString]
        let request = UNNotificationRequest(identifier: "skip|\(habit.id)|\(start)", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}
#endif
