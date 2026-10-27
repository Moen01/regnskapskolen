import RegnskapKit
import SwiftUI

/// Bank pane: the statement's open lines on the left, the user's open bank vouchers on the right, matched by hand.
struct BankView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedLines: Set<String> = []
    @State private var selectedEntries: Set<UUID> = []
    @State private var error: MatchError?

    var body: some View {
        if let statement = store.bankStatement {
            content(statement)
        } else {
            ContentUnavailableView("Denne casen har ingen kontoutskrift", systemImage: "building.columns")
        }
    }

    private func content(_ statement: BankStatement) -> some View {
        let reconciliation = store.reconciliation
        let openLines = statement.linjer.filter { !reconciliation.isMatched(bankLine: $0.id) }
            .sorted { ($0.dato, $0.id) < ($1.dato, $1.id) }
        let openEntries = store.sandbox.entries.filter { $0.bankMovement(konto: statement.konto) != 0 && !reconciliation.isMatched(entry: $0.id) }
        let sums = Reconciliation.sums(bankLineIds: Array(selectedLines), entryIds: Array(selectedEntries), statement: statement, journal: store.sandbox)
        let difference = sums.map { $0.bank - $0.journal }
        let canMatch = difference == 0 && !selectedLines.isEmpty && !selectedEntries.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            if let check = store.bankCheck {
                SectionHeader(title: "Kontoutskrift \(statement.konto)", subtitle: "Utgående \(NorwegianFormat.kroner(statement.utgaaende)) · \(check.linesMatched) av \(check.linesTotal) linjer avstemt")
            }
            HStack(alignment: .top, spacing: 12) {
                column("Banklinjer", empty: "Alle linjene er avstemt.") {
                    ForEach(openLines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            row(date: line.dato, text: line.tekst, amount: line.belop, selected: selectedLines.contains(line.id)) { toggle(&selectedLines, line.id) }
                            Button("Før fra banklinjen") { store.bookFromBankLine(line); selectedLines.remove(line.id) }
                                .controlSize(.small)
                                .padding(.leading, 6)
                        }
                    }
                } isEmpty: { openLines.isEmpty }
                column("Bilag", empty: "Ingen åpne bilag med bankbevegelse.") {
                    ForEach(openEntries) { entry in
                        row(date: entry.dato, text: entry.tekst, amount: entry.bankMovement(konto: statement.konto), selected: selectedEntries.contains(entry.id)) { toggle(&selectedEntries, entry.id) }
                    }
                } isEmpty: { openEntries.isEmpty }
            }
            if !reconciliation.matches.isEmpty { matched(statement) }
            Divider()
            HStack {
                Text("Valgt: bank \(sums.map { NorwegianFormat.kroner($0.bank) } ?? "–") · bilag \(sums.map { NorwegianFormat.kroner($0.journal) } ?? "–") · differanse \(difference.map { NorwegianFormat.kroner($0) } ?? "–")")
                    .font(.callout.monospacedDigit())
                Spacer()
                Button("Avstem") { match() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.skole)
                    .disabled(!canMatch)
            }
            if let error { Text(error.message).font(.callout).foregroundStyle(Color.bad) }
            if store.bankCheck?.done == true {
                Label("Banken er avstemt. Godt jobbet!", systemImage: "checkmark.seal.fill").foregroundStyle(Color.ok)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ title: String, empty: String, @ViewBuilder rows: () -> some View, isEmpty: () -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if isEmpty() { Text(empty).font(.caption).foregroundStyle(.secondary) }
                    rows()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(date: DayKey, text: String, amount: Decimal, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Two lines: the columns are narrow, so the text gets a row of its own and the date and amount never wrap.
            VStack(alignment: .leading, spacing: 2) {
                Text(text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text(NorwegianFormat.date(date.date)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 4)
                    Text(NorwegianFormat.kroner(amount)).monospacedDigit().foregroundStyle(amount >= 0 ? Color.debet : Color.kredit).fixedSize()
                }
            }
            .font(.callout)
            .padding(6)
            .background(selected ? Color.skole.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func matched(_ statement: BankStatement) -> some View {
        DisclosureGroup("Avstemt (\(store.reconciliation.matches.count))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.reconciliation.matches) { match in
                    let lines = match.bankLineIds.compactMap { statement.line(id: $0) }
                    let entries = match.entryIds.compactMap { id in store.sandbox.entries.first { $0.id == id } }
                    HStack {
                        Text("\(lines.map(\.tekst).joined(separator: ", ")) · \(entries.map(\.tekst).joined(separator: ", ")) · \(NorwegianFormat.kroner(lines.reduce(0) { $0 + $1.belop }))")
                            .font(.caption).lineLimit(1)
                        Spacer()
                        Button("Opphev") { store.unmatchBank(match.id) }.controlSize(.small)
                    }
                }
            }
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func match() {
        error = store.matchBank(lineIds: Array(selectedLines), entryIds: Array(selectedEntries))
        // Keep the selection on failure so the user can adjust it.
        guard error == nil else { return }
        selectedLines = []
        selectedEntries = []
    }
}
