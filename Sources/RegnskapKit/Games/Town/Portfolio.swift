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

    public init(status: ClientStatus, satisfaction: Int, met: Bool, booked: [BookedBilag] = [], openErrors: [OpenError] = [],
                closedMonths: Set<MonthKey> = [], delivered: Set<String> = [], missed: Set<String> = []) {
        self.status = status
        self.satisfaction = satisfaction
        self.met = met
        self.booked = booked
        self.openErrors = openErrors
        self.closedMonths = closedMonths
        self.delivered = delivered
        self.missed = missed
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

    public func errors(in month: MonthKey) -> [OpenError] {
        openErrors.filter { $0.month == month }
    }

    public mutating func correct(_ error: OpenError, ok: Bool) {
        if ok {
            openErrors.removeAll { $0 == error }
        } else {
            adjustSatisfaction(by: TownRules.correctionMiss)
        }
    }

    public mutating func closeIfClean(_ month: MonthKey) {
        guard errors(in: month).isEmpty else { return }
        closedMonths.insert(month)
    }

    public mutating func deliver(_ kind: DeadlineKind) {
        delivered.insert(kind.id)
        adjustSatisfaction(by: TownRules.deliverBonus)
    }

    /// `deadlines` must be this client's deadlines only; the state does not know its own id.
    /// A deadline is missed from the day after it falls due. Returns the newly missed ones.
    public mutating func checkMissed(_ deadlines: [TownDeadline], today: DayKey) -> [TownDeadline] {
        var newly: [TownDeadline] = []
        for d in deadlines where d.day < today && !delivered.contains(d.kind.id) && !missed.contains(d.kind.id) {
            missed.insert(d.kind.id)
            adjustSatisfaction(by: TownRules.missedDeadline)
            newly.append(d)
        }
        return newly
    }
}
