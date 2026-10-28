import Foundation

/// Where a creature stands: a wild one is a puzzle not yet caught; the rest are the Leitner boxes.
public enum Stage: Int, Hashable, Sendable, CaseIterable {
    case vill = 0, klekket, ung, voksen, mester

    public var navn: String {
        switch self {
        case .vill: "Vill"
        case .klekket: "Klekket"
        case .ung: "Ung"
        case .voksen: "Voksen"
        case .mester: "Mester"
        }
    }

    public static func of(box: Int?) -> Stage { Stage(rawValue: min(max(box ?? 0, 0), 4))! }
}

public struct RegionTheme: Hashable, Sendable {
    public let symbol: String
    /// A colour name the app maps to its theme colours: skole, debet, kredit, ok, warn, orange.
    public let farge: String
    public let setning: String
}

/// One topic as a place on the map: its puzzles, the gym leader, what the learner has caught.
public struct Region: Hashable, Sendable, Identifiable {
    public let tema: String
    public let navn: String
    public let rekkefolge: Int
    public let theme: RegionTheme
    public let puzzles: [Puzzle]
    public let gymLeader: Puzzle?
    public let caught: Int
    public let mastered: Int
    public let unlocked: Bool
    public let gymBadge: DayKey?

    public init(tema: String, navn: String, rekkefolge: Int, theme: RegionTheme, puzzles: [Puzzle], gymLeader: Puzzle?, caught: Int, mastered: Int, unlocked: Bool, gymBadge: DayKey?) {
        self.tema = tema; self.navn = navn; self.rekkefolge = rekkefolge; self.theme = theme; self.puzzles = puzzles; self.gymLeader = gymLeader
        self.caught = caught; self.mastered = mastered; self.unlocked = unlocked; self.gymBadge = gymBadge
    }

    public var id: String { tema }
    public var isEmpty: Bool { puzzles.isEmpty }
    public var caughtRatio: Double { puzzles.isEmpty ? 0 : Double(caught) / Double(puzzles.count) }

    /// Half the region's weight, gym leader left out: that much damage opens the gym.
    public var damageTarget: Int {
        puzzles.filter { $0.id != gymLeader?.id }.map { $0.vanskelighet * RegionRunRules.damagePerLevel }.reduce(0, +) / 2
    }
}

/// The numbers shared by the regions and the runs.
public enum RegionRunRules {
    public static let damagePerLevel = 100
}

public enum Regions {
    public static let unlockRatio = 0.6
    public static let gymBadgePrefix = "gym-"

    public static let themes: [String: RegionTheme] = [
        "grunnlag": RegionTheme(symbol: "scalemass", farge: "skole", setning: "Her bor bilagene. Alt begynner med debet og kredit."),
        "kontoplan": RegionTheme(symbol: "list.number", farge: "debet", setning: "Et kontonummer forteller klasse, gruppe og side. Lær å lese det."),
        "resultat-balanse": RegionTheme(symbol: "chart.bar.doc.horizontal", farge: "ok", setning: "Resultatet binder resultat og balanse sammen."),
        "bilag-bokforingsloven": RegionTheme(symbol: "doc.text", farge: "warn", setning: "Et bilag må kunne leses om fem år. Loven sier hva det må inneholde."),
        "perioder-frister": RegionTheme(symbol: "calendar", farge: "kredit", setning: "Mva, a-melding og årsregnskap har hver sin dag. Bom på én, og det koster."),
        "mva": RegionTheme(symbol: "percent", farge: "skole", setning: "Fire satser, unntak og omvendt avgiftsplikt. Regionen med flest feller."),
        "lonn": RegionTheme(symbol: "person.2", farge: "debet", setning: "Brutto, trekk, arbeidsgiveravgift og feriepenger. Fire bilag i ett."),
        "periodisering": RegionTheme(symbol: "arrow.left.arrow.right", farge: "ok", setning: "Kostnaden hører til perioden den gjelder, ikke den du betalte i."),
        "avskrivning": RegionTheme(symbol: "wrench.and.screwdriver", farge: "warn", setning: "Varig og betydelig? Da aktiveres det og skrives av."),
        "arsoppgjor": RegionTheme(symbol: "book.closed", farge: "kredit", setning: "Året lukkes: disponering, frister og hva som må oppbevares."),
        "reskontro-bank": RegionTheme(symbol: "building.columns", farge: "skole", setning: "Kunder, leverandører og banken. Her ligger dungeonen."),
        "valuta-korrigeringer": RegionTheme(symbol: "eurosign.circle", farge: "orange", setning: "Kurser som endrer seg og feil som skal rettes uten å slette noe."),
    ]
    static let fallbackTheme = RegionTheme(symbol: "questionmark.circle", farge: "secondary", setning: "")

    /// Edge case with the highest vanskelighet, else the highest vanskelighet; ties go to the lowest id.
    public static func gymLeader(of puzzles: [Puzzle]) -> Puzzle? {
        let candidates = puzzles.contains(where: \.isEdgeCase) ? puzzles.filter(\.isEdgeCase) : puzzles
        return candidates.max { a, b in (a.vanskelighet, b.id) < (b.vanskelighet, a.id) }
    }

    /// One region per topic in `rekkefolge` order. The first is open; each next one opens when the
    /// previous region with puzzles has enough caught, and an empty region passes its status on.
    public static func build(topics: [Topic], pool: [Puzzle], progress: LearnerProgress) -> [Region] {
        var regions: [Region] = []
        for topic in topics.sorted(by: { $0.rekkefolge < $1.rekkefolge }) {
            let puzzles = pool.filter { $0.tema == topic.id }.sorted { $0.id < $1.id }
            let boxes = puzzles.map { progress.puzzles[$0.id]?.box ?? 0 }
            let unlocked: Bool
            if let previous = regions.last {
                unlocked = previous.isEmpty ? previous.unlocked : previous.caughtRatio >= unlockRatio
            } else {
                unlocked = true
            }
            regions.append(Region(tema: topic.id, navn: topic.navn, rekkefolge: topic.rekkefolge, theme: themes[topic.id] ?? fallbackTheme,
                                  puzzles: puzzles, gymLeader: gymLeader(of: puzzles),
                                  caught: boxes.filter { $0 >= 1 }.count, mastered: boxes.filter { $0 >= 3 }.count,
                                  unlocked: unlocked, gymBadge: progress.game.badges[gymBadgePrefix + topic.id]))
        }
        return regions
    }
}
