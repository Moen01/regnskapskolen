import Foundation

extension Calendar {
    /// Gregorian, Oslo time, Monday first.
    public static let norwegian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        c.firstWeekday = 2
        c.locale = Locale(identifier: "nb_NO")
        return c
    }()
}

/// A calendar day in Oslo, stored as "YYYY-MM-DD".
public struct DayKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .norwegian) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m), (1...31).contains(d) else { return nil }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
        guard let date = Calendar.norwegian.date(from: comps), DayKey(date) == DayKey(year: y, month: m, day: d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public static func today() -> DayKey { DayKey(Date()) }

    public var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { string }

    /// Midnight in Oslo.
    public var date: Date {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = day
        return Calendar.norwegian.date(from: comps)!
    }

    public func adding(days: Int) -> DayKey { DayKey(Calendar.norwegian.date(byAdding: .day, value: days, to: date)!) }
    public func adding(months: Int) -> DayKey { DayKey(Calendar.norwegian.date(byAdding: .month, value: months, to: date)!) }

    /// The 42 days a month calendar shows: six rows of Monday to Sunday, starting on the Monday on
    /// or before the first of the month. Days from the months around fill the first and last rows.
    public static func monthGrid(year: Int, month: Int) -> [DayKey] {
        let first = DayKey(year: year, month: month, day: 1)
        let start = first.adding(days: -(first.weekday - 1))
        return (0..<42).map { start.adding(days: $0) }
    }

    public static func daysBetween(_ a: DayKey, _ b: DayKey) -> Int {
        Calendar.norwegian.dateComponents([.day], from: a.date, to: b.date).day!
    }

    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int {
        let w = Calendar.norwegian.component(.weekday, from: date)  // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    public var isWeekend: Bool { weekday >= 6 }

    /// ISO 8601 week: the first days of January can belong to the old year's last week.
    public var isoWeek: (year: Int, week: Int) {
        let c = Calendar.norwegian.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (c.yearForWeekOfYear!, c.weekOfYear!)
    }

    /// "2026-44"
    public var weekKey: String { let w = isoWeek; return "\(w.year)-\(w.week)" }

    public var isNorwegianPublicHoliday: Bool {
        if [(1, 1), (5, 1), (5, 17), (12, 25), (12, 26)].contains(where: { $0.0 == month && $0.1 == day }) { return true }
        let easter = Self.easterSunday(year: year)
        let offsets = [-3, -2, 0, 1, 39, 49, 50]  // skjærtorsdag, langfredag, 1. og 2. påskedag, Kristi himmelfart, 1. og 2. pinsedag
        return offsets.contains { easter.adding(days: $0) == self }
    }

    public var isWorkingDay: Bool { !isWeekend && !isNorwegianPublicHoliday }

    /// This day when it is a working day, else the first working day after it.
    public var nextWorkingDay: DayKey {
        var d = self
        while !d.isWorkingDay { d = d.adding(days: 1) }
        return d
    }

    /// Anonymous Gregorian algorithm.
    static func easterSunday(year: Int) -> DayKey {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return DayKey(year: year, month: month, day: day)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Ugyldig dato \(s), forventet ÅÅÅÅ-MM-DD"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}
