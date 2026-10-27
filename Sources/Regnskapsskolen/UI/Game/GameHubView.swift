import RegnskapKit
import SwiftUI

/// Spill: the level and XP, the badges, and one card per game to start a round from.
struct GameHubView: View {
    @Environment(AppStore.self) private var store

    private var game: GameProgress { store.progress.game }
    private var level: Level { XP.level(for: game.xp) }
    private var topics: [String] { LightningRound.topics(in: store.pool) }
    private var lightningPoolIsEmpty: Bool { LightningRound.eligible(pool: store.pool, tema: store.lynrundeTema).isEmpty }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Spill", subtitle: "Korte runder som teller i boksene og gir XP")
                levelCard
                Text("Merker").font(.headline)
                badges
                HStack(alignment: .top, spacing: 12) {
                    GameCard(title: GameKind.lynrunde.navn, text: "90 sekunder med quiz, mva og saker. Riktig svar bygger combo; feil viser forklaringen.",
                             best: store.bestScore(for: .lynrunde, tema: store.lynrundeTema), disabledReason: lightningPoolIsEmpty ? "Ingen oppgaver i dette temaet" : nil,
                             action: store.startLightning) {
                        Picker("Tema", selection: $store.lynrundeTema) {
                            Text("Alle temaer").tag(nil as String?)
                            ForEach(topics, id: \.self) { Text(store.topic($0)?.navn ?? $0).tag(Optional($0)) }
                        }
                    }
                    GameCard(title: GameKind.debetKredit.navn, text: "60 sekunder: øker kontoen på debet eller kredit? Piltaster eller D og K.",
                             best: store.bestScore(for: .debetKredit, tema: nil), disabledReason: nil, action: store.startDrill) { EmptyView() }
                }
                if !store.newBadges.isEmpty {
                    Label("Nytt merke: " + store.newBadges.map(\.navn).joined(separator: ", "), systemImage: store.newBadges[0].symbol)
                        .foregroundStyle(Color.skole)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        // Shown once: the next visit starts clean.
        .onDisappear { store.newBadges = [] }
    }

    private var levelCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.circle.fill").font(.largeTitle).foregroundStyle(Color.skole)
            VStack(alignment: .leading, spacing: 6) {
                Text(level.navn).font(.title3.weight(.semibold))
                Text("\(game.xp) XP").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if let next = level.neste, let nextLevel = XP.levels.first(where: { $0.terskel == next }) {
                    MasteryBar(value: Double(game.xp - level.terskel) / Double(next - level.terskel))
                    Text("\(next - game.xp) til \(nextLevel.navn)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var badges: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Badges.all) { badge in
                let earned = game.badges[badge.id]
                VStack(spacing: 4) {
                    Image(systemName: badge.symbol).font(.title2)
                    Text(badge.navn).font(.caption)
                }
                .foregroundStyle(earned == nil ? Color.secondary.opacity(0.4) : Color.skole)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .help(badge.beskrivelse + (earned.map { " · tjent \(NorwegianFormat.date($0.date))" } ?? ""))
            }
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
