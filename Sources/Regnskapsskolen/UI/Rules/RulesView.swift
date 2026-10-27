import RegnskapKit
import SwiftUI

/// Regler: the rule cards, searchable, with the Markdown body and the source link.
struct RulesView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: String?
    @State private var query = ""

    private var cards: [RuleCard] {
        let all = store.library?.rules ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.tittel.lowercased().contains(q) || $0.lov.lowercased().contains(q) || $0.paragrafer.joined(separator: " ").lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Søk i regler", text: $query).textFieldStyle(.roundedBorder).padding(10)
                List(cards, selection: $selected) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.tittel)
                        Text("\(card.lov) \(card.paragrafer.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(card.id)
                }
                .listStyle(.inset)
            }
            .frame(width: 320)
            Divider()
            if let selected, let card = (store.library?.rules ?? []).first(where: { $0.id == selected }) {
                RuleCardView(card: card)
            } else {
                ContentUnavailableView("Velg en regel", systemImage: "book.closed", description: Text("Korte kort om lovene oppgavene bygger på."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = cards.first?.id } }
    }
}

struct RuleCardView: View {
    @Environment(AppStore.self) private var store
    let card: RuleCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: card.tittel, subtitle: "\(card.lov) \(card.paragrafer.joined(separator: ", "))")
                if let topic = store.topic(card.tema) { Pill(text: topic.navn, color: .skole) }
                MarkdownBlocksView(text: card.body)
                if let kilde = card.kilde, let url = URL(string: kilde) {
                    Link(destination: url) { Label("Kilde: \(url.host() ?? kilde)", systemImage: "arrow.up.right.square") }.font(.callout)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Headings, paragraphs, lists and tables from a rule card body.
struct MarkdownBlocksView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let heading):
                    MarkdownText(heading).font(level <= 2 ? .title3.weight(.semibold) : .headline)
                case .paragraph(let paragraph):
                    MarkdownText(paragraph)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); MarkdownText(item) }
                        }
                    }
                case .table(let header, let rows):
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, cell in MarkdownText(cell).font(.caption.weight(.semibold)).foregroundStyle(.secondary) } }
                        Divider()
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in MarkdownText(cell) } }
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
