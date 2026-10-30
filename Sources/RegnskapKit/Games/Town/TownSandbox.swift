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
    /// The earliest month from the client's books start that is over, not closed and has no
    /// open error the player can see. Bilag still unbooked in it do not stop it: the case stands in for them.
    public func sandboxMonth(start: MonthKey, today: DayKey, pool: Set<String>) -> MonthKey? {
        var month = booksFrom(start: start)
        while today >= month.next.first {
            if !closedMonths.contains(month), errors(in: month, pool: pool).isEmpty { return month }
            month = month.next
        }
        return nil
    }
}

extension TownState {
    /// Pays out a cleared sandbox case: a client's case closes a month, a case with a card gives
    /// the card. A case that gave nothing is not stored, so the next save tries again.
    /// `damage` is the booking damage of the closed month; the caller adds it to the topics.
    public mutating func creditSandbox(_ caseId: String, content: TownContent, pool: Set<String>,
                                       tema: (String) -> String?) -> (credit: SandboxCredit, damage: [String: Int]) {
        guard !sandboxCleared.contains(caseId) else { return (.already, [:]) }
        guard let person = content.sandboxPerson(caseId) else { return (.unknown, [:]) }
        if let id = person.klient {
            guard var client = clients[id], client.status == .active else { return (.notActive(client: id), [:]) }
            guard let month = client.sandboxMonth(start: start, today: calendar.today, pool: pool) else { return (.noMonth(client: id), [:]) }
            let damage = client.closeIfClean(month, pool: pool, tema: tema)
            clients[id] = client
            sandboxCleared.insert(caseId)
            return (.closedMonth(client: id, month: month), damage)
        }
        guard let card = person.gir else { return (.unknown, [:]) }
        regelkort.insert(card)
        sandboxCleared.insert(caseId)
        return (.card(card), [:])
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
