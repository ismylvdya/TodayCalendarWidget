import Foundation

/// Почему день не сделан. Виды — из Tiny Habits (BJ Fogg): поведение = мотивация + способность +
/// подсказка; если привычка не случается, ищут, чего не хватило, — подсказки, способности или
/// мотивации, и меняют саму привычку, а не винят себя. «Уважительная» — болезнь, поездка:
/// не повод что-то менять.
enum SkipKind: String, Codable, CaseIterable, Identifiable {
    case prompt, ability, motivation, excused, other
    var id: String { rawValue }

    /// Короткое название — в строке причины в настройках.
    var shortTitle: String {
        switch self {
        case .prompt: "Prompt"
        case .ability: "Ability"
        case .motivation: "Motivation"
        case .excused: "Excused"
        case .other: "Other"
        }
    }

    var title: String {
        switch self {
        case .prompt: "Prompt — forgot, no cue"
        case .ability: "Ability — too hard, no time"
        case .motivation: "Motivation — didn't want to"
        case .excused: "Excused — sick, travel"
        case .other: "Other"
        }
    }

    /// Что не так — первая строка плашки долгого пропуска (что поменять — в `ways`).
    var diagnosis: String {
        switch self {
        case .prompt: "Nothing reminds you at the right moment: the habit has no reliable cue."
        case .ability: "The habit is too hard or too long for you right now."
        case .motivation: "Right now you don't want it enough."
        case .excused, .other: "The same thing keeps getting in the way."
        }
    }
}

extension SkipKind {
    /// Что можно поменять — список на плашке долгого пропуска.
    var ways: [String] {
        switch self {
        case .prompt: [
            "Anchor it to a daily routine: “After I …, I will …”.",
            "Leave a visible cue where you'll see it at the right moment.",
            "Set a reminder for the moment you usually do it.",
        ]
        case .ability: [
            "Shrink it to a two-minute version and grow it later.",
            "Move it to a time when you have more energy.",
            "Prepare everything in advance to remove the first obstacle.",
        ]
        case .motivation: [
            "Pair it with something you enjoy.",
            "Make the first step tiny and celebrate right after it.",
            "Ask whether this habit still matters — archive it if not.",
        ]
        case .excused, .other: [
            "Change the habit's time, size or cue.",
            "Look at what these days had in common and remove that obstacle.",
        ]
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

    /// Первый отмеченный день («yyyy-MM-dd» сортируются как даты).
    var firstMarkedDay: Date? { completions.min().flatMap(HabitDay.date) }

    /// Несделанный прошедший день (не сегодня) без причины после первой отметки — на нём
    /// знак вопроса. Только если у привычки включено «Why Not Done» и она не вредная.
    func needsReason(_ day: Date, today: Date = HabitDay.today(), firstMarked: Date? = nil) -> Bool {
        guard asksWhyNotDone, !harmful, day < today, state(day) == .none, reason(day) == nil,
              let first = firstMarked ?? firstMarkedDay else { return false }
        return day > first
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

/// Долгий пропуск: последние несделанные дни подряд — с одной неуважительной причиной.
/// Привычка помечается восклицательным знаком, на её странице — плашка с советом.
struct LongGap: Equatable {
    let reason: SkipReason
    let days: Int
    /// Первый день серии: по нему помним, что плашку закрыли.
    let start: String
}

extension Habit {
    /// Долгий пропуск, если он идёт сейчас: после него привычку ни разу не сделали.
    /// Дни без причины в конце (например, сегодня ещё не подписано) серию не прерывают.
    func longGap(reasons: [SkipReason], today: Date = HabitDay.today()) -> LongGap? {
        let need = HabitSettings.reasonAlertDays
        guard asksWhyNotDone, need > 0 else { return nil }
        let cal = Calendar.current
        var day = today
        for _ in 0..<370 {
            guard state(day) == .none else { return nil }
            if let id = reason(day) {
                guard let reason = reasons.first(where: { $0.id == id }), reason.kind != .excused else { return nil }
                let streak = reasonStreak(endingAt: day)
                guard streak >= need else { return nil }
                let start = HabitDay.key(cal.date(byAdding: .day, value: -(streak - 1), to: day)!)
                guard AppGroup.defaults.string(forKey: LongGap.dismissedKey(self.id)) != start else { return nil }
                return LongGap(reason: reason, days: streak, start: start)
            }
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return nil
    }
}

extension LongGap {
    static func dismissedKey(_ habitID: UUID) -> String { "longGapDismissed|\(habitID)" }
}
