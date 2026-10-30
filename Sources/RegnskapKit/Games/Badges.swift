import Foundation

public enum GameKind: String, Codable, Hashable, Sendable, CaseIterable {
    case lynrunde
    case debetKredit = "debet-kredit"

    public var navn: String {
        switch self {
        case .lynrunde: "Lynrunde"
        case .debetKredit: "Debet eller kredit?"
        }
    }
}

public struct Badge: Hashable, Sendable, Identifiable {
    public let id: String
    public let navn: String
    public let beskrivelse: String
    public let symbol: String
}

/// What the app tells the badge rules about; each event is one call to `Badges.award`.
public enum GameEvent: Hashable, Sendable {
    case puzzleAnswered(kind: PuzzleKind, correctFirstTry: Bool)
    /// `tema` is the lightning round's topic filter; nil is all topics, the only kind that can earn «Lynrask».
    case roundFinished(game: GameKind, tema: String?, score: Int, correct: Int)
    case caseMatched
    case bankReconciled
    case dayCompleted(streak: Int)
    /// Paragrafjakten: a creature caught; `total` is the collection's size afterwards.
    case caught(total: Int)
    /// Every puzzle in a region at box 3 or higher.
    case regionMastered
    /// A gym badge earned; `count` is how many are held afterwards.
    case gymBadges(count: Int)
    /// The bokettersyn was passed.
    case auditPassed
}

/// The badge catalog and the one place badges are handed out. Thresholds live here.
public enum Badges {
    public static let mvaRun = "mva-paa-rad", fristCount = "frist-riktig"
    public static let mvaRunNeeded = 20, fristNeeded = 10, lynraskScore = 1500, reflekserCorrect = 30
    public static let streakSeven = 7, streakThirty = 30
    public static let collectorCount = 25, allGyms = 12

    public static let all: [Badge] = [
        Badge(id: "mva-mester", navn: "Mva-mester", beskrivelse: "20 mva-oppgaver riktig på rad", symbol: "percent"),
        Badge(id: "fristfri", navn: "Fristfri", beskrivelse: "10 frister riktig på første forsøk", symbol: "calendar.badge.checkmark"),
        Badge(id: "null-differanse", navn: "Null differanse", beskrivelse: "En sandkasse-case som stemmer med fasiten", symbol: "equal.circle"),
        Badge(id: "bank-avstemt", navn: "Bank avstemt", beskrivelse: "En case avstemt mot banken", symbol: "building.columns"),
        Badge(id: "lynrask", navn: "Lynrask", beskrivelse: "1 500 poeng i Lynrunden", symbol: "bolt"),
        Badge(id: "reflekser", navn: "Reflekser", beskrivelse: "30 riktige i én runde Debet eller kredit?", symbol: "arrow.left.arrow.right"),
        Badge(id: "sju-dager", navn: "Sju dager", beskrivelse: "7 dager på rad", symbol: "flame"),
        Badge(id: "tretti-dager", navn: "Tretti dager", beskrivelse: "30 dager på rad", symbol: "flame.fill"),
        Badge(id: "forste-fangst", navn: "Første fangst", beskrivelse: "Den første skapningen i samlingen", symbol: "sparkle"),
        Badge(id: "samler", navn: "Samler", beskrivelse: "25 skapninger i samlingen", symbol: "square.grid.3x3.fill"),
        Badge(id: "hele-regionen", navn: "Hele regionen", beskrivelse: "Alle skapningene i én region på Voksen eller høyere", symbol: "map.fill"),
        Badge(id: "tolv-merker", navn: "Tolv merker", beskrivelse: "Alle gym-merkene", symbol: "crown.fill"),
        Badge(id: "revisorens-beste-venn", navn: "Revisorens beste venn", beskrivelse: "Et bokettersyn uten merknader", symbol: "checkmark.seal"),
    ]

    public static func badge(_ id: String) -> Badge? { all.first { $0.id == id } }

    /// Updates the counters the event touches, records the badges it earns on `day` (each once), and
    /// returns the ones earned by this call, in catalog order.
    @discardableResult
    public static func award(_ event: GameEvent, on day: DayKey, progress: inout LearnerProgress) -> [Badge] {
        var earned: [String] = []
        switch event {
        case .puzzleAnswered(let kind, let correctFirstTry):
            if kind == .mva {
                let run = correctFirstTry ? (progress.game.counters[mvaRun] ?? 0) + 1 : 0
                progress.game.counters[mvaRun] = run
                if run >= mvaRunNeeded { earned.append("mva-mester") }
            }
            if kind == .frist, correctFirstTry {
                let count = (progress.game.counters[fristCount] ?? 0) + 1
                progress.game.counters[fristCount] = count
                if count >= fristNeeded { earned.append("fristfri") }
            }
        case .roundFinished(let game, let tema, let score, let correct):
            if game == .lynrunde, tema == nil, score >= lynraskScore { earned.append("lynrask") }
            if game == .debetKredit, correct >= reflekserCorrect { earned.append("reflekser") }
        case .caseMatched:
            earned.append("null-differanse")
        case .bankReconciled:
            earned.append("bank-avstemt")
        case .dayCompleted(let streak):
            if streak >= streakSeven { earned.append("sju-dager") }
            if streak >= streakThirty { earned.append("tretti-dager") }
        case .caught(let total):
            if total >= 1 { earned.append("forste-fangst") }
            if total >= collectorCount { earned.append("samler") }
        case .regionMastered:
            earned.append("hele-regionen")
        case .gymBadges(let count):
            if count >= allGyms { earned.append("tolv-merker") }
        case .auditPassed:
            earned.append("revisorens-beste-venn")
        }
        return all.filter { earned.contains($0.id) && progress.game.badges[$0.id] == nil }.map { badge in
            progress.game.badges[badge.id] = day
            return badge
        }
    }
}
