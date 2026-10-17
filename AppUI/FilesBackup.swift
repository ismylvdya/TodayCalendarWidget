import Foundation
import UserNotifications

/// Бэкапы базы и настроек. Пишутся в «Файлы → На iPhone → Habits on Reminders» и, если выбрана,
/// в свою папку (например, в iCloud Drive). В каждой папке:
/// - `habits.json` — текущая база, `habits-previous.json` — до последнего изменения;
/// - `habits-daily.json` — состояние до первого изменения за день (независимая вчерашняя копия);
/// - `habits-before-…json` — снимок перед подозрительно большим изменением (сам не удаляется);
/// - `habits.csv` и `habit_days.csv` (привычки и дни) и `settings.json`.
enum FilesBackup {
    private static var localFolder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static let bookmarkKey = "backupFolderBookmark"

    /// Все ключи настроек приложения.
    private static let settingKeys: [String] = [
        CalendarSettings.Key.alertsEnabled, CalendarSettings.Key.keepAfterTap, CalendarSettings.Key.keepAfterSwipe, CalendarSettings.Key.notifyMovedIntoPast, CalendarSettings.Key.removeWhenMovedLater,
        CalendarSettings.Key.removeWhenDeleted, CalendarSettings.Key.staleLabelMinutes, CalendarSettings.Key.cursorHex, CalendarSettings.Key.cursorOverEventOpacity, CalendarSettings.Key.bellOpacityLight, CalendarSettings.Key.bellOpacityDark, CalendarSettings.Key.bellHexLight, CalendarSettings.Key.bellHexDark,
        CalendarSettings.Key.defaultDayStart, CalendarSettings.Key.defaultDayEnd,
        HabitSettings.Key.dayCutoffHour, HabitSettings.Key.widgetWeeks, HabitSettings.Key.buttonSize, HabitSettings.Key.buttonInset,
        HabitSettings.Key.gridInset, HabitSettings.Key.titleSize, HabitSettings.Key.undoneOpacity, HabitSettings.Key.partialPattern,
        HabitSettings.Key.undonePattern, HabitSettings.Key.undoneSymbol, HabitSettings.Key.undoneIconScale, HabitSettings.Key.undoneIconOpacity, HabitSettings.Key.undoneOutlineWidth,
        HabitSettings.Key.stripeWidth, HabitSettings.Key.doneStripeOpacity, HabitSettings.Key.undoneStripeOpacity,
        HabitSettings.Key.partialSymbol, HabitSettings.Key.overSymbol, HabitSettings.Key.partialIconScale,
        HabitSettings.Key.overIconScale, HabitSettings.Key.overIconDarker, HabitSettings.Key.overIconDarkness,
        HabitSettings.Key.gridBottomMargin, HabitSettings.Key.missedHex, HabitSettings.Key.missedOpacity, HabitSettings.Key.missedLinkOpacity,
        HabitSettings.Key.twicePattern, HabitSettings.Key.twiceSymbol, HabitSettings.Key.twiceIconScale,
        HabitSettings.Key.twiceInnerSize, HabitSettings.Key.twiceDarker, HabitSettings.Key.twiceDarkness,
    ]

    // MARK: Своя папка

    /// Выбранная папка (доступ к ней сохраняется закладкой между запусками).
    static var chosenFolder: URL? {
        guard let data = AppGroup.defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() { AppGroup.defaults.set(fresh, forKey: bookmarkKey) }
        return url
    }

    static func setFolder(_ url: URL?) {
        guard let url else { AppGroup.defaults.removeObject(forKey: bookmarkKey); return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            AppGroup.defaults.set(try url.bookmarkData(), forKey: bookmarkKey)
        } catch {
            SyncIssues.report("Couldn't use the folder “\(url.lastPathComponent)” for backups: \(error.localizedDescription)")
            return
        }
        write()
    }

    // MARK: Запись

    /// Следующее изменение ожидаемо большое (слияние, восстановление) — без предупреждения.
    static var expectBigChange = false

    /// Снимок текущей базы во все папки бэкапов: «habits-<name>-дата.json».
    static func snapshot(_ name: String) {
        guard let data = try? Data(contentsOf: localFolder.appendingPathComponent("habits.json")) else { return }
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        let file = "habits-\(name)-\(format.string(from: Date())).json"
        try? data.write(to: localFolder.appendingPathComponent(file), options: .atomic)
        if let folder = chosenFolder {
            let access = folder.startAccessingSecurityScopedResource()
            try? data.write(to: folder.appendingPathComponent(file), options: .atomic)
            if access { folder.stopAccessingSecurityScopedResource() }
        }
    }

    static func write() {
        let db = HabitStorage.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(db) else { return }

        // Сравниваем с прошлым бэкапом: слишком большое изменение за раз — сохраняем снимок «до».
        let old = try? Data(contentsOf: localFolder.appendingPathComponent("habits.json"))
        let warning = expectBigChange ? nil : old.flatMap(decode).flatMap { massChange(from: $0, to: db) }
        expectBigChange = false
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        let snapshot = warning == nil ? nil : "habits-before-\(format.string(from: Date())).json"

        write(data, db: db, to: localFolder, snapshot: snapshot)
        if let folder = chosenFolder {
            let access = folder.startAccessingSecurityScopedResource()
            write(data, db: db, to: folder, snapshot: snapshot)
            if access { folder.stopAccessingSecurityScopedResource() }
        }
        if let warning, let snapshot { warn(warning + " A copy from before the change was saved as \(snapshot) in the backup folders.") }
    }

    private static func write(_ data: Data, db: HabitDB, to folder: URL, snapshot: String?) {
        let fm = FileManager.default
        let current = folder.appendingPathComponent("habits.json")
        let old = try? Data(contentsOf: current)
        do {
            if let old, old != data {
                if let snapshot { try old.write(to: folder.appendingPathComponent(snapshot), options: .atomic) }
                // Дневная копия обновляется раз в день — состоянием до первого изменения за день.
                let daily = folder.appendingPathComponent("habits-daily.json")
                let dailyDate = (try? fm.attributesOfItem(atPath: daily.path)[.modificationDate] as? Date) ?? .distantPast
                if dailyDate < Calendar.current.startOfDay(for: Date()) { try old.write(to: daily, options: .atomic) }
                try old.write(to: folder.appendingPathComponent("habits-previous.json"), options: .atomic)
            }
            if old != data { try data.write(to: current, options: .atomic) }
            try HabitCSV.makeHabits(db.habits).write(to: folder.appendingPathComponent(HabitCSV.habitsFile), atomically: true, encoding: .utf8)
            try HabitCSV.makeDays(db.habits, reasons: db.reasons).write(to: folder.appendingPathComponent(HabitCSV.daysFile), atomically: true, encoding: .utf8)
            var settings: [String: Any] = [:]
            for key in settingKeys { if let value = AppGroup.defaults.object(forKey: key) { settings[key] = value } }
            let json = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: folder.appendingPathComponent("settings.json"), options: .atomic)
        } catch {
            SyncIssues.report("Backup to “\(folder.lastPathComponent)” failed: \(error.localizedDescription)", once: true)
        }
    }

    static func decode(_ data: Data) -> HabitDB? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HabitDB.self, from: data)
    }

    // MARK: Подозрительные изменения

    /// Сразу пропало много отметок, несколько привычек или поменялись привязки у нескольких
    /// привычек (Reminders пересоздали напоминания, база случайно очистилась…).
    private static func massChange(from old: HabitDB, to new: HabitDB) -> String? {
        let newByID = Dictionary(new.habits.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let removed = old.habits.filter { newByID[$0.id] == nil }
        var lostMarks = removed.reduce(0) { $0 + $1.completions.count }, relinked = 0
        for habit in old.habits {
            guard let now = newByID[habit.id] else { continue }
            lostMarks += habit.completions.subtracting(now.completions).count
            let before = Set(habit.links.map(\.reminderID)), after = Set(now.links.map(\.reminderID))
            if !before.isEmpty && before.isDisjoint(with: after) { relinked += 1 }
        }
        var problems: [String] = []
        if removed.count >= 2 { problems.append("\(removed.count) habits disappeared") }
        if lostMarks >= 10 { problems.append("\(lostMarks) marked days disappeared") }
        if relinked >= 2 { problems.append("\(relinked) habits lost all their linked reminders") }
        return problems.isEmpty ? nil : "Big change in habits at once: " + problems.joined(separator: ", ") + "."
    }

    /// Алерт в приложении и уведомление (если приложение не на экране).
    private static func warn(_ message: String) {
        SyncIssues.report(message)
        let content = UNMutableNotificationContent()
        content.title = "Habits changed a lot"
        content.body = message
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "backup-warning-\(UUID().uuidString)", content: content, trigger: nil))
    }
}
