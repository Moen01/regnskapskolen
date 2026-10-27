import RegnskapKit
import SwiftUI

/// The numbers after a round, the record mark, new badges, and the two ways on.
struct RoundSummaryView: View {
    let summary: RoundSummary
    let newBadges: [Badge]
    let isRecord: Bool
    let onAgain: () -> Void
    let onHub: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Runden er over", subtitle: summary.game.navn)
            if isRecord { Pill(text: "Ny rekord!", color: .ok) }
            HStack(spacing: 12) {
                StatTile(value: "\(summary.score)", label: "poeng", symbol: "star", color: .skole)
                StatTile(value: "\(summary.correct)/\(summary.answered)", label: "riktige av besvarte", symbol: "target", color: .ok)
                StatTile(value: String(format: "×%.2f", summary.bestCombo), label: "beste combo", symbol: "flame", color: .orange)
                StatTile(value: "\(summary.xp)", label: "XP tjent", symbol: "sparkles", color: .debet)
            }
            ForEach(newBadges) { badge in
                Label("Nytt merke: \(badge.navn)", systemImage: badge.symbol).foregroundStyle(Color.skole)
            }
            HStack(spacing: 10) {
                Button("Spill igjen", action: onAgain).buttonStyle(.borderedProminent).tint(.skole).keyboardShortcut(.return, modifiers: [])
                Button("Til spill", action: onHub)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 820, alignment: .leading)
    }
}
