import Foundation

public enum ClientStatus: String, Codable, Sendable {
    case prospect, active, archived
}

public struct ClientState: Hashable, Codable, Sendable {
    public var status: ClientStatus
    public var satisfaction: Int
    public var met: Bool
    public var booked: [BookedBilag]
    public var openErrors: [OpenError]
    public var closedMonths: Set<MonthKey>
    public var delivered: Set<String>
    public var missed: Set<String>
    /// The day the client was won. Deadlines due before it are not the player's: a client won in
    /// April cannot have missed the term due in March. `nil` (the start client, saves from before
    /// the field) covers every deadline. Optional, so the synthesized decoder reads old saves.
    public var activeFrom: DayKey?

    public init(status: ClientStatus, satisfaction: Int, met: Bool, booked: [BookedBilag] = [], openErrors: [OpenError] = [],
                closedMonths: Set<MonthKey> = [], delivered: Set<String> = [], missed: Set<String> = [], activeFrom: DayKey? = nil) {
        self.status = status
        self.satisfaction = satisfaction
        self.met = met
        self.booked = booked
        self.openErrors = openErrors
        self.closedMonths = closedMonths
        self.delivered = delivered
        self.missed = missed
        self.activeFrom = activeFrom
    }
}

extension ClientState {
    public static func fresh(_ status: ClientStatus) -> ClientState {
        ClientState(status: status, satisfaction: TownRules.startSatisfaction, met: false)
    }

    private mutating func adjustSatisfaction(by delta: Int) {
        satisfaction = min(TownRules.maxSatisfaction, max(0, satisfaction + delta))
        if satisfaction == 0 { status = .archived }
    }

    /// `client` is the client id; the state does not know its own id, so the caller passes it.
    public mutating func book(_ bilag: BookedBilag, boxBefore: Int, client: String) {
        booked.append(bilag)
        guard !bilag.correct else { return }
        openErrors.append(OpenError(puzzleId: bilag.puzzleId, client: client, month: bilag.month, day: bilag.day, boxBefore: boxBefore))
    }

    /// The month's open errors; with `pool`, only those whose puzzle is visible, since a hidden
    /// draft can never be shown as a correction.
    public func errors(in month: MonthKey, pool: Set<String>? = nil) -> [OpenError] {
        openErrors.filter { $0.month == month && pool?.contains($0.puzzleId) != false }
    }

    /// The errors the client found itself, on puzzles the player can see.
    public func discoveredErrors(pool: Set<String>) -> [OpenError] {
        openErrors.filter { $0.discovered && pool.contains($0.puzzleId) }
    }

    /// Marks the error as found and costs satisfaction. Nothing happens for an error that is gone or already found.
    public mutating func discover(_ error: OpenError) {
        guard let i = openErrors.firstIndex(where: { $0.id == error.id && !$0.discovered }) else { return }
        openErrors[i].discovered = true
        adjustSatisfaction(by: TownRules.discoveredPenalty)
    }

    public mutating func correct(_ error: OpenError, ok: Bool) {
        if ok {
            // By id: the caller's copy may have been taken before the client found the error.
            openErrors.removeAll { $0.id == error.id }
        } else {
            adjustSatisfaction(by: TownRules.correctionMiss)
        }
    }

    /// Closes the month when no error is left. With `pool`, errors on hidden puzzles do not block
    /// it (Review Focus 1: otherwise the month could never close); they are dropped with the close,
    /// because a closed month is never corrected again.
    public mutating func closeIfClean(_ month: MonthKey, pool: Set<String>? = nil) {
        guard errors(in: month, pool: pool).isEmpty else { return }
        openErrors.removeAll { $0.month == month }
        closedMonths.insert(month)
    }

    /// Whether the deadline falls on or after the day the client was won.
    public func covers(_ deadline: TownDeadline) -> Bool {
        activeFrom.map { deadline.day >= $0 } ?? true
    }

    /// The month the client's books start: the month it was won, never before the game's start.
    public func booksFrom(start: MonthKey) -> MonthKey {
        guard let activeFrom else { return start }
        return max(start, MonthKey(activeFrom))
    }

    public mutating func deliver(_ kind: DeadlineKind) {
        delivered.insert(kind.id)
        adjustSatisfaction(by: TownRules.deliverBonus)
    }

    /// `deadlines` must be this client's deadlines only; the state does not know its own id.
    /// A deadline is missed from the day after it falls due. Returns the newly missed ones.
    public mutating func checkMissed(_ deadlines: [TownDeadline], today: DayKey) -> [TownDeadline] {
        var newly: [TownDeadline] = []
        for d in deadlines where d.day < today && covers(d) && !delivered.contains(d.kind.id) && !missed.contains(d.kind.id) {
            missed.insert(d.kind.id)
            adjustSatisfaction(by: TownRules.missedDeadline)
            newly.append(d)
        }
        return newly
    }
}
