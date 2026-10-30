import Foundation

public struct BookedBilag: Hashable, Codable, Sendable {
    public let puzzleId: String
    public let month: MonthKey
    public let day: DayKey
    public let correct: Bool
    /// The topic damage the booking earned. Held back until the month closes: added at once, the
    /// gym count would tell whether the bilag was right. Saves from before the field read as 0.
    public let damage: Int
    /// The puzzle's box before the booking, set by `ClientState.book`. `TownState.masked` shows it
    /// until the month closes, right or wrong: a right booking moves the box too. Saves from before
    /// the field read as `nil`, and such a booking is not masked.
    public var boxBefore: Int?

    public init(puzzleId: String, month: MonthKey, day: DayKey, correct: Bool, damage: Int = 0, boxBefore: Int? = nil) {
        self.puzzleId = puzzleId
        self.month = month
        self.day = day
        self.correct = correct
        self.damage = damage
        self.boxBefore = boxBefore
    }

    private enum CodingKeys: String, CodingKey { case puzzleId, month, day, correct, damage, boxBefore }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        puzzleId = try c.decode(String.self, forKey: .puzzleId)
        month = try c.decode(MonthKey.self, forKey: .month)
        day = try c.decode(DayKey.self, forKey: .day)
        correct = try c.decode(Bool.self, forKey: .correct)
        damage = try c.decodeIfPresent(Int.self, forKey: .damage) ?? 0
        boxBefore = try c.decodeIfPresent(Int.self, forKey: .boxBefore)
    }
}

/// A wrong booking that comes back when the month is closed.
public struct OpenError: Hashable, Codable, Sendable, Identifiable {
    public let puzzleId: String
    public let client: String
    public let month: MonthKey
    public let day: DayKey
    public let boxBefore: Int
    /// Set when the client finds the error itself (`TownState.discover`). Saves from before the
    /// field read as `false`.
    public var discovered: Bool

    public init(puzzleId: String, client: String, month: MonthKey, day: DayKey, boxBefore: Int, discovered: Bool = false) {
        self.puzzleId = puzzleId
        self.client = client
        self.month = month
        self.day = day
        self.boxBefore = boxBefore
        self.discovered = discovered
    }

    private enum CodingKeys: String, CodingKey { case puzzleId, client, month, day, boxBefore, discovered }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        puzzleId = try c.decode(String.self, forKey: .puzzleId)
        client = try c.decode(String.self, forKey: .client)
        month = try c.decode(MonthKey.self, forKey: .month)
        day = try c.decode(DayKey.self, forKey: .day)
        boxBefore = try c.decode(Int.self, forKey: .boxBefore)
        discovered = try c.decodeIfPresent(Bool.self, forKey: .discovered) ?? false
    }

    public var id: String { "\(client):\(puzzleId):\(day.string)" }
}

public enum Ledger {
    /// The month's bilag still to book. The monthly slice is cut from the whole list *before* the
    /// pool filter, so a month keeps its content when "show drafts" is switched on and off.
    /// `start` is the game's first month; the client's own books begin at `booksFrom(start:)`.
    public static func pile(for client: TownClient, month: MonthKey, start: MonthKey, state: ClientState, pool: Set<String>) -> [String] {
        // The piles start again every January: a new accounting year begins with the first slice,
        // and only bookings from that year count as booked.
        let from = max(state.booksFrom(start: start), MonthKey(year: month.year, month: 1))
        let i = (month.year - from.year) * 12 + (month.month - from.month)
        let size = TownRules.bilagPerMonth
        guard i >= 0, i * size < client.oppgaver.count else { return [] }
        let slice = client.oppgaver[(i * size)..<min((i + 1) * size, client.oppgaver.count)]
        let booked = Set(state.booked.filter { $0.month.year == month.year }.map(\.puzzleId))
        return slice.filter { pool.contains($0) && !booked.contains($0) }
    }

    /// The oldest month, from the client's books start through the month of `today`, that still has bilag to book.
    public static func pileMonth(for client: TownClient, start: MonthKey, today: DayKey, state: ClientState, pool: Set<String>) -> MonthKey? {
        let last = MonthKey(today)
        var month = state.booksFrom(start: start)
        while month <= last {
            if !state.closedMonths.contains(month), !pile(for: client, month: month, start: start, state: state, pool: pool).isEmpty { return month }
            month = month.next
        }
        return nil
    }

    /// A month before the client's books start is never the player's to close.
    public static func canClose(_ month: MonthKey, client: TownClient, start: MonthKey, state: ClientState, today: DayKey, pool: Set<String>) -> Bool {
        month >= state.booksFrom(start: start) && today >= month.next.first
            && pile(for: client, month: month, start: start, state: state, pool: pool).isEmpty
    }
}
