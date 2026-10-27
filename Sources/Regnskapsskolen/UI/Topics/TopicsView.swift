import RegnskapKit
import SwiftUI

/// Øv: topics with mastery bars on the left, the chosen topic's puzzles on the right.
struct TopicsView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: String?

    private var topics: [Topic] { store.library?.topics ?? [] }

    var body: some View {
        HStack(spacing: 0) {
            List(topics, selection: $selected) { topic in
                TopicRow(topic: topic, mastery: store.mastery(topic.id), seen: seen(topic.id), total: puzzles(topic.id).count)
                    .tag(topic.id)
            }
            .listStyle(.inset)
            .frame(width: 320)
            Divider()
            if let selected, let topic = store.topic(selected) {
                puzzleList(topic)
            } else {
                ContentUnavailableView("Velg et tema", systemImage: "list.bullet.rectangle", description: Text("Oppgavene sorteres etter vanskelighet. Resultatene teller for boksene, ikke for dagens sett."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = topics.first?.id } }
    }

    private func puzzles(_ tema: String) -> [Puzzle] { store.library?.puzzles(tema: tema, includeDrafts: store.settings.showDrafts) ?? [] }
    private func seen(_ tema: String) -> Int { puzzles(tema).filter { store.state(of: $0) != nil }.count }

    private func puzzleList(_ topic: Topic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: topic.navn, subtitle: topic.maal)
                let list = puzzles(topic.id)
                if list.isEmpty {
                    Text("Ingen oppgaver i dette temaet ennå. Be Claude om noen med /ny-oppgave \(topic.id).").foregroundStyle(.secondary)
                }
                ForEach(list) { puzzle in
                    Button { store.open(puzzle, fromToday: false) } label: {
                        HStack(spacing: 10) {
                            BoxBadge(box: store.state(of: puzzle)?.box, seen: store.state(of: puzzle) != nil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(puzzle.tittel).font(.body.weight(.medium))
                                Text("\(puzzle.kind.navn) · nivå \(puzzle.vanskelighet)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if puzzle.isEdgeCase { Pill(text: "edge case", color: .warn) }
                            if puzzle.status == .utkast || puzzle.generert { Pill(text: "utkast", color: .warn) }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TopicRow: View {
    let topic: Topic
    let mastery: Double
    let seen: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(topic.navn)
                Spacer()
                Text("\(seen)/\(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            MasteryBar(value: mastery)
        }
        .padding(.vertical, 3)
    }
}

/// Share of a topic's puzzles in box 3 or higher.
struct MasteryBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.skole).frame(width: max(0, geometry.size.width * value))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Mestring \(Int(value * 100)) prosent")
    }
}

/// The Leitner box a puzzle sits in: 0 (just learnt or failed) to 4 (every three weeks).
struct BoxBadge: View {
    let box: Int?
    let seen: Bool

    var body: some View {
        Text(seen ? "boks \(box ?? 0)" : "ny")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
            .frame(width: 52)
    }

    private var color: Color {
        guard seen, let box else { return .secondary }
        switch box {
        case 0: return .bad
        case 1, 2: return .warn
        default: return .ok
        }
    }
}
