import RegnskapKit
import SwiftUI

/// Lynrunden: the clock, score and combo on top, one quick puzzle in the middle, and the explanation
/// after a wrong answer. Every answer goes to the store; the view only shows the round's state.
struct LightningRoundView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let round = store.lightning {
            VStack(alignment: .leading, spacing: 16) {
                topBar(round)
                if let puzzle = round.current {
                    Text(puzzle.tittel).font(.title2.weight(.semibold))
                    MarkdownText(puzzle.oppgave)
                    LightningQuestion(puzzle: puzzle, locked: round.phase != .question) { store.answerLightning($0) }
                        .id(puzzle.id)
                    if case .feedback(let since) = round.phase { feedback(puzzle, since: since) }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func topBar(_ round: LightningRound) -> some View {
        HStack(spacing: 12) {
            if round.limit.isInfinite {
                Label("Spørsmål \(round.answered + 1) av \(round.answered + round.queue.count)", systemImage: "list.number").monospacedDigit()
            } else {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let left = Int(round.remaining(at: store.now).rounded(.up))
                    Label("\(left) s", systemImage: "timer").monospacedDigit().foregroundStyle(left < 10 ? Color.bad : Color.primary)
                }
            }
            Text("\(round.score) poeng").monospacedDigit()
            Pill(text: String(format: "×%.2f", round.combo.multiplier), color: .skole)
            Text("\(round.answered) besvart").foregroundStyle(.secondary).monospacedDigit()
            if round.lastEvent?.verdict.correct == true, round.phase == .question {
                Pill(text: "Riktig", color: .ok).transition(.opacity)
            }
            Spacer()
            Button("Avbryt") { store.endRound() }
        }
        .font(.callout)
        .animation(.easeOut(duration: 0.3), value: round.answered)
    }

    private func feedback(_ puzzle: Puzzle, since: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ikke riktig", systemImage: "xmark.circle.fill").foregroundStyle(Color.bad).font(.headline)
            Text("Riktig svar: " + correctAnswer(puzzle)).font(.callout)
            MarkdownText(firstParagraph(puzzle.forklaring)).font(.callout)
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Button("Neste") { store.nextInRound() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent).tint(.skole)
                    .disabled(store.now - since < LightningRound.feedbackMinimum)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bad.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func correctAnswer(_ puzzle: Puzzle) -> String {
        switch puzzle.payload {
        case .quiz(let q): q.alternativer.indices.contains(q.svar) ? q.alternativer[q.svar] : ""
        case .case(let c): c.valg.first { $0.nokkel == c.svar }?.tekst ?? c.svar
        case .vat(let v): "behandling \(v.fasit.behandling)" + (v.fasit.fradrag.map { $0 ? ", fradrag ja" : ", fradrag nei" } ?? "")
        default: ""
        }
    }

    private func firstParagraph(_ text: String) -> String {
        text.components(separatedBy: "\n\n").first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? text
    }
}

/// The answer input for one puzzle. Its state is per puzzle: the parent gives it `.id(puzzle.id)`.
private struct LightningQuestion: View {
    @Environment(AppStore.self) private var store
    let puzzle: Puzzle
    let locked: Bool
    let onAnswer: (PuzzleAttempt) -> Void
    @State private var quizChoice: Int?
    @State private var caseChoice: String?

    var body: some View {
        switch puzzle.payload {
        case .quiz(let q):
            QuizView(quiz: q, selected: $quizChoice, showAnswer: locked, disabled: locked)
                .onChange(of: quizChoice) { if let choice = quizChoice, !locked { onAnswer(.quiz(choice)) } }
            // 1–4 pick an alternative from the keyboard.
            ForEach(Array(q.alternativer.indices.prefix(4)), id: \.self) { index in
                Button("") { if !locked { quizChoice = index } }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0)
            }
        case .case(let c):
            CaseView(sak: c, selected: $caseChoice, showAnswer: locked, disabled: locked)
                .onChange(of: caseChoice) { if let choice = caseChoice, !locked { onAnswer(.case(choice)) } }
        case .vat(let v):
            LightningVATView(vat: v, rates: store.library?.rates.mvaSatser ?? [], locked: locked, onAnswer: onAnswer)
        default:
            Text("Oppgavetypen passer ikke i Lynrunden.").foregroundStyle(.secondary)
        }
    }
}

/// Mva in two steps: the treatment, then the deduction when the puzzle asks for it.
private struct LightningVATView: View {
    let vat: VAT
    let rates: [MVARate]
    let locked: Bool
    let onAnswer: (PuzzleAttempt) -> Void
    @State private var behandling: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vat.transaksjon)
            Text("Behandling").font(.caption).foregroundStyle(.secondary)
            // One full-width row per code: the names must be readable on a 90-second clock.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rates, id: \.kode) { rate in
                    Button { pick(rate.kode) } label: {
                        HStack {
                            Text(rate.kode).font(.body.weight(.semibold).monospacedDigit()).frame(width: 72, alignment: .leading)
                            Text(rate.navn).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(behandling == rate.kode ? .skole : nil)
                }
            }
            .disabled(locked || behandling != nil)
            if behandling != nil, vat.fasit.fradrag != nil, !locked {
                Text("Fradrag for inngående mva?").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Ja") { onAnswer(.vat(behandling: behandling, fradrag: true)) }.buttonStyle(.borderedProminent).tint(.skole)
                    Button("Nei") { onAnswer(.vat(behandling: behandling, fradrag: false)) }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func pick(_ kode: String) {
        behandling = kode
        // The deduction is only asked when the fasit has an opinion on it; otherwise the treatment is the answer.
        if vat.fasit.fradrag == nil { onAnswer(.vat(behandling: kode, fradrag: nil)) }
    }
}
