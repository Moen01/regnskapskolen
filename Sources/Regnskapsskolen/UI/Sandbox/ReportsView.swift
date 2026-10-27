import RegnskapKit
import SwiftUI

/// The reports over the sandbox journal, recomputed on every edit.
struct ReportsView: View {
    enum Tab: String, CaseIterable { case saldo = "Saldo", statements = "Resultat", tAccount = "T-konto", vat = "Mva", check = "Fasit" }
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = .saldo
    @State private var account = ""

    private var journal: Journal { store.sandbox }
    private var title: String {
        switch tab {
        case .saldo: "Saldobalanse"
        case .statements: "Resultat og balanse"
        case .tAccount: "T-konto"
        case .vat: "Mva-oppgjør"
        case .check: "Sjekk mot fasit"
        }
    }
    private var chart: ChartOfAccounts? { store.library?.chart }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Rapport", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            Text(title).font(.headline)
            if let chart {
                ScrollView {
                    switch tab {
                    case .saldo: trialBalance(chart)
                    case .statements: statements(chart)
                    case .tAccount: tAccount(chart)
                    case .vat: vat
                    case .check: check(chart)
                    }
                }
            } else {
                ContentUnavailableView("Innholdet mangler", systemImage: "folder.badge.questionmark")
            }
        }
        .padding(12)
        .font(.caption)
    }

    private func money(_ value: Decimal) -> some View {
        Text(NorwegianFormat.kroner(value)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func trialBalance(_ chart: ChartOfAccounts) -> some View {
        let rows = Reports.trialBalance(journal, chart: chart)
        return Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("Konto").gridColumnAlignment(.leading)
                Text("Debet").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Kredit").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Saldo").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(rows) { row in
                GridRow {
                    VStack(alignment: .leading, spacing: 0) { Text(row.konto).monospacedDigit(); Text(row.navn).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.frame(width: 72, alignment: .leading)
                    money(row.debet).foregroundStyle(Color.debet)
                    money(row.kredit).foregroundStyle(Color.kredit)
                    money(row.saldo)
                }
            }
            Divider()
            GridRow {
                Text("Sum").font(.caption.weight(.semibold))
                money(rows.reduce(0) { $0 + $1.debet }).foregroundStyle(Color.debet)
                money(rows.reduce(0) { $0 + $1.kredit }).foregroundStyle(Color.kredit)
                money(rows.reduce(0) { $0 + $1.saldo })
            }
            if rows.isEmpty { Text("Ingen posteringer ennå.").foregroundStyle(.secondary) }
        }
    }

    private func statements(_ chart: ChartOfAccounts) -> some View {
        let s = Reports.statements(journal, chart: chart)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Resultat").font(.headline)
            line("Inntekter", s.inntekter)
            line("Kostnader", s.kostnader)
            line("Resultat", s.resultat, bold: true, color: s.resultat >= 0 ? .ok : .bad)
            Text("Balanse").font(.headline).padding(.top, 6)
            line("Eiendeler", s.eiendeler)
            line("Gjeld", s.gjeld)
            line("Egenkapital (før disponering)", s.egenkapital)
            line("Eiendeler − (gjeld + egenkapital)", s.differanse, bold: true, color: s.differanse == s.resultat ? .ok : .bad)
            Text("Før årets resultat er disponert, skal differansen være lik resultatet.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func line(_ label: String, _ value: Decimal, bold: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(label).fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(NorwegianFormat.kroner(value)).monospacedDigit().fontWeight(bold ? .semibold : .regular).foregroundStyle(color)
        }
    }

    private func tAccount(_ chart: ChartOfAccounts) -> some View {
        let used = Reports.trialBalance(journal, chart: chart).map(\.konto)
        let chosen = used.contains(account) ? account : (used.first ?? "")
        let t = Reports.tAccount(konto: chosen, journal: journal)
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Konto", selection: Binding(get: { chosen }, set: { account = $0 })) {
                ForEach(used, id: \.self) { Text("\($0) \(chart.name($0))").tag($0) }
            }
            if used.isEmpty {
                Text("Ingen posteringer ennå.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    side("Debet", t.debet, t.sumDebet, .debet)
                    Divider()
                    side("Kredit", t.kredit, t.sumKredit, .kredit)
                }
                line("Saldo", t.saldo, bold: true)
            }
        }
    }

    private func side(_ title: String, _ postings: [TAccountPosting], _ sum: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            ForEach(Array(postings.enumerated()), id: \.offset) { _, p in
                HStack {
                    Text("\(NorwegianFormat.date(p.dato.date)) \(p.tekst)").font(.caption).lineLimit(1)
                    Spacer()
                    Text(NorwegianFormat.kroner(p.belop)).font(.caption.monospacedDigit())
                }
            }
            Divider()
            HStack { Spacer(); Text(NorwegianFormat.kroner(sum)).font(.caption.weight(.semibold).monospacedDigit()) }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var vat: some View {
        let v = Reports.vatSettlement(journal)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Mva-oppgjør for perioden").font(.headline)
            line("Utgående mva (2700)", v.utgaaende)
            line("Inngående mva (2710)", v.inngaaende)
            line(v.aaBetale >= 0 ? "Å betale" : "Til gode", abs(v.aaBetale), bold: true, color: v.aaBetale >= 0 ? .kredit : .ok)
            Text("Utgående minus inngående. Leveres i mva-meldingen én måned og ti dager etter terminen.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func check(_ chart: ChartOfAccounts) -> some View {
        Group {
            if let sandboxCase = store.activeCase {
                let diffs = sandboxCase.compare(journal: journal, chart: chart)
                if diffs.isEmpty {
                    if journal.entries.isEmpty {
                        Text("Før bilagene, så sammenlignes saldobalansen med fasiten her.").foregroundStyle(.secondary)
                    } else {
                        Label("Saldobalansen stemmer med fasiten. Godt jobbet!", systemImage: "checkmark.seal.fill").foregroundStyle(Color.ok)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(diffs.count) konto\(diffs.count == 1 ? "" : "er") avviker fra fasiten").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            GridRow {
                                Text("Konto")
                                Text("Fasit").frame(maxWidth: .infinity, alignment: .trailing)
                                Text("Din").frame(maxWidth: .infinity, alignment: .trailing)
                                Text("Avvik").frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Divider()
                            ForEach(diffs) { diff in
                                GridRow {
                                    VStack(alignment: .leading, spacing: 0) { Text(diff.konto).monospacedDigit(); Text(chart.name(diff.konto)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.frame(width: 72, alignment: .leading)
                                    money(diff.forventet)
                                    money(diff.faktisk)
                                    money(diff.faktisk - diff.forventet).foregroundStyle(Color.bad)
                                }
                            }
                        }
                        Text("Saldo: debet pluss, kredit minus.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Velg en case for å sammenligne med en fasit.").foregroundStyle(.secondary)
            }
        }
    }
}
