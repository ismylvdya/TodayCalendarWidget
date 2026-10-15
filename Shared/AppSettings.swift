import Foundation
import SwiftUI

/// Название приложения в интерфейсе и текстах.
#if os(iOS)
let appName = "Calendar Enhancer & Reminders Habiter"
#else
let appName = "Calendar Widget"
#endif

/// Общее хранилище приложения и виджета.
/// На iOS это App Group: AltStore при установке переименовывает группу и записывает
/// настоящее имя в Info.plist (`ALTAppGroups`). На macOS (тестовый режим) у приложения
/// и виджета хранилища раздельные.
enum AppGroup {
    static let defaultID = "group.com.chumbulev.TripleToday"

    static var id: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? defaultID
    }

    static var defaults: UserDefaults {
        #if os(iOS)
        UserDefaults(suiteName: id) ?? .standard
        #else
        .standard
        #endif
    }

    /// Папка для базы привычек. Если общая папка недоступна — своя папка процесса.
    static var containerURL: URL {
        #if os(iOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        #endif
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Настройки календарной части, которые меняются в приложении.
enum CalendarSettings {
    enum Key {
        static let alertsEnabled = "alertsEnabled"
        static let keepAfterTap = "keepNotificationAfterTap"
        static let removeWhenMovedLater = "removeNotificationWhenMovedLater"
        static let removeWhenDeleted = "removeNotificationWhenDeleted"
        static let staleLabelMinutes = "staleLabelMinutes"
        static let cursorHex = "cursorHex"
        static let notificationTapOpensEvent = "notificationTapOpensEvent"
        static let defaultDayStart = "defaultDayStart"
        static let defaultDayEnd = "defaultDayEnd"
        static let prefix = "calendarNotificationPrefix"
        static let separator = "calendarNotificationSeparator"
    }

    static var prefix: String { d.string(forKey: Key.prefix) ?? "" }
    static var separator: String { d.string(forKey: Key.separator) ?? NotificationTitle.defaultSeparator }

    static let defaultCursorHex = "#E9534CFF"

    private static var d: UserDefaults { AppGroup.defaults }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }
    private static func int(_ key: String, _ fallback: Int) -> Int {
        d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
    }

    /// Свои уведомления для событий с alert.
    static var alertsEnabled: Bool { bool(Key.alertsEnabled, true) }
    /// На сколько дней вперёд расписывать уведомления.
    static let alertDaysAhead = 10
    /// После нажатия класть уведомление обратно в список.
    static var keepAfterTap: Bool { bool(Key.keepAfterTap, true) }
    static var removeWhenMovedLater: Bool { bool(Key.removeWhenMovedLater, true) }
    static var removeWhenDeleted: Bool { bool(Key.removeWhenDeleted, false) }
    /// С какой давности данных показывать подпись «N min ago».
    static var staleLabelMinutes: Int { max(1, int(Key.staleLabelMinutes, 30)) }
    static var cursorColor: Color { Color(hex: d.string(forKey: Key.cursorHex) ?? defaultCursorHex) ?? .red }
    /// Нажатие на уведомление открывает карточку события в приложении (иначе — Calendar).
    static var notificationTapOpensEvent: Bool { bool(Key.notificationTapOpensEvent, false) }
    /// Интервал дня для календарных виджетов, у которых в настройках стоит «Default».
    static var defaultDayStart: Int { int(Key.defaultDayStart, 6) }
    static var defaultDayEnd: Int { int(Key.defaultDayEnd, 24) }
}

/// Общие настройки привычек (сетки, виджетов, отметок).
enum HabitSettings {
    enum Key {
        static let dayCutoffHour = "habitDayCutoffHour"
        static let widgetWeeks = "habitWidgetWeeks"
        static let buttonSize = "habitButtonSize"
        static let buttonInset = "habitButtonInset"
        static let gridInset = "habitGridInset"
        static let titleSize = "habitTitleSize"
        static let undoneOpacity = "habitUndoneOpacity"
        static let partialPattern = "habitPartialPatternV2"
        static let stripeWidth = "habitStripeWidthV2"
        static let doneStripeOpacity = "habitDoneStripeOpacity"
        static let undoneStripeOpacity = "habitUndoneStripeOpacity"
        static let partialSymbol = "habitPartialSymbol"
        static let overSymbol = "habitOverSymbol"
        static let partialIconScale = "habitPartialIconScale"
        static let overIconScale = "habitOverIconScale"
        static let overIconDarker = "habitOverIconDarker"
        static let overIconDarkness = "habitOverIconDarkness"
        static let gridBottomMargin = "habitGridBottomMargin"
        static let previewMargin = "habitPreviewMargin"
        static let prefix = "habitNotificationPrefix"
        static let separator = "habitNotificationSeparator"
    }

    static var prefix: String { d.string(forKey: Key.prefix) ?? "Habit" }
    static var separator: String { d.string(forKey: Key.separator) ?? NotificationTitle.defaultSeparator }


    private static var d: UserDefaults { AppGroup.defaults }
    private static func double(_ key: String, _ fallback: Double) -> Double {
        d.object(forKey: key) == nil ? fallback : d.double(forKey: key)
    }
    private static func symbol(_ key: String, _ fallback: String) -> String {
        let s = d.string(forKey: key) ?? ""
        return s.isEmpty ? fallback : s
    }

    /// До какого часа ночи отметка засчитывается предыдущему дню.
    static var dayCutoffHour: Int { d.integer(forKey: Key.dayCutoffHour) }
    /// Сколько недель чётко видно в виджете.
    static var widgetWeeks: Int { max(1, Int(double(Key.widgetWeeks, 4))) }
    static var buttonSize: Double { double(Key.buttonSize, 40) }
    /// Отступ кнопки от верхнего и правого края виджета.
    static var buttonInset: Double { double(Key.buttonInset, 12) }
    /// Отступ сетки от нижнего, левого и правого края виджета.
    static var gridInset: Double { double(Key.gridInset, 16) }
    /// Размер шрифта однострочного названия на виджетах (двустрочное — на треть меньше).
    static var titleSize: Double { double(Key.titleSize, 24) }
    /// Ближе какого расстояния до низа экрана подложка сетки на странице привычки не опускается.
    static var gridBottomMargin: Double { double(Key.gridBottomMargin, -11) }
    /// Поле подложки вокруг дня в контекстном меню, pt.
    static var previewMargin: Double { double(Key.previewMargin, 18) }

    static var style: HabitStyle {
        HabitStyle(undoneOpacity: double(Key.undoneOpacity, 0.15),
                   partialPattern: PartialPattern(rawValue: d.string(forKey: Key.partialPattern) ?? "") ?? .icon,
                   stripeWidth: double(Key.stripeWidth, 6),
                   doneStripeOpacity: double(Key.doneStripeOpacity, 1),
                   undoneStripeOpacity: double(Key.undoneStripeOpacity, 0.13),
                   partialSymbol: symbol(Key.partialSymbol, "tortoise.fill"),
                   overSymbol: symbol(Key.overSymbol, "bolt.fill"),
                   partialIconScale: double(Key.partialIconScale, 0.65),
                   overIconScale: double(Key.overIconScale, 0.65),
                   overIconDarker: d.object(forKey: Key.overIconDarker) == nil ? true : d.bool(forKey: Key.overIconDarker),
                   overIconDarkness: double(Key.overIconDarkness, 0.65))
    }
}

/// Как показывать недоделанный день.
enum PartialPattern: String, CaseIterable, Identifiable {
    case icon, lighter, outline, diagonal, half
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: "Icon"
        case .lighter: "Lighter fill"
        case .outline: "Outline"
        case .diagonal: "Diagonal stripes"
        case .half: "Half filled"
        }
    }
}

/// Снимок настроек отрисовки клеток — для сетки и виджетов.
struct HabitStyle {
    var undoneOpacity = 0.15
    var partialPattern = PartialPattern.icon
    var stripeWidth = 6.0
    var doneStripeOpacity = 1.0
    var undoneStripeOpacity = 0.13
    var partialSymbol = "tortoise.fill"
    var overSymbol = "bolt.fill"
    /// Размер иконок — доля стороны клетки.
    var partialIconScale = 0.65
    var overIconScale = 0.65
    /// Иконка перевыполнения темнее клетки (смесь цвета привычки с чёрным), а не светлее.
    var overIconDarker = true
    var overIconDarkness = 0.65
}

/// Заголовок уведомления с префиксом: «Habit · инбокс», «[Habit] инбокс».
enum NotificationTitle {
    static let defaultSeparator = "·"
    static let separators = ["·", "•", ":", "—", "|", "[ ]"]

    static func make(_ title: String, prefix: String, separator: String) -> String {
        let p = prefix.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return title }
        switch separator {
        case "[ ]": return "[\(p)] \(title)"
        case ":": return "\(p):  \(title)"
        default: return "\(p)  \(separator)  \(title)"
        }
    }
}

/// Картинки справа в уведомлениях: для привычек, для событий по умолчанию и для отдельных
/// календарей. Хранятся в общей папке.
struct NotificationImage {
    let key: String

    static let habit = NotificationImage(key: "habit")
    static let calendar = NotificationImage(key: "calendar")
    static func calendar(_ id: String) -> NotificationImage {
        NotificationImage(key: "calendar-" + id.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined())
    }

    /// Картинка для события: своя у календаря, иначе общая.
    static func forEvent(calendarID: String) -> NotificationImage {
        let own = calendar(calendarID)
        return own.exists ? own : .calendar
    }

    var url: URL { AppGroup.containerURL.appendingPathComponent("notification-\(key).png") }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Копия во временной папке: iOS забирает файл вложения себе.
    func attachmentCopy() -> URL? {
        guard exists else { return nil }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        return (try? FileManager.default.copyItem(at: url, to: copy)) == nil ? nil : copy
    }
}

extension Color {
    /// «#RRGGBB» или «#RRGGBBAA».
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? (v << 8) | 0xFF : v
        self.init(.sRGB,
                  red: Double((rgba >> 24) & 0xFF) / 255, green: Double((rgba >> 16) & 0xFF) / 255,
                  blue: Double((rgba >> 8) & 0xFF) / 255, opacity: Double(rgba & 0xFF) / 255)
    }
}
