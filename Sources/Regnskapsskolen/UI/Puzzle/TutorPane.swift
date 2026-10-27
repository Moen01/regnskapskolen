import RegnskapKit
import SwiftUI

struct TutorExchange: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

/// Claude's corner under a puzzle: the explanation, a question field and "Vanskeligere oppgave".
struct TutorPane: View {
    @Environment(AppStore.self) private var store
    let puzzle: Puzzle
    let explanation: String?
    @State private var question = ""
    @State private var exchanges: [TutorExchange] = []
    @State private var session: String?
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Claude", systemImage: "sparkles").font(.headline).foregroundStyle(Color.skole)
            if let explanation { MarkdownText(explanation).textSelection(.enabled) }
            ForEach(exchanges) { exchange in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exchange.question).font(.callout.weight(.semibold))
                    MarkdownText(exchange.answer).textSelection(.enabled)
                }
            }
            if store.tutorBusy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Claude tenker…").foregroundStyle(.secondary) }
            }
            if let error = store.tutorError { Text(error).font(.caption).foregroundStyle(Color.bad) }
            HStack {
                TextField("Spør om oppgaven…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .focused($questionFocused)
                    .onSubmit(ask)
                Button("Spør", action: ask).disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || store.tutorBusy)
                Button("Vanskeligere oppgave") { Task { await store.harder(than: puzzle) } }.disabled(store.tutorBusy)
            }
            Text("Oppgaven, fasiten og svaret ditt sendes til Claude. Ingenting annet.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skole.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { questionFocused = explanation == nil }
    }

    private func ask() {
        let asked = question.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty, !store.tutorBusy else { return }
        question = ""
        Task {
            if let (answer, newSession) = await store.ask(puzzle: puzzle, question: asked, session: session) {
                exchanges.append(TutorExchange(question: asked, answer: answer))
                session = newSession
            }
        }
    }
}
