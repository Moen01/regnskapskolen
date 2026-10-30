import Foundation

/// Fristnav, the portfolio and the counter: the lists the town opens, and the needs card.
extension TownFlow {
    static let monthAbbreviations = ["JAN", "FEB", "MAR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DES"]
    public static let monthNames = ["januar", "februar", "mars", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "desember"]

    /// The first word of the name in capitals ("Bakeren AS" → "BAKEREN"), so rows stay short.
    static func shortName(_ client: TownClient) -> String {
        client.navn.split(separator: " ").first.map { $0.uppercased() } ?? client.id.uppercased()
    }

    /// A list row of a client's short name and a detail ("MVA1", "LUKK JAN"). Only the name is
    /// cut, so the detail always survives the 17 columns; `full` goes to the dialog under the list.
    static func clientRow(id: String, name: String, detail: String, nameFirst: Bool, full: String, marked: Bool = false) -> PanelRow {
        let cut = TextWrap.truncate(name, to: max(1, rowColumns - detail.count - 1))
        return PanelRow(id: id, text: nameFirst ? "\(cut) \(detail)" : "\(detail) \(cut)", full: full, marked: marked)
    }

    var today: DayKey { state.calendar.today }

    var activeClients: [TownClient] {
        content.klienter.filter { state.clients[$0.id]?.status == .active }
    }

    // MARK: Fristnav

    /// Deadlines in the next seven days for active clients, marked when few days are left.
    /// A delivered deadline is left out: there is nothing more to do for it.
    mutating func openFristnav() -> TownAction {
        let rows = DeadlinePlanner.upcoming(clients: activeClients, from: today, days: 7, deadlines: deadlines)
            .filter { d in
                guard let client = state.clients[d.client] else { return true }
                return !client.delivered.contains(d.kind.id) && state.counts(d, client: client)
            }
            .map { d in
                let client = content.client(d.client)
                return Self.clientRow(id: "\(d.client):\(d.kind.id)", name: client.map(Self.shortName) ?? d.client.uppercased(),
                                      detail: d.shortLabel, nameFirst: false, full: "\(d.label) \(client?.navn ?? d.client)",
                                      marked: DayKey.daysBetween(today, d.day) <= TownRules.warnDaysBefore)
            }
        openList(.fristnav, rows: rows + [PanelRow(id: Self.travelRowId, text: "KART", full: "Reis til en bydel")])
        if rows.isEmpty { show(["Ingen frister de neste 7 dagene."]) }
        return .none
    }

    // MARK: Fast travel

    static let travelRowId = "kart"

    /// One row per open district; the one the player stands in is marked.
    mutating func openTravel() -> TownAction {
        let here = TownDistricts.district(of: state.mapId, in: content)?.id
        let open = TownDistricts.all(in: content).filter {
            TownDistricts.isOpen($0.id, content: content, fullmakter: state.fullmakter)
        }
        openList(.travel, rows: open.map { PanelRow(id: $0.id, text: $0.navn.uppercased(), marked: $0.id == here) })
        return .none
    }

    /// Travel is free and saved like a door. Choosing the current district only closes the list.
    mutating func selectTravel() -> TownAction {
        guard rows.indices.contains(cursor), let district = TownDistricts.all(in: content).first(where: { $0.id == rows[cursor].id }) else {
            walk()
            return .none
        }
        if district.id == TownDistricts.district(of: state.mapId, in: content)?.id {
            walk()
            return .none
        }
        state.mapId = district.id
        state.walker = TownWalker(x: district.ankomst.x, y: district.ankomst.y, facing: .down)
        walk()
        return .enteredDoor
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

    // MARK: Bag and coffee

    /// The machine gives one cup per day; the cup goes in the bag.
    mutating func takeCoffee() -> TownAction {
        guard state.coffeeTakenOn != today else { return say(["Kannen er tom til i morgen."]) }
        state.coffee += TownRules.coffeePerDay
        state.coffeeTakenOn = today
        return say(["Du tar en kaffe med deg."])
    }

    private var bagRows: [PanelRow] {
        [PanelRow(id: "kaffe", text: "KAFFE x\(state.coffee)", full: "Kaffe gir deg \(TownRules.coffeeEnergy) energi"),
         PanelRow(id: "avtaler", text: "AVTALER x\(state.contracts)", full: "Oppdragsavtaler du kan bruke på en prøvesak"),
         PanelRow(id: "regelkort", text: "REGELKORT x\(heldCards.count)", full: "Et regelkort gir deg trekk i én kamp"),
         PanelRow(id: "fullmakt", text: "FULLMAKT x\(state.fullmakter.count)", full: "Fullmakter åpner nye bydeler")]
    }

    /// The rule cards the player has, in library order. An id the library no longer has is left out.
    private var heldCards: [RuleCard] {
        ruleCards.filter { state.regelkort.contains($0.id) }
    }

    mutating func openBag() {
        openList(.bag, rows: bagRows)
    }

    /// A on the coffee drinks one cup; the list stays open so the player sees the numbers change.
    mutating func selectBag() -> TownAction {
        switch cursor {
        case 0: return drinkCoffee()
        case 2: return openCards()
        case 3: return showFullmakter()
        default:
            turnPage()
            return .none
        }
    }

    private mutating func drinkCoffee() -> TownAction {
        guard state.coffee > 0 else {
            show(["Du har ingen kaffe."])
            return .none
        }
        state.coffee -= 1
        state.energy = min(TownRules.maxEnergy, state.energy + TownRules.coffeeEnergy)
        rows = bagRows
        show(["Du føler deg våken."])
        return .none
    }

    private mutating func showFullmakter() -> TownAction {
        let names = TownDistricts.all(in: content).filter { $0.fullmakt.map(state.fullmakter.contains) ?? false }.map(\.navn)
        show(names.isEmpty ? ["Ingen fullmakter ennå."] : ["Du har fullmakt til: \(names.joined(separator: ", "))."])
        return .none
    }

    // MARK: Rule cards

    private func cardRows() -> [PanelRow] {
        heldCards.map { card in
            PanelRow(id: card.id, text: TextWrap.truncate(card.tittel, to: Self.rowColumns),
                     full: "\(card.tittel). Legges til trekkene i neste kamp.", marked: state.equippedCard == card.id)
        }
    }

    mutating func openCards() -> TownAction {
        let rows = cardRows()
        guard !rows.isEmpty else {
            show(["Du har ingen regelkort."])
            return .none
        }
        openList(.cards, rows: rows)
        return .none
    }

    /// A on a card equips it for the next battle; A on the equipped card puts it back.
    mutating func selectCard() -> TownAction {
        guard rows.indices.contains(cursor) else { return .none }
        let id = rows[cursor].id
        state.equippedCard = state.equippedCard == id ? nil : id
        rows = cardRows()
        show([rows[cursor].full ?? rows[cursor].text])
        return .none
    }

    /// A pile of papers in town: the first visit gives its card, later ones find nothing.
    mutating func findCard(_ person: TownPerson) -> TownAction {
        guard let id = person.gir, !state.found.contains(person.id) else { return say(["Det er ikke mer her."]) }
        state.found.insert(person.id)
        state.regelkort.insert(id)
        let title = ruleCards.first { $0.id == id }?.tittel ?? id
        return say(["Du fant et regelkort!", title])
    }

    // MARK: Archive

    private func archiveRows() -> [PanelRow] {
        content.klienter.compactMap { client in
            guard let status = state.clients[client.id]?.status else { return nil }
            let detail: String
            switch status {
            case .active: detail = "LEGG BORT"
            case .parked: detail = "HENT"
            case .archived: detail = "SA OPP"
            case .prospect: return nil
            }
            return Self.clientRow(id: client.id, name: Self.shortName(client), detail: detail, nameFirst: true, full: client.navn)
        }
    }

    /// The office PC: every client that is active, put away or quit, in content order.
    mutating func openArchive() -> TownAction {
        let rows = archiveRows()
        guard !rows.isEmpty else { return say(["Arkivet er tomt."]) }
        openList(.archive, rows: rows)
        return .none
    }

    /// A on a row: park an active client, take a parked one back, or tell that one quit.
    mutating func selectArchive() -> TownAction {
        guard rows.indices.contains(cursor), let client = content.client(rows[cursor].id), let status = state.clients[client.id]?.status else { return .none }
        let message: String
        switch status {
        case .active:
            message = state.park(client.id) ? "\(client.navn) ligger nå i arkivet." : "Lukk månedene for \(client.navn) først."
        case .parked:
            message = state.unpark(client.id, on: today) ? "\(client.navn) er tilbake." : "Porteføljen er full."
        case .archived:
            message = "\(client.navn) sa opp. Vinn dem tilbake med en prøvesak."
        case .prospect:
            return .none
        }
        rows = archiveRows()
        show([message])
        return .none
    }

    // MARK: Counter

    mutating func openCounter() -> TownAction {
        let tasks = activeClients.flatMap(counterTasks(for:))
        guard !tasks.isEmpty else { return say(["Ingenting å lukke eller levere nå."]) }
        openList(.counter, rows: tasks.map(\.row))
        counterTasks = tasks.map(\.task)
        return .none
    }

    /// R2: the earliest open month when it can be closed, then every deadline that has opened, whose
    /// months (withholding has none) are all closed (`ClientState.hasClosed`) and that is neither
    /// delivered nor missed.
    private func counterTasks(for client: TownClient) -> [(task: CounterTask, row: PanelRow)] {
        guard let clientState = state.clients[client.id] else { return [] }
        let name = Self.shortName(client)
        var out: [(task: CounterTask, row: PanelRow)] = []
        func add(_ task: CounterTask, _ detail: String, full: String) {
            out.append((task, Self.clientRow(id: "\(out.count):\(client.id)", name: name, detail: detail, nameFirst: true, full: full)))
        }
        if !clientState.discoveredErrors(pool: pool).isEmpty {
            add(.fixDiscovered(client: client.id), "RETT FEIL", full: "Rett feilene \(client.navn) fant")
        }
        if let month = firstOpenMonth(clientState),
           Ledger.canClose(month, client: client, start: state.start, state: clientState, today: today, pool: pool) {
            add(.close(client: client.id, month: month), "LUKK \(Self.monthAbbreviations[month.month - 1])",
                full: "Lukk \(Self.monthNames[month.month - 1]) for \(client.navn)")
        }
        for year in state.start.year...max(state.start.year, today.year) {
            for d in DeadlinePlanner.deadlines(for: client, year: year, deadlines: deadlines) {
                let months = d.kind.months(rates: deadlines.rates)
                guard state.counts(d, client: clientState), today >= d.opens, clientState.hasClosed(months, start: state.start),
                      !clientState.delivered.contains(d.kind.id), !clientState.missed.contains(d.kind.id) else { continue }
                add(.deliver(client: client.id, kind: d.kind), "LEVER \(d.kind.shortName)", full: "Lever \(d.label) for \(client.navn)")
            }
        }
        return out
    }

    /// The earliest month from the client's books start that has ended and is not closed.
    private func firstOpenMonth(_ clientState: ClientState) -> MonthKey? {
        var month = clientState.booksFrom(start: state.start)
        while month < MonthKey(today) {
            if !clientState.closedMonths.contains(month) { return month }
            month = month.next
        }
        return nil
    }

    /// Open errors in the month send the player to correct them; a clean month closes here and
    /// returns `.closedMonth` once its dialog is read.
    mutating func selectCounter() -> TownAction {
        guard counterTasks.indices.contains(cursor) else { return .none }
        switch counterTasks[cursor] {
        case let .fixDiscovered(id):
            walk()
            return .fixDiscovered(client: id)
        case let .close(id, month):
            guard state.clients[id]?.errors(in: month, pool: pool).isEmpty == true else {
                walk()
                return .startCorrection(client: id, month: month)
            }
            state.clients[id]?.closeIfClean(month, pool: pool)
            let name = content.client(id)?.navn ?? id
            // The close costs an action like a correction does; the app spends it when the dialog ends.
            return say(["\(name): \(Self.monthNames[month.month - 1]) er lukket."], then: .action(.closedMonth(client: id, month: month)))
        case let .deliver(id, kind):
            walk()
            return .deliver(client: id, kind: kind)
        }
    }
}
