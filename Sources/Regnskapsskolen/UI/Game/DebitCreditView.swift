import RegnskapKit
import SwiftUI

/// Debet eller kredit?: one account card at a time, two big buttons, arrow keys or D and K.
struct DebitCreditView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let round = store.drill {
            VStack(alignment: .leading, spacing: 20) {
                topBar(round)
                if let card = round.current {
                    Spacer(minLength: 0)
                    accountCard(card, wrong: isFeedback(round))
                    HStack(spacing: 16) {
                        answerButton("Debet", side: .debet, color: .debet, keys: [.leftArrow, "d"], locked: isFeedback(round))
                        answerButton("Kredit", side: .kredit, color: .kredit, keys: [.rightArrow, "k"], locked: isFeedback(round))
                    }
                    .frame(maxWidth: .infinity)
                    if case .feedback(let since) = round.phase { feedback(card, since: since) }
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func isFeedback(_ round: DebitCreditDrill) -> Bool {
        if case .feedback = round.phase { return true }
        return false
    }

    private func topBar(_ round: DebitCreditDrill) -> some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let left = Int(round.remaining(at: store.now).rounded(.up))
                Label("\(left) s", systemImage: "timer").monospacedDigit().foregroundStyle(left < 10 ? Color.bad : Color.primary)
            }
            Text("\(round.score) poeng").monospacedDigit()
            Pill(text: String(format: "×%.2f", round.combo.multiplier), color: .skole)
            Text("\(round.answered) besvart").foregroundStyle(.secondary).monospacedDigit()
            if round.lastCorrect == true, !isFeedback(round) { Pill(text: "Riktig", color: .ok).transition(.opacity) }
            Spacer()
            Button("Avbryt") { store.endRound() }
        }
        .font(.callout)
        .animation(.easeOut(duration: 0.3), value: round.answered)
    }

    private func accountCard(_ card: DrillCard, wrong: Bool) -> some View {
        VStack(spacing: 6) {
            Text(card.account.nr).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
            Text(card.account.navn).font(.title2)
            Text(card.increases ? "øker" : "minker").font(.title3).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bad, lineWidth: wrong ? 2 : 0))
    }

    private func answerButton(_ title: String, side: Side, color: Color, keys: [KeyEquivalent], locked: Bool) -> some View {
        Button { store.answerDrill(side) } label: {
            Text(title).font(.title3.weight(.semibold)).frame(minWidth: 160, minHeight: 56)
        }
        .buttonStyle(.borderedProminent).tint(color)
        .keyboardShortcut(keys[0], modifiers: [])
        .disabled(locked)
        // A second, invisible button carries the letter key; one button takes one shortcut.
        .background(Button("") { if !locked { store.answerDrill(side) } }.keyboardShortcut(keys[1], modifiers: []).buttonStyle(.plain).frame(width: 0, height: 0).opacity(0))
    }

    private func feedback(_ card: DrillCard, since: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ikke riktig", systemImage: "xmark.circle.fill").foregroundStyle(Color.bad).font(.headline)
            Text(card.explanation).font(.callout)
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Button("Neste") { store.nextInRound() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent).tint(.skole)
                    .disabled(store.now - since < DebitCreditDrill.feedbackMinimum)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bad.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
