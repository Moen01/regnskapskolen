import Foundation

extension TownAction {
    /// Whether the action spends one of the day's actions. Walking, doors, saving and the menus are
    /// free. Sleeping is free too: it moves the calendar itself, and spending an action first could
    /// start the next day and make the sleep skip the event the player wanted to stop at.
    public var spendsAction: Bool {
        switch self {
        case .none, .walked, .enteredDoor, .save, .openTraining, .openCollection, .sleep: false
        case .startBilag, .startCorrection, .fixDiscovered, .startTrial, .startFagkontor, .startCase, .closedMonth, .deliver: true
        }
    }
}

/// How the town's calendar moves: one action at a time, or a sleep to the next event; on a new
/// day, the deadlines that went by are marked as missed.
extension TownState {
    /// The client's deadlines from the first year of the game through this year. Years before the
    /// start are left out: the game did not run then, so nothing could be missed. So are deadlines
    /// due before the client was won (`ClientState.activeFrom`).
    public func deadlines(for client: TownClient, deadlines: Deadlines) -> [TownDeadline] {
        (start.year...max(start.year, calendar.today.year))
            .flatMap { DeadlinePlanner.deadlines(for: client, year: $0, deadlines: deadlines) }
            .filter { d in clients[client.id].map { counts(d, client: $0) } ?? true }
    }

    /// Whether the portfolio has no room for one more active client.
    public var portfolioFull: Bool {
        clients.values.filter { $0.status == .active }.count >= TownRules.portfolioSize
    }

    /// Puts an active client with clean books in the archive.
    @discardableResult
    public mutating func park(_ client: String) -> Bool {
        guard clients[client]?.status == .active, clients[client]?.canPark == true else { return false }
        clients[client]?.status = .parked
        return true
    }

    /// Takes a parked client back when the portfolio has room.
    @discardableResult
    public mutating func unpark(_ client: String, on day: DayKey) -> Bool {
        guard clients[client]?.status == .parked, !portfolioFull else { return false }
        clients[client]?.rejoin(on: day, start: start)
        return true
    }

    /// A won trial: the client becomes active from `day` and uses one contract. A client that quit
    /// or sits in the archive rejoins, with the months away closed.
    public mutating func winTrial(client: String, on day: DayKey) {
        var state = clients[client] ?? .fresh(.prospect)
        switch state.status {
        case .archived, .parked:
            state.rejoin(on: day, start: start)
        case .prospect, .active:
            state.status = .active
            state.activeFrom = day
        }
        clients[client] = state
        contracts -= 1
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

    /// Spends one action. Call it *after* the action is done: spent first, the last action of a
    /// day would already see the next day (a delivery on the deadline marked missed, a bilag
    /// booked on the wrong date). On a new day, returns the deadlines that were missed.
    public mutating func spendAction(content: TownContent, deadlines: Deadlines, pool: Set<String>) -> [TownDeadline] {
        guard calendar.act() else { return [] }
        let missed = checkMissed(content: content, deadlines: deadlines)
        _ = discover(day: calendar.today, content: content, pool: pool)
        return missed
    }

    /// Delivers at the counter, then spends the action, so a delivery on the deadline day counts
    /// even when it is the day's last action. Returns the deadlines missed on a new day.
    public mutating func deliver(client: String, kind: DeadlineKind, content: TownContent, deadlines: Deadlines, pool: Set<String>) -> [TownDeadline] {
        clients[client]?.deliver(kind)
        return spendAction(content: content, deadlines: deadlines, pool: pool)
    }

    /// The days a sleep stops at: the first of next month and, for every active client, each
    /// deadline and the day `warnDaysBefore` days before it.
    public func sleepEvents(content: TownContent, deadlines: Deadlines) -> [DayKey] {
        let today = calendar.today
        var events = [MonthKey(today).next.first]
        for client in content.klienter where clients[client.id]?.status == .active {
            // Next year too, so a sleep in December still stops at the term due in February.
            for year in start.year...(today.year + 1) {
                for d in DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines) where clients[client.id].map({ counts(d, client: $0) }) ?? true {
                    events += [d.day, d.day.adding(days: -TownRules.warnDaysBefore)]
                }
            }
        }
        return events
    }

    /// One encounter's energy. Right and wrong cost the same, so the bar never tells the verdict.
    /// Returns true when the energy is now 0 and the player collapses.
    public mutating func spendEncounter() -> Bool {
        energy = max(0, energy - TownRules.energyPerEncounter)
        return energy == 0
    }

    /// The player runs out of energy: wakes at the office the next morning with full energy, and the
    /// new day is checked like any other. Returns the deadlines missed on the way.
    public mutating func collapse(content: TownContent, deadlines: Deadlines, pool: Set<String>) -> [TownDeadline] {
        let spot = Self.officeSpot(content)
        mapId = spot.mapId
        walker = spot.walker
        let tomorrow = calendar.today.adding(days: 1)
        calendar.sleep(events: [tomorrow])
        energy = TownRules.maxEnergy
        let missed = checkMissed(content: content, deadlines: deadlines)
        _ = discover(day: calendar.today, content: content, pool: pool)
        return missed
    }

    /// Sleeps to the next event and returns the deadlines that were missed on the way.
    /// Every day passed on the way gets its own roll for discovered errors.
    public mutating func sleep(content: TownContent, deadlines: Deadlines, pool: Set<String>) -> [TownDeadline] {
        let from = calendar.today
        calendar.sleep(events: sleepEvents(content: content, deadlines: deadlines))
        energy = TownRules.maxEnergy
        let missed = checkMissed(content: content, deadlines: deadlines)
        var day = from.adding(days: 1)
        while day <= calendar.today {
            _ = discover(day: day, content: content, pool: pool)
            day = day.adding(days: 1)
        }
        return missed
    }

    /// Lets the active clients find old errors on `day`: an error that is not found yet, is at least
    /// `discoverAfterDays` old and sits on a visible puzzle is found when its roll for the day hits.
    /// The roll depends only on the error and the day, so a day gives the same answer every time.
    /// The found errors are also kept for `takeDiscoveries`, so `spendAction` and `sleep` can tell them.
    @discardableResult
    public mutating func discover(day: DayKey, content: TownContent, pool: Set<String>) -> [(client: String, error: OpenError)] {
        var found: [(client: String, error: OpenError)] = []
        for client in content.klienter where clients[client.id]?.status == .active {
            for error in clients[client.id]?.openErrors ?? [] where !error.discovered && pool.contains(error.puzzleId) {
                guard DayKey.daysBetween(error.day, day) >= TownRules.discoverAfterDays, clients[client.id]?.status == .active else { continue }
                var generator = SplitMix64(seed: SpeciesName.fnv1a("\(error.id)|\(day.string)"))
                guard generator.next() % TownRules.discoverOneIn == 0 else { continue }
                clients[client.id]?.discover(error)
                var shown = error
                shown.discovered = true
                found.append((client.id, shown))
            }
        }
        newlyDiscovered += found.map(\.error)
        return found
    }

    /// The errors found since the last call, for the app to tell. Not saved: a message lost to a
    /// crash is no harm, the error itself stays found.
    public mutating func takeDiscoveries() -> [OpenError] {
        defer { newlyDiscovered = [] }
        return newlyDiscovered
    }
}

extension TownFlow {
    /// Shows a message from the app (a missed deadline, a trial result) as a dialog; A closes it.
    /// Only call it while walking: it replaces whatever list is open.
    public mutating func tell(_ texts: [String]) {
        say(texts)
    }

    /// What a client says when it finds an old error: its name and the task's title, then its own
    /// line. Never the answer: what was wrong is for the player to find at the counter.
    /// `title` looks up a puzzle's title; the id stands in when it has none.
    public static func discoveryTexts(_ found: [OpenError], content: TownContent, title: (String) -> String?) -> [String] {
        found.flatMap { error in
            let client = content.client(error.client)
            return ["\(client?.navn ?? error.client): \(title(error.puzzleId) ?? error.puzzleId)"] + (client?.replikker.oppdagetFeil ?? [])
        }
    }

    /// What a collapse tells before the deadlines it let pass: where and on which day the player woke.
    public static func collapseTexts(wokeOn day: DayKey) -> [String] {
        ["Du sovnet av utmattelse.", String(format: "Du våknet på kontoret %02d.%02d.", day.day, day.month)]
    }
}
