import Foundation

/// Fristnav, the portfolio and the counter: the lists the town opens, and the needs card.
extension TownFlow {
    static let monthAbbreviations = ["JAN", "FEB", "MAR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DES"]
    public static let monthNames = ["januar", "februar", "mars", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "desember"]

    /// The first word of the name in capitals ("Bakeren AS" → "BAKEREN"), so rows stay short.
    static func shortName(_ client: TownClient) -> String {
        client.navn.split(separator: " ").first.map { $0.uppercased() } ?? client.id.uppercased()
    }

    var today: DayKey { state.calendar.today }

    var activeClients: [TownClient] {
        content.klienter.filter { state.clients[$0.id]?.status == .active }
    }

    // MARK: Fristnav

    /// Deadlines in the next seven days for active clients, marked when few days are left.
    /// A delivered deadline is left out: there is nothing more to do for it.
    mutating func openFristnav() -> TownAction {
        let names = Dictionary(content.klienter.map { ($0.id, Self.shortName($0)) }, uniquingKeysWith: { first, _ in first })
        let rows = DeadlinePlanner.upcoming(clients: activeClients, from: today, days: 7, deadlines: deadlines)
            .filter { state.clients[$0.client]?.delivered.contains($0.kind.id) != true }
            .map { d in
                PanelRow.fitting(id: "\(d.client):\(d.kind.id)", "\(d.label) \(names[d.client] ?? d.client)", columns: Self.rowColumns,
                                 marked: DayKey.daysBetween(today, d.day) <= TownRules.warnDaysBefore)
            }
        openList(.fristnav, rows: rows)
        if rows.isEmpty { show(["Ingen frister de neste 7 dagene."]) }
        return .none
    }

    // MARK: Portfolio

    /// Every client the player has met: active ones, and prospects after the first talk.
    mutating func openPortfolio() -> TownAction {
        let met = content.klienter.filter { client in
            guard let s = state.clients[client.id] else { return false }
            return s.status == .active || (s.status == .prospect && s.met)
        }
        guard !met.isEmpty else { return say(["Du har ingen klienter ennå."]) }
        openList(.portfolio, rows: met.map { PanelRow.fitting(id: $0.id, $0.navn, columns: Self.rowColumns) })
        return .none
    }

    /// What the client needs: industry, VAT registration, staff, this year's deadlines and the
    /// industry's rule cards.
    func needsCard(_ client: TownClient) -> [String] {
        let bransje = content.bransje(client.bransje)
        let facts = [
            client.navn,
            bransje?.navn ?? client.bransje,
            client.mvaRegistrert ? "Mva-registrert" : "Ikke mva-registrert",
            "\(client.ansatte) ansatte",
        ]
        let frister = DeadlinePlanner.deadlines(for: client, year: today.year, deadlines: deadlines).map(\.label)
        let titles = (bransje?.regelkort ?? []).compactMap { id in ruleCards.first { $0.id == id }?.tittel }
        return [facts, frister, titles].filter { !$0.isEmpty }.map { $0.joined(separator: "\n") }
    }

    // MARK: Counter

    mutating func openCounter() -> TownAction {
        let tasks = activeClients.flatMap(counterTasks(for:))
        guard !tasks.isEmpty else { return say(["Ingenting å lukke eller levere nå."]) }
        openList(.counter, rows: tasks.map(\.row))
        counterTasks = tasks.map(\.task)
        return .none
    }

    /// R2: the earliest open month when it can be closed, then every deadline whose months are
    /// all closed and that is neither delivered nor missed.
    private func counterTasks(for client: TownClient) -> [(task: CounterTask, row: PanelRow)] {
        guard let clientState = state.clients[client.id] else { return [] }
        let name = Self.shortName(client)
        var out: [(task: CounterTask, row: PanelRow)] = []
        func add(_ task: CounterTask, _ text: String) {
            out.append((task, PanelRow.fitting(id: "\(out.count):\(client.id)", text, columns: Self.rowColumns)))
        }
        if let month = firstOpenMonth(clientState),
           Ledger.canClose(month, client: client, start: state.start, state: clientState, today: today, pool: pool) {
            add(.close(client: client.id, month: month), "\(name) LUKK \(Self.monthAbbreviations[month.month - 1])")
        }
        for year in state.start.year...max(state.start.year, today.year) {
            for d in DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines) {
                let months = d.kind.months(rates: deadlines.rates)
                guard !months.isEmpty, months.allSatisfy(clientState.closedMonths.contains),
                      !clientState.delivered.contains(d.kind.id), !clientState.missed.contains(d.kind.id) else { continue }
                add(.deliver(client: client.id, kind: d.kind), "\(name) LEVER \(Self.shortKind(d.kind))")
            }
        }
        return out
    }

    /// The earliest month from the start of the game that has ended and is not closed.
    private func firstOpenMonth(_ clientState: ClientState) -> MonthKey? {
        var month = state.start
        while month < MonthKey(today) {
            if !clientState.closedMonths.contains(month) { return month }
            month = month.next
        }
        return nil
    }

    private static func shortKind(_ kind: DeadlineKind) -> String {
        switch kind {
        case let .mva(termin, _): return "MVA \(termin)"
        case .mvaAarlig: return "MVA ÅR"
        }
    }

    /// Open errors in the month send the player to correct them; a clean month closes here.
    mutating func selectCounter() -> TownAction {
        guard counterTasks.indices.contains(cursor) else { return .none }
        switch counterTasks[cursor] {
        case let .close(id, month):
            guard state.clients[id]?.errors(in: month).isEmpty == true else {
                walk()
                return .startCorrection(client: id, month: month)
            }
            state.clients[id]?.closeIfClean(month)
            let name = content.client(id)?.navn ?? id
            return say(["\(name): \(Self.monthNames[month.month - 1]) er lukket."])
        case let .deliver(id, kind):
            walk()
            return .deliver(client: id, kind: kind)
        }
    }
}
