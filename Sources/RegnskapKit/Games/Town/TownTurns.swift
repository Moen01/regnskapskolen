import Foundation

extension TownAction {
    /// Whether the action spends one of the day's actions. Walking, doors, saving and the menus are
    /// free. Sleeping is free too: it moves the calendar itself, and spending an action first could
    /// start the next day and make the sleep skip the event the player wanted to stop at.
    public var spendsAction: Bool {
        switch self {
        case .none, .walked, .enteredDoor, .save, .openTraining, .openCollection, .sleep: false
        case .startBilag, .startCorrection, .startTrial, .startFagkontor, .deliver: true
        }
    }
}

/// How the town's calendar moves: one action at a time, or a sleep to the next event; on a new
/// day, the deadlines that went by are marked as missed.
extension TownState {
    /// The client's deadlines from the first year of the game through this year. Years before the
    /// start are left out: the game did not run then, so nothing could be missed.
    public func deadlines(for client: TownClient, deadlines: Deadlines) -> [TownDeadline] {
        (start.year...max(start.year, calendar.today.year)).flatMap { DeadlinePlanner.deadlines(for: client, year: $0, deadlines: deadlines) }
    }

    /// Marks every active client's passed deadlines as missed. Returns the newly missed ones.
    public mutating func checkMissed(content: TownContent, deadlines: Deadlines) -> [TownDeadline] {
        var newly: [TownDeadline] = []
        for client in content.klienter where clients[client.id]?.status == .active {
            let due = self.deadlines(for: client, deadlines: deadlines)
            newly += clients[client.id]?.checkMissed(due, today: calendar.today) ?? []
        }
        return newly
    }

    /// Spends one action. On a new day, returns the deadlines that were missed.
    public mutating func spendAction(content: TownContent, deadlines: Deadlines) -> [TownDeadline] {
        guard calendar.act() else { return [] }
        return checkMissed(content: content, deadlines: deadlines)
    }

    /// The days a sleep stops at: the first of next month and, for every active client, each
    /// deadline and the day `warnDaysBefore` days before it.
    public func sleepEvents(content: TownContent, deadlines: Deadlines) -> [DayKey] {
        let today = calendar.today
        var events = [MonthKey(today).next.first]
        for client in content.klienter where clients[client.id]?.status == .active {
            // Next year too, so a sleep in December still stops at the term due in February.
            for year in start.year...(today.year + 1) {
                for d in DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines) {
                    events += [d.day, d.day.adding(days: -TownRules.warnDaysBefore)]
                }
            }
        }
        return events
    }

    /// Sleeps to the next event and returns the deadlines that were missed on the way.
    public mutating func sleep(content: TownContent, deadlines: Deadlines) -> [TownDeadline] {
        calendar.sleep(events: sleepEvents(content: content, deadlines: deadlines))
        return checkMissed(content: content, deadlines: deadlines)
    }
}

extension TownFlow {
    /// Shows a message from the app (a missed deadline, a trial result) as a dialog; A closes it.
    /// Only call it while walking: it replaces whatever list is open.
    public mutating func tell(_ texts: [String]) {
        say(texts)
    }
}
