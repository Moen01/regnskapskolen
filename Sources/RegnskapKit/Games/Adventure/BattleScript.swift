import Foundation

/// What the dialog box says during an encounter. Each element is one page's text; the dialog
/// wraps it. Plain text only: the pixel font has no bold, and no U+2212, so minus is `-`.
public enum BattleScript {
    public static func intro(_ encounter: Encounter) -> [String] {
        let name = SpeciesName.name(for: encounter.puzzle.id)
        let title = encounter.puzzle.tittel
        switch encounter.context {
        case .wild: break
        case .bilag: return ["Bilag fra haugen!", title]
        case .correction(_, let day):
            // One page; the dialog's wrap puts a long species name on the date's line instead of cutting it.
            return ["Avstemmingen går ikke opp: \(name) \(String(format: "%02d.%02d", day.day, day.month))."]
        case .trial: return ["Prøvesak!", title]
        case .fagkontor(let office): return ["\(office) vil teste deg!", title]
        case .kundesak(_, let name): return ["\(name) lurer på", "noe!", title]
        }
        let first: String
        if encounter.isGymLeader {
            first = "Gym-lederen \(name) stiller!"
        } else if encounter.stageBefore == .vill {
            first = "En vill \(name) dukket opp!"
        } else {
            first = "\(name) (\(encounter.stageBefore.navn.uppercased())) vil kjempe igjen!"
        }
        return [first, title]
    }

    public static func moveUsed(_ move: Move?, laws: LawNames) -> String {
        guard let move else { return "Du angrep uten regel!" }
        return "Du brukte \(move.shortLabel(laws: laws))!"
    }

    public static func result(_ outcome: EncounterOutcome, encounter: Encounter) -> [String] {
        let name = SpeciesName.name(for: encounter.puzzle.id)
        switch outcome {
        case .caught(let stage, let superEffective):
            return [superEffective ? "Det er supereffektivt!" : "Treff!", "\(name) ble fanget! Trinn: \(stage.navn.uppercased())"]
        case .escaped(let hpLost):
            return ["Bom!", "\(name) flyktet! Kunden mistet \(kroner(hpLost)) kr."]
        case .repeated:
            return ["Riktig, men \(name) er alt møtt i dag.", "Den kommer igjen i morgen."]
        case .booked:
            return ["Bilaget er bokført."]
        case .corrected(let ok):
            return [ok ? "Feilen er rettet." : "Fortsatt feil. Kunden er mindre fornøyd."]
        case .answered(let ok):
            return ok ? ["Kunden er", "fornøyd."] : ["Det stemte ikke."]
        }
    }

    /// The explanation as plain text, then one line per paragraph the puzzle rests on.
    public static func explanation(_ encounter: Encounter, laws: LawNames) -> [String] {
        [TextWrap.plain(markdown: encounter.puzzle.forklaring)]
            + encounter.puzzle.lov.map { "\(laws.short($0.lov)) \($0.paragraf): \($0.tekst)" }
    }

    /// Whole kroner with a plain space between thousands and an ASCII minus: the pixel font has
    /// neither U+202F nor U+2212.
    public static func kroner(_ amount: Int) -> String {
        NorwegianFormat.kroner(Decimal(amount), decimals: 0)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
