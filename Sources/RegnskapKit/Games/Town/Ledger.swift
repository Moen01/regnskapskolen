import Foundation

public struct BookedBilag: Hashable, Codable, Sendable {
    public let puzzleId: String
    public let month: MonthKey
    public let day: DayKey
    public let correct: Bool

    public init(puzzleId: String, month: MonthKey, day: DayKey, correct: Bool) {
        self.puzzleId = puzzleId
        self.month = month
        self.day = day
        self.correct = correct
    }
}

/// A wrong booking that comes back when the month is closed.
public struct OpenError: Hashable, Codable, Sendable, Identifiable {
    public let puzzleId: String
    public let client: String
    public let month: MonthKey
    public let day: DayKey
    public let boxBefore: Int

    public init(puzzleId: String, client: String, month: MonthKey, day: DayKey, boxBefore: Int) {
        self.puzzleId = puzzleId
        self.client = client
        self.month = month
        self.day = day
        self.boxBefore = boxBefore
    }

    public var id: String { "\(client):\(puzzleId):\(day.string)" }
}

public enum Ledger {
    /// The month's bilag still to book. The monthly slice is cut from the whole list *before* the
    /// pool filter, so a month keeps its content when "show drafts" is switched on and off.
    /// `start` is the game's first month; the client's own books begin at `booksFrom(start:)`.
    public static func pile(for client: TownClient, month: MonthKey, start: MonthKey, state: ClientState, pool: Set<String>) -> [String] {
        let from = state.booksFrom(start: start)
        let i = (month.year - from.year) * 12 + (month.month - from.month)
        let size = TownRules.bilagPerMonth
        guard i >= 0, i * size < client.oppgaver.count else { return [] }
        let slice = client.oppgaver[(i * size)..<min((i + 1) * size, client.oppgaver.count)]
        let booked = Set(state.booked.map(\.puzzleId))
        return slice.filter { pool.contains($0) && !booked.contains($0) }
    }

    /// The oldest month, from the client's books start through the month of `today`, that still has bilag to book.
    public static func pileMonth(for client: TownClient, start: MonthKey, today: DayKey, state: ClientState, pool: Set<String>) -> MonthKey? {
        let last = MonthKey(today)
        var month = state.booksFrom(start: start)
        while month <= last {
            if !pile(for: client, month: month, start: start, state: state, pool: pool).isEmpty { return month }
            month = month.next
        }
        return nil
    }

    public static func canClose(_ month: MonthKey, client: TownClient, start: MonthKey, state: ClientState, today: DayKey, pool: Set<String>) -> Bool {
        today >= month.next.first && pile(for: client, month: month, start: start, state: state, pool: pool).isEmpty
    }
}
