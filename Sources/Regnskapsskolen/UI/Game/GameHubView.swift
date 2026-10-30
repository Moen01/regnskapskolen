import RegnskapKit
import SwiftUI

/// Spill: routes between the town, a fight in town, Paragrafjakten (map, region, fight), a round and the collection.
struct GameHubView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.lightning != nil {
            LightningRoundView()
        } else if store.drill != nil {
            DebitCreditView()
        } else if let summary = store.lastSummary {
            RoundSummaryView(summary: summary, newBadges: store.newBadges, isRecord: store.lastWasRecord, weeklyCode: store.lastWasWeekly ? store.weeklyCode : nil,
                             onAgain: { summary.game == .lynrunde ? store.startLightning() : store.startDrill() },
                             onHub: { store.lastSummary = nil })
        } else if store.showCollection {
            CollectionScreen()
        } else if let run = store.bilagRun, run.current != nil {
            BattleScreen(host: Self.isCase(run) ? .kundesak(store) : .bilag(store))
        } else if store.townRun?.current != nil {
            BattleScreen(host: .townTrial(store))
        } else if store.showTraining {
            training
        } else {
            TownScreen()
        }
    }

    /// Paragrafjakten, opened from the town menu: the map, a region, a fight, the run's summary.
    @ViewBuilder
    private var training: some View {
        if store.run?.current != nil {
            BattleScreen(host: .adventure(store))
        } else if let summary = store.lastRunSummary {
            SummaryScreen(summary: summary, newBadges: store.newBadges, onRegion: { store.lastRunSummary = nil }, onMap: { store.closeRegion() })
        } else if let region = store.currentRegion {
            RegionScreen(region: region)
        } else {
            MapScreen()
        }
    }

    private static func isCase(_ run: BilagRun) -> Bool {
        if case .kundesak = run.kind { return true }
        return false
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
