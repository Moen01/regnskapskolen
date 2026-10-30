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
    case amelding(month: MonthKey)
    /// Withholding tax for the pay day in `month`.
    case forskuddstrekk(month: MonthKey)
    case aga(termin: Int, year: Int)
    /// The tax return for `year`, due the year after.
    case skattemelding(year: Int)
    /// The annual accounts for `year`, due the year after.
    case aarsregnskap(year: Int)

    public var id: String {
        switch self {
        case let .mva(termin, year): return "mva-\(year)-\(termin)"
        case let .mvaAarlig(year): return "mva-\(year)-aar"
        case let .amelding(month): return String(format: "amelding-%04d-%02d", month.year, month.month)
        case let .forskuddstrekk(month): return String(format: "trekk-%04d-%02d", month.year, month.month)
        case let .aga(termin, year): return "aga-\(year)-\(termin)"
        case let .skattemelding(year): return "skatt-\(year)"
        case let .aarsregnskap(year): return "arsregnskap-\(year)"
        }
    }

    /// The year the deadline reports for. A month deadline reports for the year of its month.
    public var year: Int {
        switch self {
        case let .mva(_, year), let .mvaAarlig(year), let .aga(_, year), let .skattemelding(year), let .aarsregnskap(year): return year
        case let .amelding(month), let .forskuddstrekk(month): return month.year
        }
    }

    /// The months this deadline covers. Needs `rates` because the terms live in `satser.json`.
    public func months(rates: Rates) -> [MonthKey] {
        switch self {
        case let .mva(termin, year):
            let nums = rates.mvaTerminer.first { $0.nr == termin }?.maaneder ?? []
            return nums.map { MonthKey(year: year, month: $0) }
        case let .mvaAarlig(year), let .skattemelding(year), let .aarsregnskap(year):
            return (1...12).map { MonthKey(year: year, month: $0) }
        case let .amelding(month):
            return [month]
        case .forskuddstrekk:
            return []
        case let .aga(termin, year):
            let nums = rates.agaTerminer.first { $0.nr == termin }?.maaneder ?? []
            return nums.map { MonthKey(year: year, month: $0) }
        }
    }
}

public struct TownDeadline: Hashable, Sendable {
    public let day: DayKey
    public let kind: DeadlineKind
    public let client: String
    /// The first day the deadline can be delivered.
    public let opens: DayKey

    public init(day: DayKey, kind: DeadlineKind, client: String, opens: DayKey? = nil) {
        self.day = day
        self.opens = opens ?? day
        self.kind = kind
        self.client = client
    }

    /// "10.04 MVA 1. TERMIN"; the date is the real due day after weekend rolling.
    public var label: String {
        let date = String(format: "%02d.%02d", day.day, day.month)
        switch kind {
        case let .mva(termin, _): return "\(date) MVA \(termin). TERMIN"
        case .mvaAarlig: return "\(date) MVA ÅRLIG"
        case let .amelding(month): return "\(date) A-MELDING \(Self.monthNames[month.month - 1])"
        case let .forskuddstrekk(month): return "\(date) TREKK \(Self.monthNames[month.month - 1])"
        case let .aga(termin, _): return "\(date) AGA \(termin). TERMIN"
        case let .skattemelding(year): return "\(date) SKATTEMELDING \(year)"
        case let .aarsregnskap(year): return "\(date) ÅRSREGNSKAP \(year)"
        }
    }

    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DES"]

    /// "10.04 MVA1": short enough that a list row keeps the client's name.
    public var shortLabel: String {
        String(format: "%02d.%02d ", day.day, day.month) + kind.shortName
    }
}

extension DeadlineKind {
    /// "MVA1" or "MVAÅR", for list rows.
    public var shortName: String {
        switch self {
        case let .mva(termin, _): return "MVA\(termin)"
        case .mvaAarlig: return "MVAÅR"
        case let .amelding(month): return "AMELD\(month.month)"
        case let .forskuddstrekk(month): return "TREKK\(month.month)"
        case let .aga(termin, _): return "AGA\(termin)"
        case .skattemelding: return "SKATT"
        case .aarsregnskap: return "ÅRSREGN"
        }
    }
}

public enum DeadlinePlanner {
    /// Company forms that file a tax return, and those that also send annual accounts.
    public static let skattemeldingForms: Set<String> = ["AS", "ENK"]
    public static let aarsregnskapForms: Set<String> = ["AS"]

    public static func deadlines(for client: TownClient, year: Int, deadlines: Deadlines) -> [TownDeadline] {
        vatDeadlines(for: client, year: year, deadlines: deadlines)
            + payrollDeadlines(for: client, year: year, deadlines: deadlines)
            + annualDeadlines(for: client, year: year, deadlines: deadlines)
    }

    private static func annualDeadlines(for client: TownClient, year: Int, deadlines: Deadlines) -> [TownDeadline] {
        var list: [TownDeadline] = []
        if skattemeldingForms.contains(client.selskapsform) {
            let kind = DeadlineKind.skattemelding(year: year)
            list.append(TownDeadline(day: deadlines.skattemeldingFrist(year: year), kind: kind, client: client.id, opens: opens(kind, rates: deadlines.rates)))
        }
        if aarsregnskapForms.contains(client.selskapsform) {
            let kind = DeadlineKind.aarsregnskap(year: year)
            list.append(TownDeadline(day: deadlines.aarsregnskapFrist(year: year), kind: kind, client: client.id, opens: opens(kind, rates: deadlines.rates)))
        }
        return list
    }

    private static func vatDeadlines(for client: TownClient, year: Int, deadlines: Deadlines) -> [TownDeadline] {
        guard client.mvaRegistrert, let type = client.mvaTermin else { return [] }
        switch type {
        case .tomaanedlig:
            return deadlines.rates.mvaTerminer.map {
                let kind = DeadlineKind.mva(termin: $0.nr, year: year)
                return TownDeadline(day: deadlines.mvaFrist(termin: $0.nr, year: year), kind: kind, client: client.id, opens: opens(kind, rates: deadlines.rates))
            }
        case .aarlig:
            let kind = DeadlineKind.mvaAarlig(year: year)
            return [TownDeadline(day: deadlines.mvaAarligFrist(year: year), kind: kind, client: client.id, opens: opens(kind, rates: deadlines.rates))]
        }
    }

    private static func payrollDeadlines(for client: TownClient, year: Int, deadlines: Deadlines) -> [TownDeadline] {
        guard client.ansatte > 0, let payDay = client.lonnsdag else { return [] }
        let rates = deadlines.rates
        let months = (1...12).map { MonthKey(year: year, month: $0) }
        let ameldinger = months.map { m -> TownDeadline in
            let kind = DeadlineKind.amelding(month: m)
            return TownDeadline(day: deadlines.ameldingFrist(forMonth: m.month, year: year), kind: kind, client: client.id, opens: opens(kind, rates: rates))
        }
        let trekk = months.map { m -> TownDeadline in
            let kind = DeadlineKind.forskuddstrekk(month: m)
            let paid = DayKey(year: year, month: m.month, day: payDay)
            return TownDeadline(day: deadlines.forskuddstrekkFrist(utbetalt: paid), kind: kind, client: client.id, opens: paid)
        }
        let aga = rates.agaTerminer.map {
            let kind = DeadlineKind.aga(termin: $0.nr, year: year)
            return TownDeadline(day: deadlines.agaFrist(termin: $0.nr, year: year), kind: kind, client: client.id, opens: opens(kind, rates: rates))
        }
        return ameldinger + trekk + aga
    }

    /// The day after the last month the deadline covers; withholding opens on the pay day instead.
    private static func opens(_ kind: DeadlineKind, rates: Rates) -> DayKey {
        kind.months(rates: rates).last?.next.first ?? DayKey(year: 1970, month: 1, day: 1)
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
