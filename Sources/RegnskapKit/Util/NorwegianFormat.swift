import Foundation

/// Amounts and dates the way a Norwegian accountant writes them: "1 250,00", "10.06.2026".
public enum NorwegianFormat {
    /// Reads "1 250,00", "1.250,00", "1250", "1 250,5", "kr 1 250", "1,250.00". Nil for anything else.
    public static func parseAmount(_ text: String) -> Decimal? {
        var s = text.lowercased().replacingOccurrences(of: "kr", with: "")
        s = String(s.filter { !$0.isWhitespace })
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        guard !s.isEmpty else { return nil }
        // The last separator followed by one or two digits is the decimal mark; the rest are thousands.
        var decimalMark: Character?
        if let last = s.lastIndex(where: { $0 == "," || $0 == "." }) {
            let digitsAfter = s.distance(from: s.index(after: last), to: s.endIndex)
            if (1...2).contains(digitsAfter), s[s.index(after: last)...].allSatisfy(\.isNumber) { decimalMark = s[last] }
        }
        var cleaned = ""
        for ch in s {
            if ch == "," || ch == "." { if ch == decimalMark { cleaned.append(".") } }
            else { cleaned.append(ch) }
        }
        // Exactly one decimal point remains when a mark was found; two separators of the mark's kind is garbage.
        // Exactly: an optional leading minus, digits, at most one point. `Decimal(string:)` would read "1-000" as 1.
        let unsigned = cleaned.hasPrefix("-") ? String(cleaned.dropFirst()) : cleaned
        guard unsigned.filter({ $0 == "." }).count <= 1, unsigned.contains(where: \.isNumber),
              unsigned.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// "1 250,00" with a narrow no-break space between thousands and a comma before the decimals;
    /// negatives with a true minus sign.
    public static func kroner(_ amount: Decimal, decimals: Int = 2) -> String {
        var rounded = amount
        var source = amount
        NSDecimalRound(&rounded, &source, decimals, .bankers)
        let negative = rounded < 0
        let magnitude = negative ? -rounded : rounded
        let text = NSDecimalNumber(decimal: magnitude).description(withLocale: Locale(identifier: "en_US_POSIX"))
        var whole = text, fraction = ""
        if let dot = text.firstIndex(of: ".") {
            whole = String(text[..<dot])
            fraction = String(text[text.index(after: dot)...])
        }
        var grouped = ""
        for (i, ch) in whole.reversed().enumerated() {
            if i > 0, i % 3 == 0 { grouped.append("\u{202F}") }
            grouped.append(ch)
        }
        grouped = String(grouped.reversed())
        if decimals > 0 {
            fraction = String((fraction + String(repeating: "0", count: decimals)).prefix(decimals))
            grouped += "," + fraction
        }
        return (negative ? "\u{2212}" : "") + grouped
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .norwegian
        f.timeZone = Calendar.norwegian.timeZone
        f.locale = Locale(identifier: "nb_NO")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    /// "10.06.2026"
    public static func date(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Reads "2026-06-10" (midnight in Oslo). Nil for other shapes.
    public static func parseDate(_ text: String) -> Date? { DayKey(string: text)?.date }

    /// Reads a day the way it is typed: "10.06.2026", "1.6.2026", "10/06/2026", "10-06-2026" or
    /// "2026-06-10". The year must have four digits: a two-digit year cannot be told from one that
    /// is still being typed. Nil for anything else, including days that do not exist.
    public static func parseDay(_ text: String) -> DayKey? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(omittingEmptySubsequences: false, whereSeparator: { ".-/".contains($0) })
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }) else { return nil }
        let (yearPart, monthPart, dayPart) = parts[0].count == 4 ? (parts[0], parts[1], parts[2]) : (parts[2], parts[1], parts[0])
        guard yearPart.count == 4, monthPart.count <= 2, dayPart.count <= 2,
              let year = Int(yearPart), let month = Int(monthPart), let day = Int(dayPart) else { return nil }
        return DayKey(string: String(format: "%04d-%02d-%02d", year, month, day))
    }
}
