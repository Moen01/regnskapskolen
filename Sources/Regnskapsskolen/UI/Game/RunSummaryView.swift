import RegnskapKit
import SwiftUI

/// After a run in a region: what was caught and lost, the XP, the gym badge, and the way on.
struct RunSummaryView: View {
    let summary: RunSummary
    let newBadges: [Badge]
    let onRegion: () -> Void
    let onMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: summary.hpLeft == 0 ? "Kunden byttet regnskapsfører" : "Økten er over",
                          subtitle: summary.hpLeft == 0 ? "Pengene tok slutt. Det du fanget beholder du; regionen mistet en fjerdedel av framgangen." : "Framgangen i regionen er lagret.")
            HStack(spacing: 12) {
                StatTile(value: "\(summary.caught)", label: "fanget", symbol: "checkmark.seal", color: .ok)
                StatTile(value: "\(summary.escaped)", label: "flyktet", symbol: "arrow.uturn.left", color: .bad)
                StatTile(value: "\(summary.xp)", label: "XP tjent", symbol: "sparkles", color: .debet)
                StatTile(value: "\(NorwegianFormat.kroner(Decimal(summary.hpLeft), decimals: 0))", label: "kr igjen", symbol: "heart", color: .kredit)
            }
            if summary.gymBadge { Label("Gym-merket er ditt!", systemImage: "crown.fill").foregroundStyle(Color.skole).font(.headline) }
            ForEach(newBadges) { badge in Label("Nytt merke: \(badge.navn)", systemImage: badge.symbol).foregroundStyle(Color.skole) }
            HStack(spacing: 10) {
                Button("Tilbake til regionen", action: onRegion).buttonStyle(.borderedProminent).tint(.skole)
                Button("Til kartet", action: onMap)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 820, alignment: .leading)
    }
}
