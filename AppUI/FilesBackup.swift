import Foundation
import UserNotifications

/// Бэкапы базы и настроек. Пишутся в «Файлы → На iPhone → Habits on Reminders» и, если выбрана,
/// в свою папку (например, в iCloud Drive). В самой папке — только текущее состояние:
/// - `habits-settings.json` — настройки каждой привычки (без отметок по дням);
/// - `habits-fact-table.csv` — дни: отметки, заметки, причины пропуска, снятые вручную;
/// - `habits-names.csv` — ID и названия привычек;
/// - `app-settings.json` — общие настройки приложения и список причин пропуска.
/// В `backups/` — прежние состояния, каждое отдельной папкой с теми же четырьмя файлами:
/// `previous` (до последнего изменения), `daily` (до первого изменения за день) и
/// `habits-before-…` (перед подозрительно большим изменением, слиянием, восстановлением —
/// не перезаписываются). Файлы прежнего формата один раз переносятся в `backups/old-format`.
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
        HabitSettings.Key.reasonAlertDays, HabitSettings.Key.squircleButton, HabitSettings.Key.mainSquircle,
        HabitSettings.Key.mainSquircleSize, HabitSettings.Key.mainCheckboxSize,
        CalendarSettings.Key.bellInsetTop, CalendarSettings.Key.bellInsetRight, CalendarSettings.Key.darkBackgroundHex, CalendarSettings.Key.darkGradient, ToastSettings.Key.width, ToastSettings.Key.corners,
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

    static let settingsFile = "habits-settings.json"
    static let appSettingsFile = "app-settings.json"
    private static var fileNames: [String] { [settingsFile, HabitCSV.daysFile, HabitCSV.habitsFile, appSettingsFile] }
    /// Поля привычки с данными по дням — в habits-settings.json их нет (они в таблице дней).
    private static let dayFields = ["completions", "partialDays", "overDays", "twiceDays", "removedDays", "notes", "skipReasons"]

    /// Последнее записанное состояние базы — для сравнения (в папке приложения, не в «Файлах»).
    private static var lastBackupURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-backup.json")
    }

    private static var stamp: String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        return format.string(from: Date())
    }

    /// Снимок текущих файлов во все папки бэкапов: `backups/habits-<name>-дата/`.
    static func snapshot(_ name: String) {
        let label = "habits-\(name)-\(stamp)"
        eachFolder { copyCurrent(in: $0, to: label) }
    }

    static func write() {
        let db = HabitStorage.load()
        let files = makeFiles(db)
        // Сравниваем с прошлым бэкапом: слишком большое изменение за раз — сохраняем снимок «до».
        let old = (try? Data(contentsOf: lastBackupURL)).flatMap(decode)
        let warning = expectBigChange ? nil : old.flatMap { massChange(from: $0, to: db) }
        expectBigChange = false
        let snapshot = warning == nil ? nil : "habits-before-\(stamp)"

        eachFolder { write(files, to: $0, snapshot: snapshot) }
        if let data = encode(db) { try? data.write(to: lastBackupURL, options: .atomic) }
        if let warning, let snapshot { warn(warning + " A copy from before the change was saved in backups/\(snapshot) in the backup folders.") }
    }

    private static func eachFolder(_ body: (URL) -> Void) {
        body(localFolder)
        if let folder = chosenFolder {
            let access = folder.startAccessingSecurityScopedResource()
            body(folder)
            if access { folder.stopAccessingSecurityScopedResource() }
        }
    }

    private static func encode(_ db: HabitDB) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(db)
    }

    /// Четыре файла текущего состояния.
    private static func makeFiles(_ db: HabitDB) -> [String: Data] {
        var files: [String: Data] = [:]
        // Настройки привычек: база без данных по дням и без списка причин (он в общих настройках).
        if let data = encode(db), var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object["habits"] = (object["habits"] as? [[String: Any]])?.map { habit in habit.filter { !dayFields.contains($0.key) } }
            object["skipReasonPool"] = nil
            files[settingsFile] = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        }
        files[HabitCSV.daysFile] = Data(HabitCSV.makeDays(db.habits, reasons: db.reasons, includeRemoved: true).utf8)
        files[HabitCSV.habitsFile] = Data(HabitCSV.makeHabits(db.habits).utf8)
        var settings: [String: Any] = [:]
        for key in settingKeys { if let value = AppGroup.defaults.object(forKey: key) { settings[key] = value } }
        if let reasons = try? JSONEncoder().encode(db.reasons), let list = try? JSONSerialization.jsonObject(with: reasons) {
            settings["skipReasons"] = list
        }
        files[appSettingsFile] = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        return files
    }

    private static func write(_ files: [String: Data], to folder: URL, snapshot: String?) {
        let fm = FileManager.default
        migrateOldFiles(in: folder)
        let changed = files.contains { name, data in (try? Data(contentsOf: folder.appendingPathComponent(name))) != data }
        guard changed else { return }
        let hasCurrent = fm.fileExists(atPath: folder.appendingPathComponent(settingsFile).path)
        if hasCurrent {
            if let snapshot { copyCurrent(in: folder, to: snapshot) }
            // Дневная копия обновляется раз в день — состоянием до первого изменения за день.
            let daily = folder.appendingPathComponent("backups/daily")
            let dailyDate = (try? fm.attributesOfItem(atPath: daily.path)[.modificationDate] as? Date) ?? .distantPast
            if dailyDate < Calendar.current.startOfDay(for: Date()) { copyCurrent(in: folder, to: "daily") }
            copyCurrent(in: folder, to: "previous")
        }
        do {
            for (name, data) in files { try data.write(to: folder.appendingPathComponent(name), options: .atomic) }
        } catch {
            SyncIssues.report("Backup to “\(folder.lastPathComponent)” failed: \(error.localizedDescription)", once: true)
        }
    }

    /// Текущие файлы папки — в `backups/<label>/` (прежнее содержимое этой подпапки заменяется).
    private static func copyCurrent(in folder: URL, to label: String) {
        let fm = FileManager.default
        let target = folder.appendingPathComponent("backups/\(label)")
        try? fm.removeItem(at: target)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in fileNames {
            let source = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) { try? fm.copyItem(at: source, to: target.appendingPathComponent(name)) }
        }
        // Дата папки — момент снимка (по ней видно, когда обновлялась дневная копия).
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
    }

    /// Файлы прежнего формата (habits.json, habits-*.json, habits.csv, habit_days.csv, settings.json) —
    /// в `backups/old-format/`.
    private static func migrateOldFiles(in folder: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let old = names.filter { name in
            ["habits.json", "habits.csv", "habit_days.csv", "settings.json"].contains(name)
                || (name.hasPrefix("habits-") && name.hasSuffix(".json") && name != settingsFile)
        }
        guard !old.isEmpty else { return }
        let target = folder.appendingPathComponent("backups/old-format")
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in old {
            let to = target.appendingPathComponent(name)
            try? fm.removeItem(at: to)
            try? fm.moveItem(at: folder.appendingPathComponent(name), to: to)
        }
    }

    static func decode(_ data: Data) -> HabitDB? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HabitDB.self, from: data)
    }

    // MARK: Восстановление

    /// База из выбранных файлов бэкапа: habits-settings.json + habits-fact-table.csv
    /// (+ app-settings.json — список причин пропуска) или старый цельный habits*.json.
    static func restoreDB(from urls: [URL]) -> HabitDB? {
        var db: HabitDB?
        var facts: String?
        var reasons: [SkipReason]?
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if url.pathExtension.lowercased() == "csv" {
                facts = String(data: data, encoding: .utf8)
            } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if object["habits"] != nil {
                    db = decode(data)
                } else if let list = object["skipReasons"], let listData = try? JSONSerialization.data(withJSONObject: list) {
                    reasons = try? JSONDecoder().decode([SkipReason].self, from: listData)
                }
            }
        }
        guard var db else { return nil }
        if let reasons { db.reasons = reasons }
        if let facts { apply(facts, to: &db) }
        return db
    }

    /// Дни из таблицы фактов в базу (по ID привычки); причины — по названию из списка.
    private static func apply(_ text: String, to db: inout HabitDB) {
        let rows = HabitCSV.csvRows(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }),
              let idCol = header.firstIndex(of: "habit_id"), let dateCol = header.firstIndex(of: "date") else { return }
        let statusCol = header.firstIndex(of: "status"), noteCol = header.firstIndex(of: "note"), reasonCol = header.firstIndex(of: "skip_reason")
        let index = Dictionary(db.habits.indices.map { (db.habits[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
        func cell(_ row: [String], _ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil } ?? "" }
        for row in rows.dropFirst() {
            guard let id = UUID(uuidString: cell(row, idCol)), let i = index[id] else { continue }
            let key = cell(row, dateCol)
            guard HabitDay.date(key) != nil else { continue }
            switch cell(row, statusCol) {
            case "done": db.habits[i].completions.insert(key)
            case "partial": db.habits[i].completions.insert(key); db.habits[i].partialDays.insert(key)
            case "over": db.habits[i].completions.insert(key); db.habits[i].overDays.insert(key)
            case "twice": db.habits[i].completions.insert(key); db.habits[i].twiceDays.insert(key)
            case "removed": db.habits[i].removedDays.insert(key)
            default: break
            }
            let note = cell(row, noteCol)
            if !note.isEmpty { db.habits[i].notes[key] = note }
            let title = cell(row, reasonCol)
            if !title.isEmpty {
                let reasonID = db.reasons.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.id ?? {
                    let reason = SkipReason(title: title)
                    db.reasons.append(reason)
                    return reason.id
                }()
                db.habits[i].skipReasons[key] = reasonID
            }
        }
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
