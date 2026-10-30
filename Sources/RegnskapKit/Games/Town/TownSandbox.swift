import Foundation

/// What a cleared sandbox case gave. Only `closedMonth` and `card` use up the case.
public enum SandboxCredit: Hashable, Sendable {
    case closedMonth(client: String, month: MonthKey)
    case card(String)
    case already
    case notActive(client: String)
    case noMonth(client: String)
    case unknown
}

extension ClientState {
    /// The earliest month from the client's books start that is over, not closed and has no booked
    /// bilag: the case stands in for that whole month. A month with bookings is never taken, right
    /// or wrong, so the choice tells nothing about a held-back verdict (spec Mål 7).
    public func sandboxMonth(start: MonthKey, today: DayKey) -> MonthKey? {
        let withBilag = Set(booked.map(\.month))
        var month = booksFrom(start: start)
        while today >= month.next.first {
            if !closedMonths.contains(month), !withBilag.contains(month) { return month }
            month = month.next
        }
        return nil
    }
}

extension TownState {
    /// Pays out a cleared sandbox case: a client's case closes a month, a case with a card gives
    /// the card. A case that gave nothing is not stored, so the next save tries again.
    /// The closed month has no bookings, so it has no booking damage to pay.
    public mutating func creditSandbox(_ caseId: String, content: TownContent) -> SandboxCredit {
        guard !sandboxCleared.contains(caseId) else { return .already }
        guard let person = content.sandboxPerson(caseId) else { return .unknown }
        if let id = person.klient {
            guard var client = clients[id], client.status == .active else { return .notActive(client: id) }
            guard let month = client.sandboxMonth(start: start, today: calendar.today) else { return .noMonth(client: id) }
            client.closedMonths.insert(month)
            clients[id] = client
            sandboxCleared.insert(caseId)
            return .closedMonth(client: id, month: month)
        }
        guard let card = person.gir else { return .unknown }
        regelkort.insert(card)
        sandboxCleared.insert(caseId)
        return .card(card)
    }
}

extension TownFlow {
    /// The lines that tell what a cleared case gave. Silent for the rest, since the call runs on
    /// every save in the sandbox.
    public static func sandboxTexts(_ credit: SandboxCredit, content: TownContent, ruleCards: [RuleCard]) -> [String] {
        switch credit {
        case .closedMonth(let id, let month):
            let name = content.client(id).map(shortName) ?? id.uppercased()
            return ["Saken er ryddet!", "\(name): \(monthNames[month.month - 1]) er lukket."]
        case .card(let id):
            return ["Saken er ryddet!", "Du fikk regelkortet «\(ruleCards.first { $0.id == id }?.tittel ?? id)»."]
        case .already, .notActive, .noMonth, .unknown:
            return []
        }
    }
}
