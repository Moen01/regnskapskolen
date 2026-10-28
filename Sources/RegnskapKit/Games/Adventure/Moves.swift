import Foundation

/// A move in an encounter: one paragraph of one law. Picking the paragraph the puzzle rests on is
/// the attack; the choice is where the learning sits.
public struct Move: Hashable, Sendable, Identifiable {
    public let lov: String
    public let paragraf: String

    public init(lov: String, paragraf: String) { self.lov = lov; self.paragraf = paragraf }

    public var id: String { "\(lov) \(paragraf)" }
    public var label: String { id }
    /// «bfl. § 4»: the form that fits a Game Boy move list.
    public func shortLabel(laws: LawNames) -> String { "\(laws.short(lov)) \(paragraf)" }
}

public enum Moves {
    /// Buttons on screen, «Ingen regel» included.
    public static let maxOptions = 6
    /// Pairs taken from other regions' cards, so the right one is not the only choice.
    public static let distractors = 2

    /// Every (lov, paragraf) pair a set of cards covers. A card's `lov` is a comma list and its
    /// paragraphs are not matched to laws one by one, so each law is paired with each paragraph.
    public static func pairs(from cards: [RuleCard]) -> [Move] {
        var pairs = Set<Move>()
        for card in cards {
            let laws = card.lov.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for lov in laws { for paragraf in card.paragrafer { pairs.insert(Move(lov: lov, paragraf: paragraf)) } }
        }
        return pairs.sorted { $0.id < $1.id }
    }

    public static func hits(_ move: Move, _ puzzle: Puzzle) -> Bool {
        puzzle.lov.contains { $0.lov == move.lov && $0.paragraf == move.paragraf }
    }

    public static func canHit(_ puzzle: Puzzle, regionCards: [RuleCard]) -> Bool {
        pairs(from: regionCards).contains { hits($0, puzzle) }
    }

    /// The region's pairs (at least one that hits) plus `distractors` foreign pairs that never hit,
    /// at most `maxOptions - 1` in all, in a seeded order. Empty when the region cannot hit the puzzle.
    public static func options(for puzzle: Puzzle, regionCards: [RuleCard], otherCards: [RuleCard], seed: UInt64) -> [Move] {
        guard canHit(puzzle, regionCards: regionCards) else { return [] }
        var generator = SplitMix64(seed: seed)
        let region = pairs(from: regionCards)
        let regionSlots = maxOptions - 1 - distractors
        var chosen = Array(region.filter { hits($0, puzzle) }.prefix(regionSlots))
        chosen += region.filter { !hits($0, puzzle) }.shuffled(using: &generator).prefix(max(0, regionSlots - chosen.count))
        let foreign = pairs(from: otherCards).filter { !hits($0, puzzle) && !region.contains($0) }.shuffled(using: &generator).prefix(distractors)
        chosen += foreign
        return chosen.shuffled(using: &generator)
    }
}
