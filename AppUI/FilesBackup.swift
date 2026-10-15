import Foundation

/// Копии данных в «Файлы → На iPhone → Cal Enh & Hab»: привычки (JSON и CSV) и все настройки (JSON).
enum FilesBackup {
    private static var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// Все ключи настроек приложения.
    private static let settingKeys: [String] = [
        CalendarSettings.Key.alertsEnabled, CalendarSettings.Key.keepAfterTap, CalendarSettings.Key.removeWhenMovedLater,
        CalendarSettings.Key.removeWhenDeleted, CalendarSettings.Key.staleLabelMinutes, CalendarSettings.Key.cursorHex,
        CalendarSettings.Key.notificationTapOpensEvent, CalendarSettings.Key.defaultDayStart, CalendarSettings.Key.defaultDayEnd,
        CalendarSettings.Key.prefix, CalendarSettings.Key.separator,
        HabitSettings.Key.dayCutoffHour, HabitSettings.Key.widgetWeeks, HabitSettings.Key.buttonSize, HabitSettings.Key.buttonInset,
        HabitSettings.Key.gridInset, HabitSettings.Key.titleSize, HabitSettings.Key.undoneOpacity, HabitSettings.Key.partialPattern,
        HabitSettings.Key.stripeWidth, HabitSettings.Key.doneStripeOpacity, HabitSettings.Key.undoneStripeOpacity,
        HabitSettings.Key.partialSymbol, HabitSettings.Key.overSymbol, HabitSettings.Key.partialIconScale,
        HabitSettings.Key.overIconScale, HabitSettings.Key.overIconDarker, HabitSettings.Key.overIconDarkness,
        HabitSettings.Key.gridBottomMargin, HabitSettings.Key.previewMargin, HabitSettings.Key.prefix, HabitSettings.Key.separator,
    ]

    static func write() {
        let db = HabitStorage.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(db) { try? data.write(to: folder.appendingPathComponent("habits.json"), options: .atomic) }
        try? HabitCSV.make(db.habits).write(to: folder.appendingPathComponent("habits.csv"), atomically: true, encoding: .utf8)

        var settings: [String: Any] = [:]
        for key in settingKeys { if let value = AppGroup.defaults.object(forKey: key) { settings[key] = value } }
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("settings.json"), options: .atomic)
        }
    }
}
