import RegnskapKit
import SwiftUI

/// A creature in front of the learner: pick the rule, answer the puzzle, see it caught or gone.
struct EncounterView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let run = store.run, let encounter = run.current, let region = Optional(run.region) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        bars(run)
                        Spacer()
                        Button("Avbryt") { store.endRun() }
                    }
                    creatureCard(encounter, region: region)
                    if run.phase == .encounter {
                        moveStep(encounter, run: run)
                    }
                    Text(encounter.puzzle.oppgave.isEmpty ? encounter.puzzle.tittel : "").font(.title3.weight(.semibold))
                    MarkdownText(encounter.puzzle.oppgave).textSelection(.enabled)
                    input(encounter.puzzle, locked: run.phase != .encounter)
                    if run.phase == .encounter {
                        Button("Sjekk") { store.answerEncounter() }
                            .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.skole)
                            .disabled(!(store.encounterSession?.attempt.isAnswered ?? false) || !(encounter.moves.isEmpty || run.hasChosen))
                        if !encounter.moves.isEmpty, !run.hasChosen { Text("Velg en regel først.").font(.caption).foregroundStyle(.secondary) }
                    }
                    if case .result(let outcome) = run.phase { result(outcome, encounter) }
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
    }

    private func bars(_ run: RegionRun) -> some View {
        HStack(spacing: 16) {
            Label("\(NorwegianFormat.kroner(Decimal(run.hp), decimals: 0)) kr", systemImage: "heart.fill").foregroundStyle(run.hp < 3000 ? Color.kredit : Color.ok).monospacedDigit()
            Label("\(run.damage) av \(run.region.damageTarget)", systemImage: "flag.checkered").foregroundStyle(.secondary).monospacedDigit()
            Text("\(run.caught) fanget").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
    }

    private func creatureCard(_ encounter: Encounter, region: Region) -> some View {
        HStack(spacing: 14) {
            Image(systemName: region.theme.symbol).font(.system(size: 40)).foregroundStyle(Color.theme(region.theme.farge)).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(encounter.puzzle.tittel).font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Pill(text: store.topic(encounter.puzzle.tema)?.navn ?? encounter.puzzle.tema, color: Color.theme(region.theme.farge))
                    Text(String(repeating: "★", count: encounter.puzzle.vanskelighet)).foregroundStyle(Color.warn)
                    if encounter.puzzle.isEdgeCase { Pill(text: "Sjelden", color: .warn) }
                    if encounter.isGymLeader { Pill(text: "Gym-leder", color: .bad) }
                    Pill(text: encounter.stageBefore.navn, color: encounter.stageBefore == .vill ? .secondary : .skole)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func moveStep(_ encounter: Encounter, run: RegionRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hvilken regel gjelder?").font(.headline)
            if encounter.moves.isEmpty {
                Text("Ingen kjent regel for denne.").font(.caption).foregroundStyle(.secondary)
            } else {
                // A wrapping row of paragraph buttons; the picked one is tinted.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(encounter.moves) { move in
                        Button(move.label) { store.chooseMove(move) }
                            .buttonStyle(.bordered).tint(run.chosenMove == move ? .skole : nil)
                    }
                    Button("Ingen regel") { store.chooseMove(nil) }.buttonStyle(.bordered).tint(run.hasChosen && run.chosenMove == nil ? .skole : nil)
                }
            }
        }
    }

    @ViewBuilder
    private func input(_ puzzle: Puzzle, locked: Bool) -> some View {
        switch puzzle.payload {
        case .posting(let p): PostingView(posting: p, lines: binding(\.posting), disabled: locked)
        case .classify(let p): ClassifyView(classify: p, answers: binding(\.classify), perItem: nil, disabled: locked)
        case .spot(let p): SpotView(spot: p, marked: binding(\.spot), perItem: nil, disabled: locked)
        case .number(let p): NumberView(answer: p, text: binding(\.number), disabled: locked)
        case .quiz(let p): QuizView(quiz: p, selected: binding(\.quiz), showAnswer: locked, disabled: locked)
        case .case(let p): CaseView(sak: p, selected: binding(\.case), showAnswer: locked, disabled: locked)
        case .vat(let p): VATView(vat: p, rates: store.library?.rates.mvaSatser ?? [], behandling: binding(\.vatBehandling), fradrag: binding(\.vatFradrag), disabled: locked)
        case .deadline(let p): DeadlineView(deadline: p, day: binding(\.deadline), disabled: locked)
        }
    }

    /// SwiftUI still refreshes the bindings while the view is on its way out, after `endRun` has
    /// dropped the session; an empty attempt stands in so nothing is unwrapped.
    private func binding<T>(_ path: WritableKeyPath<PuzzleAttempt, T>) -> Binding<T> {
        let kind = store.run?.current?.puzzle.kind ?? .quiz
        return Binding(get: { (store.encounterSession?.attempt ?? PuzzleAttempt.empty(for: kind))[keyPath: path] },
                       set: { store.encounterSession?.attempt[keyPath: path] = $0 })
    }

    private func result(_ outcome: EncounterOutcome, _ encounter: Encounter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch outcome {
            case .caught(let stage, let superEffective):
                Label("Fanget! \(stage.navn)", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Color.ok)
                if superEffective { Pill(text: "Super effektivt!", color: .ok) }
            case .escaped(let hpLost):
                Label("Flyktet. −\(NorwegianFormat.kroner(Decimal(hpLost), decimals: 0)) kr", systemImage: "xmark.circle.fill").font(.headline).foregroundStyle(Color.bad)
            case .repeated:
                Label("Riktig, men den er alt møtt i dag. Den kommer igjen i morgen.", systemImage: "clock.arrow.circlepath").font(.headline).foregroundStyle(.secondary)
            }
            MarkdownText(encounter.puzzle.forklaring).font(.callout)
            ForEach(encounter.puzzle.lov, id: \.self) { LawBadge(law: $0) }
            Button("Neste") { store.proceedEncounter() }
                .keyboardShortcut(.return, modifiers: []).buttonStyle(.borderedProminent).tint(.skole)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background({ switch outcome { case .caught: Color.ok.opacity(0.08); case .escaped: Color.bad.opacity(0.08); case .repeated: Color.secondary.opacity(0.08) } }(), in: RoundedRectangle(cornerRadius: 10))
    }
}
