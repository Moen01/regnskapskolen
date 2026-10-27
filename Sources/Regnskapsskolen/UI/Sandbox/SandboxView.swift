import RegnskapKit
import SwiftUI

/// Sandkasse: the case on the left, the journal in the middle, the reports on the right.
struct SandboxView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false
    @State private var pendingCase: SandboxCase?

    var body: some View {
        // Proportional panes: the journal needs its lines on one row, the reports four money columns.
        GeometryReader { geometry in
            HStack(spacing: 0) {
                casePanel.frame(width: max(200, geometry.size.width * 0.21)).clipped()
                Divider()
                JournalEditor().clipped()
                Divider()
                ReportsView().frame(width: max(320, geometry.size.width * 0.36)).clipped()
            }
        }
        .onChange(of: store.sandbox) { store.saveSandbox() }
        .confirmationDialog("Tømme journalen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Tøm journalen", role: .destructive) { store.clearSandbox() }
        } message: {
            Text("Alle bilagene i sandkassen slettes. Casen beholdes.")
        }
        .confirmationDialog("Starte ny case?", isPresented: Binding(get: { pendingCase != nil }, set: { if !$0 { pendingCase = nil } }), titleVisibility: .visible) {
            Button("Start og tøm journalen", role: .destructive) { if let pendingCase { store.startCase(pendingCase) }; pendingCase = nil }
        } message: {
            Text("Journalen har \(store.sandbox.entries.count) bilag som slettes når en ny case starter.")
        }
    }

    private var casePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu("Velg case") {
                    ForEach(store.sandboxCases) { sandboxCase in
                        Button("\(sandboxCase.tittel) · nivå \(sandboxCase.vanskelighet)") { start(sandboxCase) }
                    }
                    if store.sandboxCases.isEmpty { Text("Ingen caser i Innhold/sandkasse") }
                }
                Menu("Lag en case med Claude") {
                    ForEach(store.library?.topics ?? []) { topic in
                        Button(topic.navn) { makeCase(tema: topic.id) }
                    }
                }
                .disabled(!store.claudeStatus.isReady || store.tutorBusy)
            }
            .controlSize(.small)
            if store.tutorBusy { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Claude skriver en case…").font(.caption) } }
            if let error = store.tutorError { Text(error).font(.caption).foregroundStyle(Color.bad) }
            if let sandboxCase = store.activeCase {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sandboxCase.tittel).font(.headline)
                        Text(sandboxCase.selskap).font(.caption).foregroundStyle(.secondary)
                        MarkdownText(sandboxCase.beskrivelse).font(.callout)
                        Text("Hendelser").font(.subheadline.weight(.semibold)).padding(.top, 4)
                        ForEach(Array(sandboxCase.hendelser.enumerated()), id: \.offset) { index, event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(NorwegianFormat.date(event.dato.date))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                MarkdownText(event.tekst).font(.callout)
                                if let hint = event.hint {
                                    DisclosureGroup("Hint") { Text(hint).font(.caption).foregroundStyle(.secondary) }.font(.caption)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        }
                        ForEach(sandboxCase.lov, id: \.self) { LawBadge(law: $0) }
                    }
                }
            } else {
                ContentUnavailableView("Ingen case valgt", systemImage: "tray.2", description: Text("Velg en case, eller før fritt i journalen og se rapportene oppdatere seg."))
            }
            Spacer(minLength: 0)
            Button("Tøm journalen", role: .destructive) { confirmClear = true }
                .controlSize(.small)
                .disabled(store.sandbox.entries.isEmpty)
        }
        .padding(12)
    }

    private func start(_ sandboxCase: SandboxCase) {
        // Picking the case already in progress just keeps going; a new case asks before clearing the journal.
        if sandboxCase.id == store.activeCase?.id { return }
        if store.sandbox.entries.isEmpty { store.startCase(sandboxCase) } else { pendingCase = sandboxCase }
    }

    private func makeCase(tema: String) {
        Task {
            if let made = await store.makeCase(tema: tema) { start(made) }
        }
    }
}
