import Foundation

public struct ItemResult: Hashable, Sendable {
    public enum State: Sendable { case right, wrong, missed }
    public let index: Int
    public let state: State
    public let note: String?
}

/// What a check found: right or not, the messages to show in the ladder's words, a 0…1 score and,
/// for list-type puzzles, the state per item.
public struct Verdict: Hashable, Sendable {
    public let correct: Bool
    public let messages: [String]
    public let score: Double
    public let perItem: [ItemResult]?

    public init(correct: Bool, messages: [String], score: Double, perItem: [ItemResult]? = nil) {
        self.correct = correct; self.messages = messages; self.score = score; self.perItem = perItem
    }

    public static func right(_ message: String = "Riktig!") -> Verdict { Verdict(correct: true, messages: [message], score: 1) }
    public static func wrong(_ messages: [String], score: Double = 0) -> Verdict { Verdict(correct: false, messages: messages, score: score) }
}
