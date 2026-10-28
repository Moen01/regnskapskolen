import RegnskapKit
import SwiftUI

/// Spill: routes between the map, a region, a running game, a round summary and the collection.
struct GameHubView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.lightning != nil {
            LightningRoundView()
        } else if store.drill != nil {
            DebitCreditView()
        } else if let summary = store.lastSummary {
            RoundSummaryView(summary: summary, newBadges: store.newBadges, isRecord: store.lastWasRecord,
                             onAgain: { summary.game == .lynrunde ? store.startLightning() : store.startDrill() },
                             onHub: { store.lastSummary = nil })
        } else if let region = store.currentRegion {
            RegionView(region: region)
        } else {
            MapView()
        }
    }

}

/// One game on the hub: what it is, the record, an optional setting, and the button that starts it.
struct GameCard<Setting: View>: View {
    let title: String
    let text: String
    let best: Int?
    let disabledReason: String?
    let action: () -> Void
    @ViewBuilder let setting: Setting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Text(best.map { "Rekord: \($0)" } ?? "Ingen runde ennå").font(.caption).monospacedDigit()
            setting
            Button("Spill", action: action).buttonStyle(.borderedProminent).tint(.skole).disabled(disabledReason != nil)
            if let disabledReason { Text(disabledReason).font(.caption).foregroundStyle(Color.warn) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
