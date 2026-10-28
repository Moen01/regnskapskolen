import RegnskapKit
import SwiftUI

/// One region: the client's money, the meter towards the gym leader, the creatures that live here.
struct RegionView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation
    let region: Region

    private var hp: Int { store.run?.hp ?? RegionRun.hp }
    private var damage: Int { store.run?.damage ?? store.progress.game.regionDamage[region.tema] ?? 0 }
    private var gymReady: Bool { store.run?.gymReady ?? (damage >= region.damageTarget && region.gymBadge == nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: region.theme.symbol).font(.largeTitle).foregroundStyle(Color.theme(region.theme.farge))
                    SectionHeader(title: region.navn, subtitle: region.theme.setning)
                    Spacer()
                    Button("Tilbake til kartet") { store.closeRegion() }
                }
                meter("Kundens penger", value: hp, max: RegionRun.hp, color: hp < 3000 ? .kredit : .ok, text: "\(NorwegianFormat.kroner(Decimal(hp), decimals: 0)) kr")
                meter("Mot gym-lederen", value: min(damage, max(1, region.damageTarget)), max: max(1, region.damageTarget), color: .skole, text: "\(damage) av \(region.damageTarget)")
                if region.gymBadge != nil {
                    Label("Gym-merket er ditt", systemImage: "crown.fill").foregroundStyle(Color.skole)
                } else if gymReady {
                    Label("Gym-lederen venter: \(region.gymLeader?.tittel ?? "")", systemImage: "flag.checkered").foregroundStyle(Color.warn)
                }
                HStack(spacing: 10) {
                    Button(store.run == nil ? "Neste møte" : "Fortsett") { if store.run == nil { store.startRun() } }
                        .buttonStyle(.borderedProminent).tint(.skole).disabled(region.isEmpty)
                    if region.tema == "reskontro-bank" {
                        Button("Gå inn i dungeon", systemImage: "door.left.hand.open") {
                            if let bank = store.sandboxCases.first(where: { $0.id == "bank-001" }) { store.startCase(bank) }
                            navigation.section = .sandbox
                        }
                    }
                }
                Text("Skapningene her").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(region.puzzles) { puzzle in
                        let stage = Stage.of(box: store.progress.puzzles[puzzle.id]?.box)
                        VStack(spacing: 4) {
                            Image(systemName: stage == .vill ? "questionmark" : region.theme.symbol).font(.title3)
                            Text(stage == .vill ? "?" : puzzle.tittel).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                            Pill(text: puzzle.id == region.gymLeader?.id ? "Gym-leder" : stage.navn, color: puzzle.id == region.gymLeader?.id ? .warn : (stage == .vill ? .secondary : .skole))
                        }
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .opacity(stage == .vill ? 0.6 : 1)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func meter(_ title: String, value: Int, max: Int, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Text(text).font(.caption.monospacedDigit()) }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: Swift.max(0, geometry.size.width * CGFloat(value) / CGFloat(max)))
                }
            }
            .frame(height: 8)
        }
    }
}
