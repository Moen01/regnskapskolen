import RegnskapKit
import SwiftUI

/// The day's set as cards; a card opens its puzzle in the detail pane.
struct TodayView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "I dag", subtitle: NorwegianFormat.date(store.todayKey.date))
                HStack(spacing: 12) {
                    Label("\(store.streak) dager på rad", systemImage: "flame").foregroundStyle(.orange)
                    if !store.today.isEmpty {
                        Pill(text: store.remainingToday == 0 ? "Alt gjort" : "\(store.remainingToday) igjen", color: store.remainingToday == 0 ? .ok : .skole)
                    }
                }
                if store.today.isEmpty {
                    ContentUnavailableView("Ingen oppgaver i dag", systemImage: "tray", description: Text("Sjekk innholdsmappen i Innstillinger."))
                } else {
                    ForEach(store.today) { puzzle in
                        Button { store.open(puzzle, fromToday: true) } label: { PuzzleCard(puzzle: puzzle, state: state(puzzle)) }
                            .buttonStyle(.plain)
                    }
                    if store.remainingToday == 0 {
                        Label("Dagens oppgaver er gjort. Godt jobbet!", systemImage: "checkmark.seal.fill").foregroundStyle(Color.ok)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func state(_ puzzle: Puzzle) -> PuzzleCard.State {
        guard store.isCompletedToday(puzzle) else { return .ny }
        return (store.state(of: puzzle)?.box ?? 0) > 0 ? .riktig : .feil
    }
}

struct PuzzleCard: View {
    enum State { case ny, riktig, feil }
    @Environment(AppStore.self) private var store
    let puzzle: Puzzle
    let state: State

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(puzzle.tittel).font(.body.weight(.medium))
                Text("\(store.topic(puzzle.tema)?.navn ?? puzzle.tema) · \(puzzle.kind.navn) · nivå \(puzzle.vanskelighet)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if puzzle.isEdgeCase { Pill(text: "edge case", color: .warn) }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch state {
        case .ny: "circle"
        case .riktig: "checkmark.circle.fill"
        case .feil: "arrow.counterclockwise.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .ny: .secondary
        case .riktig: .ok
        case .feil: .warn
        }
    }
}
