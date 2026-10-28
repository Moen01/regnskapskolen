import Foundation

/// A month of the town's books, encoded as "2026-01".
public struct MonthKey: Hashable, Codable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(_ day: DayKey) { self.init(year: day.year, month: day.month) }

    public var first: DayKey { DayKey(year: year, month: month, day: 1) }
    public var next: MonthKey { MonthKey(first.adding(months: 1)) }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Ugyldig måned \(s), forventet ÅÅÅÅ-MM"))
        }
        self.init(year: y, month: m)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%04d-%02d", year, month))
    }
}

public enum DeadlineKind: Hashable, Codable, Sendable {
    case mva(termin: Int, year: Int)
    /// Annual filers cover the whole year in one go.
    case mvaAarlig(year: Int)

    public var id: String {
        switch self {
        case let .mva(termin, year): return "mva-\(year)-\(termin)"
        case let .mvaAarlig(year): return "mva-\(year)-aar"
        }
    }

    /// The months this deadline covers. Needs `rates` because the terms live in `satser.json`.
    public func months(rates: Rates) -> [MonthKey] {
        switch self {
        case let .mva(termin, year):
            let nums = rates.mvaTerminer.first { $0.nr == termin }?.maaneder ?? []
            return nums.map { MonthKey(year: year, month: $0) }
        case let .mvaAarlig(year):
            return (1...12).map { MonthKey(year: year, month: $0) }
        }
    }
}

public struct TownDeadline: Hashable, Sendable {
    public let day: DayKey
    public let kind: DeadlineKind
    public let client: String

    public init(day: DayKey, kind: DeadlineKind, client: String) {
        self.day = day
        self.kind = kind
        self.client = client
    }

    /// "10.04 MVA 1. TERMIN"; the date is the real due day after weekend rolling.
    public var label: String {
        let date = String(format: "%02d.%02d", day.day, day.month)
        switch kind {
        case let .mva(termin, _): return "\(date) MVA \(termin). TERMIN"
        case .mvaAarlig: return "\(date) MVA ÅRLIG"
        }
    }
}

public enum DeadlinePlanner {
    public static func deadlines(for client: TownClient, year: Int, deadlines: Deadlines) -> [TownDeadline] {
        guard client.mvaRegistrert, let type = client.mvaTermin else { return [] }
        switch type {
        case .tomaanedlig:
            return deadlines.rates.mvaTerminer.map {
                TownDeadline(day: deadlines.mvaFrist(termin: $0.nr, year: year), kind: .mva(termin: $0.nr, year: year), client: client.id)
            }
        case .aarlig:
            return [TownDeadline(day: deadlines.mvaAarligFrist(year: year), kind: .mvaAarlig(year: year), client: client.id)]
        }
    }

    /// Deadlines with `day <= d < day + days`, by date then client id.
    public static func upcoming(clients: [TownClient], from day: DayKey, days: Int, deadlines: Deadlines) -> [TownDeadline] {
        let end = day.adding(days: days)
        // The last term of the year before is due in February, so it can fall in this year's window.
        let years = (day.year - 1)...max(day.year, end.year)
        return years
            .flatMap { year in clients.flatMap { self.deadlines(for: $0, year: year, deadlines: deadlines) } }
            .filter { $0.day >= day && $0.day < end }
            .sorted { ($0.day, $0.client) < ($1.day, $1.client) }
    }
}
