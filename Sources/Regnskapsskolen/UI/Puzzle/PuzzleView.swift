import RegnskapKit
import SwiftUI

/// One puzzle: the task, the input for its kind, Sjekk / Vis fasit / Forklar / Spør / Neste, and
/// the explanation with its law references once the puzzle is done.
struct PuzzleView: View {
    @Environment(AppStore.self) private var store
    @State private var session: PuzzleSession
    @State private var explanation: String?
    @State private var showTutor = false
    @State private var reported = false
    let onResult: (AttemptResult) -> Void
    let onNext: (() -> Void)?

    init(puzzle: Puzzle, session: PuzzleSession? = nil, onResult: @escaping (AttemptResult) -> Void, onNext: (() -> Void)? = nil) {
        _session = State(initialValue: session ?? PuzzleSession(puzzle: puzzle))
        self.onResult = onResult
        self.onNext = onNext
    }

    private var puzzle: Puzzle { session.puzzle }
    private var finished: Bool { session.isFinished }
    private var rates: [MVARate] { store.library?.rates.mvaSatser ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Pill(text: puzzle.kind.navn, color: .skole)
                    Pill(text: store.topic(puzzle.tema)?.navn ?? puzzle.tema)
                    Pill(text: "nivå \(puzzle.vanskelighet)")
                    if puzzle.isEdgeCase { Pill(text: "edge case", color: .warn) }
                    if puzzle.status == .utkast || puzzle.generert { Pill(text: "utkast", color: .warn) }
                    Spacer()
                }
                Text(puzzle.tittel).font(.title2.weight(.semibold))
                MarkdownText(puzzle.oppgave).textSelection(.enabled)
                input
                buttons
                if let verdict = session.verdict { VerdictView(verdict: verdict) }
                if session.revealed { AnswerView(puzzle: puzzle, rates: rates) }
                if finished {
                    Divider()
                    Text("Forklaring").font(.headline)
                    MarkdownText(puzzle.forklaring).textSelection(.enabled)
                    ForEach(puzzle.lov, id: \.self) { LawBadge(law: $0) }
                }
                if showTutor { TutorPane(puzzle: puzzle, explanation: explanation) }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    @ViewBuilder
    private var input: some View {
        switch puzzle.payload {
        case .posting(let p):
            PostingView(posting: p, lines: binding(\.posting), disabled: finished)
        case .classify(let p):
            ClassifyView(classify: p, answers: binding(\.classify), perItem: session.verdict?.perItem, disabled: finished)
        case .spot(let p):
            SpotView(spot: p, marked: binding(\.spot), perItem: session.verdict?.perItem, disabled: finished)
        case .number(let p):
            NumberView(answer: p, text: binding(\.number), disabled: finished)
        case .quiz(let p):
            QuizView(quiz: p, selected: binding(\.quiz), showAnswer: finished, disabled: finished)
        case .case(let p):
            CaseView(sak: p, selected: binding(\.case), showAnswer: finished, disabled: finished)
        case .vat(let p):
            VATView(vat: p, rates: rates, behandling: binding(\.vatBehandling), fradrag: binding(\.vatFradrag), disabled: finished)
        case .deadline(let p):
            DeadlineView(deadline: p, day: binding(\.deadline), disabled: finished)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Sjekk", action: check).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.skole).disabled(finished)
            Button("Vis fasit", action: reveal).disabled(!session.canReveal || finished)
            if store.claudeStatus.isReady {
                if let verdict = session.verdict, !verdict.correct, !session.revealed {
                    Button("Forklar", action: explain).disabled(store.tutorBusy)
                }
                Button("Spør") { showTutor = true }
            }
            Spacer()
            if let onNext, finished {
                Button("Neste", action: onNext).keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent).tint(.skole)
            }
        }
    }

    private func check() {
        let verdict = session.check()
        if verdict.correct { report() }
    }

    private func reveal() {
        session.reveal()
        report()
    }

    private func report() {
        guard !reported else { return }
        reported = true
        onResult(session.result)
    }

    private func explain() {
        guard let verdict = session.verdict else { return }
        showTutor = true
        Task { explanation = await store.explain(puzzle: puzzle, attempt: session.attempt.summary(for: puzzle), verdict: verdict) }
    }

    private func binding<T>(_ path: WritableKeyPath<PuzzleAttempt, T>) -> Binding<T> {
        Binding(get: { session.attempt[keyPath: path] }, set: { session.attempt[keyPath: path] = $0 })
    }
}

/// Typed access to each case's payload, so the input views can bind to it.
extension PuzzleAttempt {
    var posting: PostingAttempt {
        get { if case .posting(let v) = self { v } else { [] } }
        set { self = .posting(newValue) }
    }
    var classify: [Int: String] {
        get { if case .classify(let v) = self { v } else { [:] } }
        set { self = .classify(newValue) }
    }
    var spot: Set<Int> {
        get { if case .spot(let v) = self { v } else { [] } }
        set { self = .spot(newValue) }
    }
    var number: String {
        get { if case .number(let v) = self { v } else { "" } }
        set { self = .number(newValue) }
    }
    var quiz: Int? {
        get { if case .quiz(let v) = self { v } else { nil } }
        set { self = .quiz(newValue) }
    }
    var `case`: String? {
        get { if case .case(let v) = self { v } else { nil } }
        set { self = .case(newValue) }
    }
    var vatBehandling: String? {
        get { if case .vat(let b, _) = self { b } else { nil } }
        set { self = .vat(behandling: newValue, fradrag: vatFradrag) }
    }
    var vatFradrag: Bool? {
        get { if case .vat(_, let f) = self { f } else { nil } }
        set { self = .vat(behandling: vatBehandling, fradrag: newValue) }
    }
    var deadline: DayKey? {
        get { if case .deadline(let v) = self { v } else { nil } }
        set { self = .deadline(newValue) }
    }
}
