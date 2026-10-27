import RegnskapKit
import SwiftUI

/// The journal: one card per voucher with its date, text and lines; problems shown under the card.
struct JournalEditor: View {
    @Environment(AppStore.self) private var store

    private var accounts: [Account] { store.library?.chart.all ?? [] }
    private var vatCodes: [MVARate] { store.library?.rates.mvaSatser ?? [] }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Journal", subtitle: "\(store.sandbox.entries.count) bilag")
                    Spacer()
                    Button("Nytt bilag", systemImage: "plus", action: addEntry).buttonStyle(.borderedProminent).tint(.skole)
                }
                if store.sandbox.entries.isEmpty {
                    Text("Ingen bilag ennå. Trykk «Nytt bilag» og før den første hendelsen.").foregroundStyle(.secondary)
                }
                ForEach($store.sandbox.entries) { $entry in
                    EntryCard(entry: $entry, accounts: accounts, vatCodes: vatCodes, problems: store.sandboxProblems.filter { $0.entryId == entry.id }) {
                        store.sandbox.entries.removeAll { $0.id == entry.id }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func addEntry() {
        let date = store.sandbox.entries.last?.dato ?? store.activeCase?.hendelser.first?.dato ?? DayKey.today()
        store.sandbox.entries.append(JournalEntry(dato: date, tekst: "", linjer: [JournalLine(konto: "", side: .debet, belop: 0), JournalLine(konto: "", side: .kredit, belop: 0)]))
    }
}

struct EntryCard: View {
    @Binding var entry: JournalEntry
    let accounts: [Account]
    let vatCodes: [MVARate]
    let problems: [JournalProblem]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // A voucher always has a date: an emptied or half-typed field keeps the last one until it parses again.
                DateField(day: Binding(get: { entry.dato }, set: { if let day = $0 { entry.dato = day } }))
                TextField("Bilagstekst", text: $entry.tekst).textFieldStyle(.roundedBorder)
                Button { onDelete() } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Slett bilaget")
            }
            ForEach($entry.linjer) { $line in
                HStack(spacing: 6) {
                    Picker("Konto", selection: $line.konto) {
                        Text("Velg konto").tag("")
                        ForEach(accounts) { Text($0.label).tag($0.nr) }
                    }
                    .labelsHidden().frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                    Picker("Side", selection: $line.side) {
                        Text("D").tag(Side.debet)
                        Text("K").tag(Side.kredit)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 64).help("Debet eller kredit")
                    AmountField(title: "Beløp", value: Binding(get: { line.belop == 0 ? nil : line.belop }, set: { line.belop = $0 ?? 0 }), color: line.side == .debet ? .debet : .kredit)
                        .frame(width: 100)
                    Picker("Mva", selection: Binding(get: { line.mvaKode ?? "" }, set: { line.mvaKode = $0.isEmpty ? nil : $0 })) {
                        Text("–").tag("")
                        ForEach(vatCodes, id: \.kode) { Text($0.kode).tag($0.kode) }
                    }
                    .labelsHidden().frame(width: 64).help("Mva-kode på grunnlagslinjen; mva-linjen sjekkes mot den.")
                    Button { entry.linjer.removeAll { $0.id == line.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).disabled(entry.linjer.count <= 1)
                }
            }
            HStack {
                Button("Linje", systemImage: "plus") { entry.linjer.append(JournalLine(konto: "", side: .debet, belop: 0)) }.buttonStyle(.borderless).controlSize(.small)
                Spacer()
                Text("D \(NorwegianFormat.kroner(entry.sumDebet)) · K \(NorwegianFormat.kroner(entry.sumKredit))")
                    .font(.caption.monospacedDigit()).foregroundStyle(entry.balanced ? Color.ok : Color.bad)
            }
            ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                Label(problem.message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.bad)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
