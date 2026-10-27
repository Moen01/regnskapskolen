import RegnskapKit
import SwiftUI

/// A radio-style row used by quiz and sak.
private struct ChoiceRow: View {
    let text: String
    let selected: Bool
    var state: ItemResult.State? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(color)
                MarkdownText(text).foregroundStyle(state == nil ? .primary : color)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch state {
        case .right: .ok
        case .wrong: .bad
        case .missed: .warn
        case nil: selected ? .skole : .secondary
        }
    }
}

/// Quiz: one question, one right alternative.
struct QuizView: View {
    let quiz: Quiz
    @Binding var selected: Int?
    var showAnswer = false
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(quiz.alternativer.enumerated()), id: \.offset) { index, text in
                ChoiceRow(text: text, selected: selected == index, state: state(index)) { selected = index }
            }
        }
        .disabled(disabled)
    }

    private func state(_ index: Int) -> ItemResult.State? {
        guard showAnswer else { return nil }
        if index == quiz.svar { return .right }
        return selected == index ? .wrong : nil
    }
}

/// Sak: a message from a colleague or client, the treatment to pick, then the clarifying questions.
struct CaseView: View {
    let sak: Case
    @Binding var selected: String?
    var showAnswer = false
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let fra = sak.fra { Text(fra).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                MarkdownText(sak.melding)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text("Hva gjør du?").font(.headline)
            ForEach(sak.valg) { choice in
                ChoiceRow(text: "\(choice.nokkel). \(choice.tekst)", selected: selected == choice.nokkel, state: state(choice.nokkel)) { selected = choice.nokkel }
            }
            if showAnswer {
                if !sak.sporsmal.isEmpty {
                    Text("Spørsmål å stille").font(.headline)
                    ForEach(sak.sporsmal, id: \.self) { Text("• \($0)") }
                }
                if let forslag = sak.forslag {
                    Text("Forslag til svar").font(.headline)
                    MarkdownText(forslag).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.skole.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .disabled(disabled)
    }

    private func state(_ key: String) -> ItemResult.State? {
        guard showAnswer else { return nil }
        if key == sak.svar { return .right }
        return selected == key ? .wrong : nil
    }
}

/// Klassifiser: a category per element.
struct ClassifyView: View {
    let classify: Classify
    @Binding var answers: [Int: String]
    var perItem: [ItemResult]? = nil
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(classify.elementer.enumerated()), id: \.offset) { index, item in
                let result = perItem?.first { $0.index == index }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        if let result { Image(systemName: icon(result.state)).foregroundStyle(color(result.state)) }
                        MarkdownText(item.tekst).frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Kategori", selection: Binding(get: { answers[index] ?? "" }, set: { answers[index] = $0.isEmpty ? nil : $0 })) {
                            Text("Velg…").tag("")
                            ForEach(classify.kategorier, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    if let note = result?.note { Text(note).font(.caption).foregroundStyle(color(result!.state)) }
                }
            }
        }
        .disabled(disabled)
    }
}

/// Finn feilene: mark the lines that are wrong.
struct SpotView: View {
    let spot: Spot
    @Binding var marked: Set<Int>
    var perItem: [ItemResult]? = nil
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heading = spot.overskrift { Text(heading).font(.headline) }
            ForEach(Array(spot.elementer.enumerated()), id: \.offset) { index, item in
                let result = perItem?.first { $0.index == index }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(get: { marked.contains(index) }, set: { if $0 { marked.insert(index) } else { marked.remove(index) } })) {
                        HStack(spacing: 6) {
                            if let result, result.state != .right || item.feil { Image(systemName: icon(result.state)).foregroundStyle(color(result.state)) }
                            MarkdownText(item.tekst)
                        }
                    }
                    .toggleStyle(.checkbox)
                    if let result, let note = result.note, result.state != .right || item.feil {
                        Text(note).font(.caption).foregroundStyle(color(result.state)).padding(.leading, 20)
                    }
                }
            }
            Text("Kryss av linjene som er feil. Ingen kryss betyr at alt er riktig.").font(.caption).foregroundStyle(.secondary)
        }
        .disabled(disabled)
    }
}

/// Mva: the treatment and, when the puzzle asks, the deduction right.
struct VATView: View {
    let vat: VAT
    let rates: [MVARate]
    @Binding var behandling: String?
    @Binding var fradrag: Bool?
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkdownText(vat.transaksjon).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Picker("Mva-behandling", selection: Binding(get: { behandling ?? "" }, set: { behandling = $0.isEmpty ? nil : $0 })) {
                Text("Velg…").tag("")
                ForEach(rates, id: \.kode) { rate in
                    Text(rate.prosent.map { "\(rate.navn) (\($0) %)" } ?? rate.navn).tag(rate.kode)
                }
            }
            .frame(maxWidth: 420)
            if vat.fasit.fradrag != nil {
                Picker("Fradragsrett", selection: Binding(get: { fradrag.map { $0 ? "ja" : "nei" } ?? "" }, set: { fradrag = $0.isEmpty ? nil : $0 == "ja" })) {
                    Text("Velg…").tag("")
                    Text("Ja, inngående mva kan trekkes fra").tag("ja")
                    Text("Nei, ingen fradragsrett").tag("nei")
                }
                .frame(maxWidth: 420)
            }
        }
        .disabled(disabled)
    }
}

private func icon(_ state: ItemResult.State) -> String {
    switch state {
    case .right: "checkmark.circle.fill"
    case .wrong: "xmark.circle.fill"
    case .missed: "exclamationmark.circle.fill"
    }
}

private func color(_ state: ItemResult.State) -> Color {
    switch state {
    case .right: .ok
    case .wrong: .bad
    case .missed: .warn
    }
}
