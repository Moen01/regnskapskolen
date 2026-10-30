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
    /// Like `payrollFrom`, for the annual deadlines (skattemelding, årsregnskap). A save without the
    /// field gets the day it is opened, so a deadline already past does not go missed in that moment.
    public var annualFrom: DayKey?
    /// Spent by every encounter; at 0 the player collapses (`collapse`). The bed fills it.
    public var energy: Int = TownRules.maxEnergy
    /// Cups in the bag, taken from the office machine, one per day.
    public var coffee: Int = 0
    public var coffeeTakenOn: DayKey?
    /// Ids of the rule cards the player won from fagkontor. They belong to the player, not to a client.
    public var regelkort: Set<String> = []
    /// Ids of the districts whose gate is open (`TownMap.fullmakt`). They belong to the player, and nothing takes them back.
    public var fullmakter: Set<String> = []
    /// Ids of the `funn` people the player has already taken a card from.
    public var found: Set<String> = []
    /// The rule card that counts in the next battle only, like a TM.
    public var equippedCard: String?
    /// Ids of the sandbox cases that have given their credit. They belong to the player.
    public var sandboxCleared: Set<String> = []
    /// Years whose bokettersyn the player has passed.
    public var revidert: Set<Int> = []
    /// The day of the last audit attempt: one attempt per day, and quitting mid-audit counts.
    public var auditTriedOn: DayKey?
    /// Errors found since `takeDiscoveries` was last called. Not part of the save.
    var newlyDiscovered: [OpenError] = []

    public init(mapId: String, walker: TownWalker, calendar: TownCalendar, start: MonthKey, clients: [String: ClientState], contracts: Int,
                payrollFrom: DayKey? = nil, annualFrom: DayKey? = nil, energy: Int = TownRules.maxEnergy, coffee: Int = 0, coffeeTakenOn: DayKey? = nil, regelkort: Set<String> = [], fullmakter: Set<String> = [], found: Set<String> = [], equippedCard: String? = nil, sandboxCleared: Set<String> = [], revidert: Set<Int> = [], auditTriedOn: DayKey? = nil) {
        self.mapId = mapId
        self.walker = walker
        self.calendar = calendar
        self.start = start
        self.clients = clients
        self.contracts = contracts
        self.payrollFrom = payrollFrom
        self.annualFrom = annualFrom
        self.energy = energy
        self.coffee = coffee
        self.coffeeTakenOn = coffeeTakenOn
        self.regelkort = regelkort
        self.fullmakter = fullmakter
        self.found = found
        self.equippedCard = equippedCard
        self.sandboxCleared = sandboxCleared
        self.revidert = revidert
        self.auditTriedOn = auditTriedOn
    }

    private enum CodingKeys: String, CodingKey { case mapId, walker, calendar, start, clients, contracts, payrollFrom, annualFrom, energy, coffee, coffeeTakenOn, regelkort, fullmakter, found, equippedCard, sandboxCleared, revidert, auditTriedOn }

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
        annualFrom = c.contains(.annualFrom) ? try c.decodeIfPresent(DayKey.self, forKey: .annualFrom) : calendar.today
        energy = try c.decodeIfPresent(Int.self, forKey: .energy) ?? TownRules.maxEnergy
        coffee = try c.decodeIfPresent(Int.self, forKey: .coffee) ?? 0
        coffeeTakenOn = try c.decodeIfPresent(DayKey.self, forKey: .coffeeTakenOn)
        regelkort = try c.decodeIfPresent(Set<String>.self, forKey: .regelkort) ?? []
        fullmakter = try c.decodeIfPresent(Set<String>.self, forKey: .fullmakter) ?? []
        found = try c.decodeIfPresent(Set<String>.self, forKey: .found) ?? []
        equippedCard = try c.decodeIfPresent(String.self, forKey: .equippedCard)
        sandboxCleared = try c.decodeIfPresent(Set<String>.self, forKey: .sandboxCleared) ?? []
        revidert = try c.decodeIfPresent(Set<Int>.self, forKey: .revidert) ?? []
        auditTriedOn = try c.decodeIfPresent(DayKey.self, forKey: .auditTriedOn)
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
        try c.encode(annualFrom, forKey: .annualFrom)
        try c.encode(energy, forKey: .energy)
        try c.encode(coffee, forKey: .coffee)
        try c.encodeIfPresent(coffeeTakenOn, forKey: .coffeeTakenOn)
        try c.encode(regelkort, forKey: .regelkort)
        try c.encode(fullmakter, forKey: .fullmakter)
        try c.encode(found, forKey: .found)
        try c.encodeIfPresent(equippedCard, forKey: .equippedCard)
        try c.encode(sandboxCleared, forKey: .sandboxCleared)
        try c.encode(revidert, forKey: .revidert)
        try c.encodeIfPresent(auditTriedOn, forKey: .auditTriedOn)
    }

    /// The equipped card for one battle: returns it and clears it, so it never carries over.
    public mutating func takeEquippedCard() -> String? {
        defer { equippedCard = nil }
        return equippedCard
    }

    /// A battle's own cards with the equipped card added once, so its moves count in this battle.
    public func ownCards(_ own: [RuleCard], all: [RuleCard]) -> [RuleCard] {
        guard let id = equippedCard, !own.contains(where: { $0.id == id }), let card = all.first(where: { $0.id == id }) else { return own }
        return own + [card]
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

    /// A fagkontor badge was won: one more contract and the rule cards of its topics the player does
    /// not have yet. Returns the new cards so the app can tell about them. The badge itself is set by the app.
    @discardableResult
    public mutating func winFagkontor(_ ref: FagkontorRef, cards: [RuleCard]) -> [RuleCard] {
        contracts += TownRules.contractsPerBadge
        let fresh = cards.filter { ref.temaer.contains($0.tema) && !regelkort.contains($0.id) }
        regelkort.formUnion(fresh.map(\.id))
        return fresh
    }

    /// Gives the topic cards of every fagkontor badge the player holds, for a save whose badges were
    /// won before badges gave cards. No contract: the badge paid that when it was won. Returns the new cards.
    @discardableResult
    public mutating func backfillCards(badges: Set<String>, content: TownContent, cards: [RuleCard]) -> [RuleCard] {
        let temaer = Set(content.kart.flatMap(\.folk).compactMap(\.fagkontor)
            .filter { badges.contains(TownTrials.badgeKey($0)) }
            .flatMap(\.temaer))
        let fresh = cards.filter { temaer.contains($0.tema) && !regelkort.contains($0.id) }
        regelkort.formUnion(fresh.map(\.id))
        return fresh
    }

    /// Adds the permits the badges earn (`TownDistricts.earned`) and returns the districts that are new.
    /// Never removes one: a permit stays even when a later call has fewer badges.
    @discardableResult
    public mutating func grantFullmakter(content: TownContent, badges: Set<String>, regions: [Region]) -> [TownDistrict] {
        let earned = TownDistricts.earned(content: content, badges: badges, regions: regions)
        let fresh = TownDistricts.all(in: content).filter { district in
            district.fullmakt.map { earned.contains($0) && !fullmakter.contains($0) } ?? false
        }
        fullmakter.formUnion(earned)
        return fresh
    }

    /// Moves the player to the office when the map is a district the player has no permit for, for
    /// instance in a save whose content changed. Returns whether the player was moved.
    @discardableResult
    public mutating func relocateIfLocked(content: TownContent) -> Bool {
        guard !TownDistricts.isOpen(mapId, content: content, fullmakter: fullmakter) else { return false }
        (mapId, walker) = Self.officeSpot(content)
        return true
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
    /// A client that quit is skipped: the verdict is no secret any more.
    private var heldBack: [(puzzleId: String, day: DayKey, box: Int)] {
        clients.values.filter { $0.status != .archived }.flatMap { client in
            client.openErrors.map { ($0.puzzleId, $0.day, $0.boxBefore) }
                + client.booked.compactMap { bilag in
                    guard let box = bilag.boxBefore, !client.closedMonths.contains(bilag.month) else { return nil }
                    return (bilag.puzzleId, bilag.day, box)
                }
        }
    }

    /// A copy of the progress where every puzzle with a held-back verdict sits in the box it had
    /// before the booking and with no `due` day, so region counts, totals and the order of the
    /// creatures do not tell whether a bilag was right (a wrong answer is due tomorrow).
    /// A puzzle with no entry stays without one when that box is 0: it reads as uncaught, as before.
    public func masked(_ progress: LearnerProgress) -> LearnerProgress {
        var result = progress
        for id in Set(heldBack.map(\.puzzleId)) {
            guard let box = maskedBox(id) else { continue }
            defer { result.puzzles[id]?.due = nil }
            if result.puzzles[id] != nil {
                result.puzzles[id]?.box = box
            } else if box > 0 {
                result.puzzles[id] = PuzzleProgress(box: box)
            }
        }
        return result
    }

    /// Whether the deadline counts for the client: it falls on or after the day the client was won
    /// for a year no earlier than the game's start and, for payroll and annual deadlines, on or after `payrollFrom` and `annualFrom`. The counter, Fristnav, missed deadlines and the
    /// sleep stops all ask this one question.
    public func counts(_ deadline: TownDeadline, client: ClientState) -> Bool {
        guard client.covers(deadline), deadline.kind.year >= start.year else { return false }
        if deadline.kind.isAnnual { return annualFrom.map { deadline.day >= $0 } ?? true }
        if deadline.kind.isPayroll { return payrollFrom.map { deadline.day >= $0 } ?? true }
        return true
    }
}

extension DeadlineKind {
    var isPayroll: Bool {
        switch self {
        case .amelding, .forskuddstrekk, .aga: true
        case .mva, .mvaAarlig, .skattemelding, .aarsregnskap: false
        }
    }

    var isAnnual: Bool {
        switch self {
        case .skattemelding, .aarsregnskap: true
        case .mva, .mvaAarlig, .amelding, .forskuddstrekk, .aga: false
        }
    }
}
