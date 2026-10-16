import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Название приложения в интерфейсе и текстах.
#if os(iOS)
let appName = "Habits on Reminders & Calendar Enhancer"
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
        static let keepAfterSwipe = "keepNotificationAfterSwipe"
        static let notifyMovedIntoPast = "notifyWhenAlertMovedIntoPast"
        static let removeWhenMovedLater = "removeNotificationWhenMovedLater"
        static let removeWhenDeleted = "removeNotificationWhenDeleted"
        static let staleLabelMinutes = "staleLabelMinutes"
        static let cursorHex = "cursorHex"
        static let cursorOverEventOpacity = "cursorOverEventOpacity"
        static let bellOpacityLight = "bellOpacityLight"
        static let bellOpacityDark = "bellOpacityDark"
        static let bellHexLight = "bellHexLight"
        static let bellHexDark = "bellHexDark"
        static let defaultDayStart = "defaultDayStart"
        static let defaultDayEnd = "defaultDayEnd"
    }

    static let defaultCursorHex = "#D02D1E"
    /// Прежний цвет по умолчанию: если он сохранён, значит его не выбирали — берём новый.
    private static let oldDefaultCursorHex = "#E9534CFF"

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
    /// После смахивания класть уведомление обратно в список.
    static var keepAfterSwipe: Bool { bool(Key.keepAfterSwipe, true) }
    /// Событие перенесли раньше и время его alert уже прошло — прислать уведомление сразу.
    static var notifyMovedIntoPast: Bool { bool(Key.notifyMovedIntoPast, true) }
    static var removeWhenMovedLater: Bool { bool(Key.removeWhenMovedLater, true) }
    static var removeWhenDeleted: Bool { bool(Key.removeWhenDeleted, true) }
    /// С какой давности данных показывать подпись «N min ago».
    static var staleLabelMinutes: Int { max(1, int(Key.staleLabelMinutes, 30)) }
    /// Цвет курсора — без прозрачности (она задаётся отдельно, для части над событиями).
    static var cursorColor: Color {
        var hex = d.string(forKey: Key.cursorHex) ?? defaultCursorHex
        if hex == oldDefaultCursorHex { hex = defaultCursorHex }
        return Color(hex: String(hex.trimmingCharacters(in: .whitespaces).prefix(7))) ?? .red
    }
    /// Непрозрачность части курсора над событиями.
    /// Непрозрачность колокольчика (цвет календаря) у событий с alert — в светлой и тёмной теме.
    static func bellOpacity(dark: Bool) -> Double {
        let key = dark ? Key.bellOpacityDark : Key.bellOpacityLight
        return d.object(forKey: key) == nil ? (dark ? 0.7 : 0.5) : d.double(forKey: key)
    }
    /// Свой цвет колокольчика (светлая / тёмная тема); nil — цвет календаря.
    static func bellColor(dark: Bool) -> Color? {
        let hex = d.string(forKey: dark ? Key.bellHexDark : Key.bellHexLight) ?? ""
        return hex.isEmpty ? nil : Color(hex: String(hex.prefix(7)))
    }
    static var cursorOverEventOpacity: Double {
        d.object(forKey: Key.cursorOverEventOpacity) == nil ? 0.7 : d.double(forKey: Key.cursorOverEventOpacity)
    }
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
        static let missedHex = "habitMissedHex"
        static let missedOpacity = "habitMissedOpacity"
        static let missedLinkOpacity = "habitMissedLinkOpacity"
        static let twicePattern = "habitTwicePattern"
        static let twiceSymbol = "habitTwiceSymbol"
        static let twiceIconScale = "habitTwiceIconScale"
        static let twiceInnerSize = "habitTwiceInnerSize"
        static let twiceDarker = "habitTwiceDarker"
        static let twiceDarkness = "habitTwiceDarkness"
        static let reasonAlertDays = "habitReasonAlertDays"
        static let squircleButton = "habitSquircleButton"
    }


    private static var d: UserDefaults { AppGroup.defaults }
    private static func double(_ key: String, _ fallback: Double) -> Double {
        d.object(forKey: key) == nil ? fallback : d.double(forKey: key)
    }
    private static func symbol(_ key: String, _ fallback: String) -> String {
        let s = d.string(forKey: key) ?? ""
        return s.isEmpty ? fallback : s
    }

    /// Через сколько дней подряд с одной причиной прислать уведомление (0 — не присылать).
    static var reasonAlertDays: Int { Int(double(Key.reasonAlertDays, 3)) }
    /// До какого часа ночи отметка засчитывается предыдущему дню.
    static var dayCutoffHour: Int { Int(double(Key.dayCutoffHour, 3)) }
    /// Сколько недель чётко видно в виджете.
    static var widgetWeeks: Int { max(1, Int(double(Key.widgetWeeks, 4))) }
    static var buttonSize: Double { double(Key.buttonSize, 40) }
    /// Кнопка виджета — сегодняшний день как клетка сетки (иначе — круглый чекбокс).
    static var squircleButton: Bool { d.object(forKey: Key.squircleButton) == nil ? true : d.bool(forKey: Key.squircleButton) }
    /// Отступ кнопки от верхнего и правого края виджета.
    static var buttonInset: Double { double(Key.buttonInset, squircleButton ? 14 : 9) }
    /// Отступ сетки от нижнего, левого и правого края виджета.
    static var gridInset: Double { double(Key.gridInset, 18) }
    /// Размер шрифта однострочного названия на виджетах (двустрочное — на треть меньше).
    static var titleSize: Double { double(Key.titleSize, 24) }
    /// Ближе какого расстояния до низа экрана подложка сетки на странице привычки не опускается.
    static var gridBottomMargin: Double { double(Key.gridBottomMargin, 1) }

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
                   overIconDarkness: double(Key.overIconDarkness, 0.6),
                   twicePattern: TwicePattern(rawValue: d.string(forKey: Key.twicePattern) ?? "") ?? .innerSquare,
                   twiceSymbol: symbol(Key.twiceSymbol, "2.circle.fill"),
                   twiceIconScale: double(Key.twiceIconScale, 0.65),
                   twiceInnerSize: double(Key.twiceInnerSize, 0.55),
                   twiceDarker: d.object(forKey: Key.twiceDarker) == nil ? true : d.bool(forKey: Key.twiceDarker),
                   twiceDarkness: double(Key.twiceDarkness, 0.55),
                   missedHex: d.string(forKey: Key.missedHex) ?? HabitStyle.defaultMissedHex,
                   missedOpacity: double(Key.missedOpacity, 0.25),
                   missedLinkOpacity: double(Key.missedLinkOpacity, 0.15))
    }
}

/// Как показывать день, сделанный дважды (поверх обычной заливки сделанного дня).
enum TwicePattern: String, CaseIterable, Identifiable {
    case innerSquare, innerOutline, icon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .innerSquare: "Inner square"
        case .innerOutline: "Inner outline"
        case .icon: "Icon"
        }
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
    var overIconDarkness = 0.6
    var twicePattern = TwicePattern.innerSquare
    var twiceSymbol = "2.circle.fill"
    var twiceIconScale = 0.65
    /// Сторона внутреннего квадрата — доля стороны дня.
    var twiceInnerSize = 0.55
    /// Отметка «дважды» темнее дня (смесь с чёрным), а не светлее.
    var twiceDarker = true
    var twiceDarkness = 0.55
    /// Пропуски сверх допустимого: цвет (без прозрачности) и прозрачность дней и перемычек
    /// между соседними пропусками в неделе.
    var missedHex = HabitStyle.defaultMissedHex
    var missedOpacity = 0.25
    var missedLinkOpacity = 0.15
    static let defaultMissedHex = "#FF0000"

    /// Цвет пропусков: свой у привычки или общий (прозрачность из hex не берётся).
    func missedColor(_ own: String?) -> Color {
        Color(hex: String((own ?? missedHex).trimmingCharacters(in: .whitespaces).prefix(7))) ?? .red
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
