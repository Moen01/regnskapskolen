import Foundation

public struct PostingAttemptLine: Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var konto: String
    public var debet: Decimal?
    public var kredit: Decimal?

    public init(konto: String = "", debet: Decimal? = nil, kredit: Decimal? = nil) {
        self.konto = konto; self.debet = debet; self.kredit = kredit
    }

    var isEmpty: Bool { konto.isEmpty && debet == nil && kredit == nil }
}

public typealias PostingAttempt = [PostingAttemptLine]

/// The feedback ladder for "før bilaget", in order: a line with both sides, not balanced, right
/// account on the wrong side, right side with the wrong amount, an account that should not be
/// there, a missing line (side only), and finally correct. Lines are summed per account and side.
public enum PostingChecker {
    public static func check(_ attempt: PostingAttempt, against posting: Posting) -> Verdict {
        let lines = attempt.filter { !$0.isEmpty }
        if lines.contains(where: { $0.debet != nil && $0.kredit != nil && $0.debet != 0 && $0.kredit != 0 }) {
            return .wrong(["En linje kan ha debet eller kredit, ikke begge."])
        }
        let used = lines.filter { !$0.konto.isEmpty && (($0.debet ?? 0) != 0 || ($0.kredit ?? 0) != 0) }
        let debet = used.reduce(Decimal(0)) { $0 + ($1.debet ?? 0) }
        let kredit = used.reduce(Decimal(0)) { $0 + ($1.kredit ?? 0) }
        if debet == 0 || kredit == 0 {
            return .wrong(["Legg til minst én debetlinje og én kreditlinje."])
        }
        if debet != kredit {
            return .wrong(["Bilaget balanserer ikke. Differanse: \(NorwegianFormat.kroner(abs(debet - kredit))) kr."])
        }

        // Sum the attempt per (account, side), mapping alternative accounts onto the fasit account.
        var attemptSums: [String: [Side: Decimal]] = [:]
        for line in used {
            let konto = posting.fasit.first { $0.alt.contains(line.konto) }?.konto ?? line.konto
            if let d = line.debet, d != 0 { attemptSums[konto, default: [:]][.debet, default: 0] += d }
            if let k = line.kredit, k != 0 { attemptSums[konto, default: [:]][.kredit, default: 0] += k }
        }
        var expected: [String: [Side: Decimal]] = [:]
        for line in posting.fasit { expected[line.konto, default: [:]][line.side, default: 0] += line.belop }

        var messages: [String] = []
        var missingSides: [Side] = []
        for (konto, sides) in expected.sorted(by: { $0.key < $1.key }) {
            for (side, amount) in sides.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let got = attemptSums[konto] ?? [:]
                if let onSide = got[side] {
                    if onSide != amount { messages.append("Konto \(konto): riktig side, feil beløp.") }
                } else if got[side.other] != nil {
                    messages.append("Konto \(konto): riktig konto, feil side.")
                } else {
                    missingSides.append(side)
                }
            }
        }
        for (konto, sides) in attemptSums.sorted(by: { $0.key < $1.key }) where expected[konto] == nil {
            _ = sides
            messages.append("Konto \(konto) skal ikke være med her.")
        }
        for side in Set(missingSides).sorted(by: { $0.rawValue < $1.rawValue }) {
            messages.append("Det mangler en linje på \(side == .debet ? "debetsiden" : "kreditsiden").")
        }
        if messages.isEmpty {
            return .right("Riktig! Debet \(NorwegianFormat.kroner(debet)) = kredit \(NorwegianFormat.kroner(kredit)).")
        }
        let total = Double(expected.values.map(\.count).reduce(0, +))
        let wrong = Double(messages.count)
        return .wrong(messages, score: max(0, (total - wrong) / max(total, 1)))
    }
}
