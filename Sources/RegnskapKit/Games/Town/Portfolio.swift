import Foundation

public enum ClientStatus: String, Codable, Sendable {
    /// `parked`: put away by the player in the archive. `archived`: the client quit.
    case prospect, active, parked, archived
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
    /// The customer cases from people in town that are answered. Once only, right or wrong.
    public var casesDone: Set<String>

    public init(status: ClientStatus, satisfaction: Int, met: Bool, booked: [BookedBilag] = [], openErrors: [OpenError] = [],
                closedMonths: Set<MonthKey> = [], delivered: Set<String> = [], missed: Set<String> = [], activeFrom: DayKey? = nil, casesDone: Set<String> = []) {
        self.status = status
        self.satisfaction = satisfaction
        self.met = met
        self.booked = booked
        self.openErrors = openErrors
        self.closedMonths = closedMonths
        self.delivered = delivered
        self.missed = missed
        self.activeFrom = activeFrom
        self.casesDone = casesDone
    }

    private enum CodingKeys: String, CodingKey {
        case status, satisfaction, met, booked, openErrors, closedMonths, delivered, missed, activeFrom, casesDone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(ClientStatus.self, forKey: .status)
        satisfaction = try c.decode(Int.self, forKey: .satisfaction)
        met = try c.decode(Bool.self, forKey: .met)
        booked = try c.decode([BookedBilag].self, forKey: .booked)
        openErrors = try c.decode([OpenError].self, forKey: .openErrors)
        closedMonths = try c.decode(Set<MonthKey>.self, forKey: .closedMonths)
        delivered = try c.decode(Set<String>.self, forKey: .delivered)
        missed = try c.decode(Set<String>.self, forKey: .missed)
        activeFrom = try c.decodeIfPresent(DayKey.self, forKey: .activeFrom)
        // Saves from before customer cases have none done.
        casesDone = try c.decodeIfPresent(Set<String>.self, forKey: .casesDone) ?? []
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

    /// Whether the client can go to the archive: no open error, every booked month closed, so no
    /// verdict is left to reveal (Review Focus 4), and every ended month closed, so a park and an
    /// unpark cannot close a month the player never kept.
    public func canPark(start: MonthKey, today: DayKey) -> Bool {
        openErrors.isEmpty && booked.allSatisfy { closedMonths.contains($0.month) }
            && firstOpenMonth(start: start, today: today) == nil
    }

    /// The earliest month from the client's books start that has ended and is not closed.
    public func firstOpenMonth(start: MonthKey, today: DayKey) -> MonthKey? {
        var month = booksFrom(start: start)
        while month < MonthKey(today) {
            if !closedMonths.contains(month) { return month }
            month = month.next
        }
        return nil
    }

    /// The client is back (taken from the archive, or won back after it quit) from `day`. The months
    /// away are closed: the player did not keep the books then. A month with bilag stays as it is.
    public mutating func rejoin(on day: DayKey, start: MonthKey) {
        status = .active
        activeFrom = day
        satisfaction = max(satisfaction, TownRules.startSatisfaction)
        let withBilag = Set(booked.map(\.month))
        var month = booksFrom(start: start)
        while month < MonthKey(day) {
            if !withBilag.contains(month) { closedMonths.insert(month) }
            month = month.next
        }
    }

    /// `client` is the client id; the state does not know its own id, so the caller passes it.
    public mutating func book(_ bilag: BookedBilag, boxBefore: Int, client: String) {
        var bilag = bilag
        bilag.boxBefore = boxBefore
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

    /// Records a customer case as done; a right answer pleases the client.
    public mutating func answerCase(_ puzzle: String, ok: Bool) {
        casesDone.insert(puzzle)
        if ok { adjustSatisfaction(by: TownRules.caseBonus) }
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
    /// Returns the booking damage that falls due by this close, per topic (`bookingDamage`); empty
    /// when the month stays open or was closed already, so no damage is ever paid twice.
    @discardableResult
    public mutating func closeIfClean(_ month: MonthKey, pool: Set<String>? = nil, tema: (String) -> String? = { _ in nil }) -> [String: Int] {
        guard !closedMonths.contains(month), errors(in: month, pool: pool).isEmpty else { return [:] }
        openErrors.removeAll { $0.month == month }
        closedMonths.insert(month)
        return bookingDamage(in: month, tema: tema)
    }

    /// The damage the month's bookings earned, per topic of their puzzle (`tema` looks it up; a
    /// puzzle without one is left out). A wrong booking earned none.
    public func bookingDamage(in month: MonthKey, tema: (String) -> String?) -> [String: Int] {
        var out: [String: Int] = [:]
        for bilag in booked where bilag.month == month && bilag.damage > 0 {
            guard let topic = tema(bilag.puzzleId) else { continue }
            out[topic, default: 0] += bilag.damage
        }
        return out
    }

    /// Whether the deadline falls on or after the day the client was won.
    public func covers(_ deadline: TownDeadline) -> Bool {
        activeFrom.map { deadline.day >= $0 } ?? true
    }

    /// The month the client's books start: the month it was won, never before the game's start.
    /// A save from phase 2a may hold bookings on earlier months (its piles began at the game's
    /// start), so the earliest booked month moves the start back and those bookings stay the player's.
    public func booksFrom(start: MonthKey) -> MonthKey {
        guard let activeFrom else { return start }
        let won = MonthKey(activeFrom)
        let first = booked.map(\.month).min().map { min(won, $0) } ?? won
        return max(start, first)
    }

    /// Whether every month a deadline reports on is closed, so it can be delivered. Months before
    /// `booksFrom` count as closed: the previous accountant kept them, and the player is never
    /// offered them, so a client won mid-term can still deliver the term.
    public func hasClosed(_ months: [MonthKey], start: MonthKey) -> Bool {
        let from = booksFrom(start: start)
        return months.filter { $0 >= from }.allSatisfy(closedMonths.contains)
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
