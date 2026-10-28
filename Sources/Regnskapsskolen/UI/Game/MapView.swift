import RegnskapKit
import SwiftUI

extension Color {
    /// A region theme's colour name from Kit, mapped to the app's palette.
    static func theme(_ name: String) -> Color {
        switch name {
        case "skole": .skole
        case "debet": .debet
        case "kredit": .kredit
        case "ok": .ok
        case "warn": .warn
        case "orange": .orange
        default: .secondary
        }
    }
}

/// The world: the level, twelve regions, the training grounds, the weekly challenge, the collection.
struct MapView: View {
    @Environment(AppStore.self) private var store

    private var game: GameProgress { store.progress.game }
    private var level: Level { XP.level(for: game.xp) }
    private var topics: [String] { LightningRound.topics(in: store.pool) }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Paragrafjakten", subtitle: "Fang reglene. Edge casene vokter regionene.")
                levelCard
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(store.regions) { region in
                        Button { if region.unlocked, !region.isEmpty { store.openRegion(region.tema) } } label: { RegionCard(region: region) }
                            .buttonStyle(.plain)
                            .disabled(!region.unlocked || region.isEmpty)
                    }
                }
                Text("Treningsplassene").font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    GameCard(title: "Arena", text: "Lynrunde: 90 sekunder med quiz, mva og saker. Combo for riktige på rad.",
                             best: store.bestScore(for: .lynrunde, tema: store.lynrundeTema),
                             disabledReason: LightningRound.eligible(pool: store.pool, tema: store.lynrundeTema).isEmpty ? "Ingen oppgaver i dette temaet" : nil,
                             action: store.startLightning) {
                        Picker("Tema", selection: $store.lynrundeTema) {
                            Text("Alle temaer").tag(nil as String?)
                            ForEach(topics, id: \.self) { Text(store.topic($0)?.navn ?? $0).tag(Optional($0)) }
                        }
                    }
                    GameCard(title: "Dojo", text: "Debet eller kredit? 60 sekunder med kontoplanen. Piltaster eller D og K.",
                             best: store.bestScore(for: .debetKredit, tema: nil), disabledReason: nil, action: store.startDrill) { EmptyView() }
                    weeklyCard
                }
                HStack {
                    Button("Samling", systemImage: "square.grid.3x3") { store.showCollection = true }
                    Text("\(store.collectionTotal) av \(store.pool.count) fanget").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if !store.newBadges.isEmpty {
                    Label("Nytt merke: " + store.newBadges.map(\.navn).joined(separator: ", "), systemImage: store.newBadges[0].symbol).foregroundStyle(Color.skole)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
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

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ukens utfordring").font(.headline)
            Text("Uke \(store.todayKey.isoWeek.week): ti oppgaver, de samme for alle. Del koden med kollegaene.").font(.callout).foregroundStyle(.secondary)
            if let code = store.weeklyCode {
                Text(code).font(.body.monospacedDigit().weight(.semibold))
                Button("Kopier") { Clipboard.copy(code) }
            } else {
                Button("Spill", action: store.startWeekly).buttonStyle(.borderedProminent).tint(.skole)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One region on the map: symbol, name, how much is caught, the lock or the gym badge.
struct RegionCard: View {
    let region: Region

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: region.theme.symbol).font(.title2).foregroundStyle(Color.theme(region.theme.farge))
                Spacer()
                if region.gymBadge != nil { Image(systemName: "crown.fill").foregroundStyle(Color.skole).help("Gym-merket er tatt") }
                else if !region.unlocked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
            }
            Text(region.navn).font(.body.weight(.semibold)).lineLimit(2)
            if region.isEmpty {
                Text("Under bygging").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(region.caught) av \(region.puzzles.count) fanget").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                MasteryBar(value: Double(region.mastered) / Double(max(1, region.puzzles.count)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(.quaternary.opacity(region.unlocked && !region.isEmpty ? 0.5 : 0.25), in: RoundedRectangle(cornerRadius: 10))
        .opacity(region.unlocked && !region.isEmpty ? 1 : 0.6)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
