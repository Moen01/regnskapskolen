import Foundation

/// Checks for every kind but `postering` (see `PostingChecker`).
public enum Checkers {
    public static func classify(_ answers: [Int: String], _ puzzle: Classify) -> Verdict {
        let items = puzzle.elementer.enumerated().map { i, item -> ItemResult in
            guard let answer = answers[i] else { return ItemResult(index: i, state: .missed, note: item.hvorfor) }
            return ItemResult(index: i, state: answer == item.svar ? .right : .wrong, note: answer == item.svar ? nil : item.hvorfor)
        }
        let right = items.filter { $0.state == .right }.count
        let correct = right == items.count
        return Verdict(correct: correct, messages: ["\(right) av \(items.count) riktig."], score: items.isEmpty ? 1 : Double(right) / Double(items.count), perItem: items)
    }

    public static func spot(_ marked: Set<Int>, _ puzzle: Spot) -> Verdict {
        let items = puzzle.elementer.enumerated().map { i, item -> ItemResult in
            switch (item.feil, marked.contains(i)) {
            case (true, true): ItemResult(index: i, state: .right, note: item.hvorfor)
            case (true, false): ItemResult(index: i, state: .missed, note: item.hvorfor)
            case (false, true): ItemResult(index: i, state: .wrong, note: nil)
            case (false, false): ItemResult(index: i, state: .right, note: nil)
            }
        }
        let wrongTotal = puzzle.elementer.filter(\.feil).count
        let found = items.filter { $0.state == .right && puzzle.elementer[$0.index].feil }.count
        let falseMarks = items.filter { $0.state == .wrong }.count
        let correct = found == wrongTotal && falseMarks == 0
        let score = max(0, Double(found - falseMarks)) / Double(max(wrongTotal, 1))
        return Verdict(correct: correct, messages: ["Du fant \(found) av \(wrongTotal)."], score: score, perItem: items)
    }

    public static func number(_ value: Decimal, _ puzzle: NumberAnswer) -> Verdict {
        if abs(value - puzzle.svar) <= puzzle.toleranse {
            return .right("Riktig! \(NorwegianFormat.kroner(puzzle.svar, decimals: puzzle.svar == puzzle.svar.rounded ? 0 : 2))\(puzzle.enhet.map { " \($0)" } ?? "").")
        }
        return .wrong(["Ikke riktig." + (puzzle.hint.map { " Hint: \($0)" } ?? "")])
    }

    public static func quiz(_ index: Int, _ puzzle: Quiz) -> Verdict {
        index == puzzle.svar ? .right() : .wrong(["Ikke riktig."])
    }

    public static func `case`(_ key: String, _ puzzle: Case) -> Verdict {
        key == puzzle.svar ? .right() : .wrong(["Ikke riktig."])
    }

    /// `fradrag` nil in the fasit means the deduction right is not asked.
    public static func vat(_ behandling: String, _ fradrag: Bool?, _ puzzle: VAT) -> Verdict {
        guard behandling == puzzle.fasit.behandling else { return .wrong(["Feil behandling."]) }
        if let expected = puzzle.fasit.fradrag, fradrag != expected {
            return .wrong(["Behandlingen er riktig, men fradragsretten er feil."], score: 0.5)
        }
        return .right()
    }

    public static func deadline(_ day: DayKey, _ puzzle: Deadline) -> Verdict {
        day == puzzle.fasit ? .right("Riktig! \(NorwegianFormat.date(puzzle.fasit.date)).") : .wrong(["Ikke riktig." + (puzzle.hint.map { " Hint: \($0)" } ?? "")])
    }
}

extension Decimal {
    var rounded: Decimal {
        var r = self, s = self
        NSDecimalRound(&r, &s, 0, .plain)
        return r
    }
}
