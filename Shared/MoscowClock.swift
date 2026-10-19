import Foundation

/// Московское время для виджета на экране блокировки. Берём часы самого iPhone (iOS сверяет их
/// по сети и продолжает точно идти без неё) и показываем в поясе Europe/Moscow — это UTC+3,
/// а если правила пояса когда-нибудь поменяются, их обновит сама iOS.
enum MoscowClock {
    static let prefixKey = "moscowClockPrefix"
    static let timeZone = TimeZone(identifier: "Europe/Moscow") ?? TimeZone(secondsFromGMT: 3 * 3600)!

    /// Текст перед временем, как его ввели (с кодами вроде \u2800).
    static var rawPrefix: String { AppGroup.defaults.string(forKey: prefixKey) ?? "" }

    /// «чч:мм» по Москве.
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func line(_ date: Date, prefix: String = rawPrefix) -> String { decode(prefix) + time(date) }

    /// Коды символов в тексте — сами символы: `\u2800`, `\u{2800}`, `U+2800`.
    static func decode(_ text: String) -> String {
        let pattern = #"\\u\{([0-9A-Fa-f]{1,6})\}|\\u([0-9A-Fa-f]{4})|U\+([0-9A-Fa-f]{4,6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let hex = (1...3).compactMap { i -> String? in
                guard let r = Range(match.range(at: i), in: text) else { return nil }
                return String(text[r])
            }.first
            guard let hex, let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }
}
