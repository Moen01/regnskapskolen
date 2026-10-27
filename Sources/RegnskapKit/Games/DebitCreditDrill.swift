import Foundation

extension AccountType {
    /// The side this kind of account normally grows on; nil for disponering, which has no fixed side.
    public var normalSide: Side? {
        switch self {
        case .eiendel, .kostnad: .debet
        case .gjeld, .egenkapital, .inntekt: .kredit
        case .disponering: nil
        }
    }

    /// "en eiendel", "gjeld", …: how the sentence names the kind.
    var drillPhrase: String? {
        switch self {
        case .eiendel: "en eiendel"
        case .gjeld: "gjeld"
        case .egenkapital: "egenkapital"
        case .inntekt: "en inntekt"
        case .kostnad: "en kostnad"
        case .disponering: nil
        }
    }

    var pluralNavn: String? {
        switch self {
        case .eiendel: "Eiendeler"
        case .gjeld: "Gjeld"
        case .egenkapital: "Egenkapital"
        case .inntekt: "Inntekter"
        case .kostnad: "Kostnader"
        case .disponering: nil
        }
    }
}

/// One card: an account that increases or decreases; the answer is the side that does it.
public struct DrillCard: Hashable, Sendable, Identifiable {
    public let account: Account
    public let increases: Bool

    public var id: String { "\(account.nr)-\(increases ? "opp" : "ned")" }
    public var answer: Side { increases ? account.okerPa : account.okerPa.other }
    /// A contra account grows on the opposite side of its kind (1580, 2080, 2710); its note explains why.
    public var isContra: Bool { account.type.normalSide != account.okerPa }

    /// "4300 er en kostnad. Kostnader øker på debet." or, for a contra account, its note plus the side.
    public var explanation: String {
        let side = account.okerPa.navn.lowercased()
        if isContra || account.type.drillPhrase == nil {
            return (account.merknad ?? "\(account.nr) \(account.navn) er en motkonto.") + " Den øker på \(side)."
        }
        return "\(account.nr) er \(account.type.drillPhrase!). \(account.type.pluralNavn!) øker på \(side)."
    }
}

/// Sixty seconds of "debet or kredit?" over the chart of accounts. Same clock and seed rules as the
/// lightning round; the deck refills so a fast player never runs out.
public struct DebitCreditDrill: Hashable, Sendable {
    public enum Phase: Hashable, Sendable { case question(shownAt: TimeInterval), feedback(since: TimeInterval), finished }

    public static let duration: TimeInterval = 60
    public static let feedbackMinimum: TimeInterval = 1.5
    public static let quickAnswer: TimeInterval = 1.5
    public static let basePoints = 10
    public static let speedBonus = 5

    private let deck: [DrillCard]
    public private(set) var queue: [DrillCard]
    public private(set) var phase: Phase
    public private(set) var score = 0
    public private(set) var correct = 0
    public private(set) var answered = 0
    public private(set) var combo = Combo()
    public private(set) var lastCorrect: Bool?
    private let startedAt: TimeInterval
    private var pausedFor: TimeInterval = 0
    private var pauseStart: TimeInterval?

    public var current: DrillCard? { queue.first }

    /// Two cards per account, disponering left out: those have no side to learn.
    public static func cards(chart: ChartOfAccounts) -> [DrillCard] {
        chart.all.filter { $0.type != .disponering }.flatMap { [DrillCard(account: $0, increases: true), DrillCard(account: $0, increases: false)] }
    }

    public init(chart: ChartOfAccounts, seed: UInt64, startedAt: TimeInterval) {
        var generator = SplitMix64(seed: seed)
        deck = Self.cards(chart: chart).shuffled(using: &generator)
        queue = deck
        self.startedAt = startedAt
        phase = deck.isEmpty ? .finished : .question(shownAt: startedAt)
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        let paused = pausedFor + (pauseStart.map { now - $0 } ?? 0)
        return max(0, Self.duration - (now - startedAt - paused))
    }

    /// The points given, or nil outside a question or once the time is up.
    public mutating func answer(_ side: Side, at now: TimeInterval) -> Int? {
        tick(at: now)
        guard case .question(let shownAt) = phase, let card = current else { return nil }
        let right = side == card.answer
        answered += 1
        lastCorrect = right
        guard right else {
            combo.miss()
            phase = .feedback(since: now)
            pauseStart = now
            return 0
        }
        let points = Int(Double(Self.basePoints) * combo.multiplier) + (now - shownAt <= Self.quickAnswer ? Self.speedBonus : 0)
        score += points
        correct += 1
        combo.hit()
        advance(at: now)
        return points
    }

    public mutating func next(at now: TimeInterval) {
        guard case .feedback(let since) = phase, now - since >= Self.feedbackMinimum else { return }
        pausedFor += now - (pauseStart ?? now)
        pauseStart = nil
        advance(at: now)
    }

    public mutating func tick(at now: TimeInterval) {
        if phase != .finished, remaining(at: now) <= 0 { finish() }
    }

    public mutating func finish() { phase = .finished }

    private mutating func advance(at now: TimeInterval) {
        queue.removeFirst()
        if queue.isEmpty { queue = deck }
        phase = .question(shownAt: now)
    }

    public var summary: RoundSummary {
        RoundSummary(game: .debetKredit, tema: nil, score: score, correct: correct, answered: answered, bestCombo: combo.best)
    }
}
