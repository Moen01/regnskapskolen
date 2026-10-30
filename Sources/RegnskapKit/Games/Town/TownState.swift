import Foundation

/// The town's whole saved state. Stored as `GameProgress.town`; `nil` there means no town game started yet.
/// A bilag run in progress is deliberately not part of it: closing the app mid-run drops the run.
public struct TownState: Hashable, Codable, Sendable {
    public var mapId: String
    public var walker: TownWalker
    public var calendar: TownCalendar
    /// The first month of the game; `Ledger.pile` counts monthly slices from here.
    public var start: MonthKey
    /// Client id → state.
    public var clients: [String: ClientState]
    public var contracts: Int
    /// Payroll deadlines due before this day do not count. `nil` in a new game: payroll counts from
    /// the start. A save from phase 2a has no such field and gets the day it is opened, so the
    /// payroll deadlines of the months before do not all go missed in that moment.
    public var payrollFrom: DayKey?
    /// Spent by every encounter; at 0 the player collapses (`collapse`). The bed fills it.
    public var energy: Int = TownRules.maxEnergy
    /// Cups in the bag, taken from the office machine, one per day.
    public var coffee: Int = 0
    public var coffeeTakenOn: DayKey?
    /// Errors found since `takeDiscoveries` was last called. Not part of the save.
    var newlyDiscovered: [OpenError] = []

    public init(mapId: String, walker: TownWalker, calendar: TownCalendar, start: MonthKey, clients: [String: ClientState], contracts: Int,
                payrollFrom: DayKey? = nil, energy: Int = TownRules.maxEnergy, coffee: Int = 0, coffeeTakenOn: DayKey? = nil) {
        self.mapId = mapId
        self.walker = walker
        self.calendar = calendar
        self.start = start
        self.clients = clients
        self.contracts = contracts
        self.payrollFrom = payrollFrom
        self.energy = energy
        self.coffee = coffee
        self.coffeeTakenOn = coffeeTakenOn
    }

    private enum CodingKeys: String, CodingKey { case mapId, walker, calendar, start, clients, contracts, payrollFrom, energy, coffee, coffeeTakenOn }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mapId = try c.decode(String.self, forKey: .mapId)
        walker = try c.decode(TownWalker.self, forKey: .walker)
        calendar = try c.decode(TownCalendar.self, forKey: .calendar)
        start = try c.decode(MonthKey.self, forKey: .start)
        clients = try c.decode([String: ClientState].self, forKey: .clients)
        contracts = try c.decode(Int.self, forKey: .contracts)
        // `nil` is written as an explicit null, so only a missing key (a 2a save) means "from today".
        payrollFrom = c.contains(.payrollFrom) ? try c.decodeIfPresent(DayKey.self, forKey: .payrollFrom) : calendar.today
        energy = try c.decodeIfPresent(Int.self, forKey: .energy) ?? TownRules.maxEnergy
        coffee = try c.decodeIfPresent(Int.self, forKey: .coffee) ?? 0
        coffeeTakenOn = try c.decodeIfPresent(DayKey.self, forKey: .coffeeTakenOn)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mapId, forKey: .mapId)
        try c.encode(walker, forKey: .walker)
        try c.encode(calendar, forKey: .calendar)
        try c.encode(start, forKey: .start)
        try c.encode(clients, forKey: .clients)
        try c.encode(contracts, forKey: .contracts)
        try c.encode(payrollFrom, forKey: .payrollFrom)
        try c.encode(energy, forKey: .energy)
        try c.encode(coffee, forKey: .coffee)
        try c.encodeIfPresent(coffeeTakenOn, forKey: .coffeeTakenOn)
    }

    /// A new game: the player stands in front of the boss in `kontoret` on 1 January of `year`.
    /// Validated content always has that map and a boss; if it does not, fall back to (0, 0) on the
    /// first map instead of crashing, so a broken content folder cannot take the app down.
    public static func new(content: TownContent, year: Int) -> TownState {
        let (mapId, walker) = officeSpot(content)
        let first = DayKey(year: year, month: 1, day: 1)
        var clients: [String: ClientState] = [:]
        for client in content.klienter {
            clients[client.id] = .fresh(client.startklient ? .active : .prospect)
        }
        return TownState(mapId: mapId, walker: walker, calendar: TownCalendar(start: first),
                         start: MonthKey(first), clients: clients, contracts: TownRules.startContracts)
    }

    /// The office and the square in front of the boss: where a new game starts and where a collapse ends.
    static func officeSpot(_ content: TownContent) -> (mapId: String, walker: TownWalker) {
        let office = content.map("kontoret") ?? content.kart.first
        let boss = office?.folk.first { $0.rolle == .sjef }
        return (office?.id ?? "kontoret", TownWalker(x: boss?.x ?? 0, y: boss.map { $0.y + 1 } ?? 0, facing: .up))
    }

    /// The box the puzzle had before its oldest held-back verdict: an open error, or a booking in a
    /// month that is not closed yet. Right bookings count too (spec Mål 7): a right answer moves the
    /// box as well, so masking only the wrong ones would give the verdict away. A booking saved
    /// before `BookedBilag.boxBefore` existed has no box to show and is left out.
    public func maskedBox(_ puzzleId: String) -> Int? {
        heldBack.filter { $0.puzzleId == puzzleId }.min { $0.day < $1.day }?.box
    }

    /// Every booking whose verdict the town still holds back, with the box from before it.
    private var heldBack: [(puzzleId: String, day: DayKey, box: Int)] {
        clients.values.flatMap { client in
            client.openErrors.map { ($0.puzzleId, $0.day, $0.boxBefore) }
                + client.booked.compactMap { bilag in
                    guard let box = bilag.boxBefore, !client.closedMonths.contains(bilag.month) else { return nil }
                    return (bilag.puzzleId, bilag.day, box)
                }
        }
    }

    /// A copy of the progress where every puzzle with a held-back verdict sits in the box it had
    /// before the booking, so region counts and totals do not tell whether a bilag was right.
    /// A puzzle with no entry stays without one when that box is 0: it reads as uncaught, as before.
    public func masked(_ progress: LearnerProgress) -> LearnerProgress {
        var result = progress
        for id in Set(heldBack.map(\.puzzleId)) {
            guard let box = maskedBox(id) else { continue }
            if result.puzzles[id] != nil {
                result.puzzles[id]?.box = box
            } else if box > 0 {
                result.puzzles[id] = PuzzleProgress(box: box)
            }
        }
        return result
    }

    /// Whether the deadline counts for the client: it falls on or after the day the client was won
    /// and, for payroll, on or after `payrollFrom`. The counter, Fristnav, missed deadlines and the
    /// sleep stops all ask this one question.
    public func counts(_ deadline: TownDeadline, client: ClientState) -> Bool {
        guard client.covers(deadline) else { return false }
        guard deadline.kind.isPayroll, let from = payrollFrom else { return true }
        return deadline.day >= from
    }
}

extension DeadlineKind {
    var isPayroll: Bool {
        switch self {
        case .amelding, .forskuddstrekk, .aga: true
        case .mva, .mvaAarlig: false
        }
    }
}
