import Foundation

/// The town's clock. It only moves when the player acts or sleeps; there is no real time in here.
public struct TownCalendar: Hashable, Codable, Sendable {
    public private(set) var today: DayKey
    public private(set) var actionsToday: Int

    public init(start: DayKey) {
        today = start
        actionsToday = 0
    }

    /// Spends one action. Returns true when it was the last one of the day and a new day started.
    @discardableResult
    public mutating func act() -> Bool {
        actionsToday += 1
        guard actionsToday >= TownRules.actionsPerDay else { return false }
        advance(to: today.adding(days: 1))
        return true
    }

    /// Jumps to the earliest event after today, or to tomorrow when there is none.
    public mutating func sleep(events: [DayKey]) {
        advance(to: events.filter { $0 > today }.min() ?? today.adding(days: 1))
    }

    private mutating func advance(to day: DayKey) {
        today = day
        actionsToday = 0
    }
}
