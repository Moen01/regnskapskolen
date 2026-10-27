import RegnskapKit
import SwiftUI

/// The check's outcome in the ladder's words.
struct VerdictView: View {
    let verdict: Verdict

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: verdict.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(verdict.correct ? Color.ok : Color.bad)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(verdict.messages, id: \.self) { Text($0) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((verdict.correct ? Color.ok : Color.bad).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The correct answer, shown after "Vis fasit".
struct AnswerView: View {
    let puzzle: Puzzle
    var rates: [MVARate] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fasit").font(.headline)
            switch puzzle.payload {
            case .posting(let p):
                ForEach(Array(p.fasit.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text("\(line.konto) \(p.kontoer.first { $0.nr == line.konto }?.navn ?? "")")
                        Spacer()
                        Text(line.side.navn).foregroundStyle(line.side == .debet ? Color.debet : Color.kredit)
                        Text(NorwegianFormat.kroner(line.belop)).monospacedDigit().frame(width: 110, alignment: .trailing)
                    }
                }
            case .classify(let p):
                ForEach(Array(p.elementer.enumerated()), id: \.offset) { _, item in MarkdownText("\(item.tekst) → \(item.svar)") }
            case .spot(let p):
                ForEach(Array(p.elementer.enumerated()).filter { $0.element.feil }, id: \.offset) { _, item in
                    MarkdownText(item.tekst + (item.hvorfor.map { " – \($0)" } ?? ""))
                }
            case .number(let p):
                Text("\(NorwegianFormat.kroner(p.svar, decimals: Double(NSDecimalNumber(decimal: p.svar).intValue) == NSDecimalNumber(decimal: p.svar).doubleValue ? 0 : 2))\(p.enhet.map { " \($0)" } ?? "")")
            case .quiz(let p):
                Text(p.alternativer.indices.contains(p.svar) ? p.alternativer[p.svar] : "")
            case .case(let p):
                Text("\(p.svar) – \(p.valg.first { $0.nokkel == p.svar }?.tekst ?? "")")
            case .vat(let p):
                Text("Behandling: \(rates.first { $0.kode == p.fasit.behandling }?.navn ?? p.fasit.behandling)")
                if let fradrag = p.fasit.fradrag { Text("Fradragsrett: \(fradrag ? "ja" : "nei")") }
            case .deadline(let p):
                Text(NorwegianFormat.date(p.fasit.date))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skole.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
