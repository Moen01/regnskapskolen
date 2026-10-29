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

    public init(mapId: String, walker: TownWalker, calendar: TownCalendar, start: MonthKey, clients: [String: ClientState], contracts: Int) {
        self.mapId = mapId
        self.walker = walker
        self.calendar = calendar
        self.start = start
        self.clients = clients
        self.contracts = contracts
    }

    /// A new game: the player stands in front of the boss in `kontoret` on 1 January of `year`.
    /// Validated content always has that map and a boss; if it does not, fall back to (0, 0) on the
    /// first map instead of crashing, so a broken content folder cannot take the app down.
    public static func new(content: TownContent, year: Int) -> TownState {
        let office = content.map("kontoret") ?? content.kart.first
        let boss = office?.folk.first { $0.rolle == .sjef }
        let walker = TownWalker(x: boss?.x ?? 0, y: boss.map { $0.y + 1 } ?? 0, facing: .up)
        let first = DayKey(year: year, month: 1, day: 1)
        var clients: [String: ClientState] = [:]
        for client in content.klienter {
            clients[client.id] = .fresh(client.startklient ? .active : .prospect)
        }
        return TownState(mapId: office?.id ?? "kontoret", walker: walker, calendar: TownCalendar(start: first),
                         start: MonthKey(first), clients: clients, contracts: TownRules.startContracts)
    }

    /// The box the puzzle had before its oldest open error, so the collection does not give the error away.
    public func maskedBox(_ puzzleId: String) -> Int? {
        clients.values
            .flatMap(\.openErrors)
            .filter { $0.puzzleId == puzzleId }
            .min { $0.day < $1.day }?
            .boxBefore
    }
}
