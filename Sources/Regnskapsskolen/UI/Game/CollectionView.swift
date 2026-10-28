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

/// The collection: every creature per region, caught ones as cards that flip to their rule, wild ones as silhouettes.
struct CollectionView: View {
    @Environment(AppStore.self) private var store
    @State private var tema: String?
    @State private var flipped: Set<String> = []

    private var regions: [Region] { store.regions.filter { !$0.isEmpty } }
    private var region: Region? { regions.first { $0.tema == tema } ?? regions.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeader(title: "Samling", subtitle: "\(store.collectionTotal) av \(store.pool.count) fanget")
                    Spacer()
                    Button("Tilbake") { store.showCollection = false }
                }
                badges
                Picker("Region", selection: Binding(get: { region?.tema ?? "" }, set: { tema = $0 })) {
                    ForEach(regions) { Text($0.navn).tag($0.tema) }
                }
                .pickerStyle(.menu).labelsHidden()
                if let region {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(region.puzzles) { puzzle in
                            let stage = Stage.of(box: store.progress.puzzles[puzzle.id]?.box)
                            Button { if stage != .vill { toggle(puzzle.id) } } label: {
                                CreatureCard(puzzle: puzzle, stage: stage, theme: region.theme, topic: store.topic(puzzle.tema)?.navn ?? puzzle.tema, flipped: flipped.contains(puzzle.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func toggle(_ id: String) { if flipped.contains(id) { flipped.remove(id) } else { flipped.insert(id) } }

    private var badges: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(Badges.all) { badge in
                let earned = store.progress.game.badges[badge.id]
                VStack(spacing: 3) {
                    Image(systemName: badge.symbol).font(.title3)
                    Text(badge.navn).font(.caption2).lineLimit(1)
                }
                .foregroundStyle(earned == nil ? Color.secondary.opacity(0.4) : Color.skole)
                .frame(maxWidth: .infinity).padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .help(badge.beskrivelse + (earned.map { " · tjent \(NorwegianFormat.date($0.date))" } ?? ""))
            }
        }
    }
}

/// One creature: the front shows who it is, the back the rule it stands on.
struct CreatureCard: View {
    let puzzle: Puzzle
    let stage: Stage
    let theme: RegionTheme
    let topic: String
    let flipped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if stage == .vill {
                Image(systemName: "questionmark").font(.title).foregroundStyle(.secondary)
                Text("?").font(.headline).foregroundStyle(.secondary)
                Text(String(repeating: "★", count: puzzle.vanskelighet)).foregroundStyle(Color.warn)
            } else if flipped {
                Text(puzzle.oppgave).font(.caption).lineLimit(3)
                ForEach(puzzle.lov, id: \.self) { LawBadge(law: $0) }
                Text(puzzle.forklaring.components(separatedBy: "\n\n").first ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(4)
            } else {
                Image(systemName: theme.symbol).font(.title).foregroundStyle(Color.theme(theme.farge))
                Text(puzzle.tittel).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    Pill(text: topic, color: Color.theme(theme.farge))
                    Text(String(repeating: "★", count: puzzle.vanskelighet)).foregroundStyle(Color.warn)
                }
                Pill(text: stage.navn, color: .skole)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.quaternary.opacity(stage == .vill ? 0.3 : 0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
