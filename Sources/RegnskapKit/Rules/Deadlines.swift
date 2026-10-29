import Foundation

/// Statutory deadlines computed from `Rates`. Every date is rolled to the next working day when it
/// lands on a weekend or a Norwegian public holiday.
public struct Deadlines: Hashable, Sendable {
    public let rates: Rates

    public init(rates: Rates) { self.rates = rates }

    public func mvaTermin(for day: DayKey) -> Termin {
        rates.mvaTerminer.first { $0.maaneder.contains(day.month) } ?? rates.mvaTerminer[0]
    }

    public func mvaFrist(termin nr: Int, year: Int) -> DayKey {
        guard let termin = rates.mvaTerminer.first(where: { $0.nr == nr }) else { return DayKey(year: year, month: 1, day: 1) }
        return termin.frist.day(forYear: year).nextWorkingDay
    }

    public func mvaFrister(year: Int) -> [DayKey] { rates.mvaTerminer.map { mvaFrist(termin: $0.nr, year: year) } }

    public func mvaAarligFrist(year: Int) -> DayKey { rates.mvaAarligFrist.day(forYear: year).nextWorkingDay }

    /// The a-melding for `month` is due on the rates' day of the following month.
    public func ameldingFrist(forMonth month: Int, year: Int) -> DayKey {
        let next = DayKey(year: year, month: month, day: 1).adding(months: 1)
        return DayKey(year: next.year, month: next.month, day: rates.ameldingFristDag).nextWorkingDay
    }

    public func agaTermin(for day: DayKey) -> Termin {
        rates.agaTerminer.first { $0.maaneder.contains(day.month) } ?? rates.agaTerminer[0]
    }

    public func agaFrist(termin nr: Int, year: Int) -> DayKey {
        guard let termin = rates.agaTerminer.first(where: { $0.nr == nr }) else { return DayKey(year: year, month: 1, day: 1) }
        return termin.frist.day(forYear: year).nextWorkingDay
    }

    /// From 2026: the first working day after the pay date.
    public func forskuddstrekkFrist(utbetalt: DayKey) -> DayKey { utbetalt.adding(days: 1).nextWorkingDay }

    /// The accounts for `year` reach Regnskapsregisteret by the rule's day the year after.
    public func aarsregnskapFrist(year: Int) -> DayKey { rates.aarsregnskap.sendesInnen.day(forYear: year).nextWorkingDay }

    /// The general meeting fixes the accounts within the rule's months after year end (no rolling: the law says "innen").
    public func aarsregnskapFastsettesFrist(year: Int) -> DayKey {
        DayKey(year: year + 1, month: 1, day: 1).adding(months: rates.aarsregnskap.fastsettesInnenMaaneder).adding(days: -1)
    }

    public func skattemeldingFrist(year: Int) -> DayKey { rates.skattemeldingFrist.day(forYear: year).nextWorkingDay }
}
