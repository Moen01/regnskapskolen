import RegnskapKit
import SwiftUI

/// "Før bilaget": account picker, debet and kredit per line, and a live balance footer.
struct PostingView: View {
    let posting: Posting
    @Binding var lines: PostingAttempt
    var disabled = false

    private var debet: Decimal { lines.reduce(0) { $0 + ($1.debet ?? 0) } }
    private var kredit: Decimal { lines.reduce(0) { $0 + ($1.kredit ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Konto").frame(maxWidth: .infinity, alignment: .leading)
                Text("Debet").foregroundStyle(Color.debet).frame(width: 120, alignment: .trailing)
                Text("Kredit").foregroundStyle(Color.kredit).frame(width: 120, alignment: .trailing)
                Color.clear.frame(width: 20)
            }
            .font(.caption.weight(.semibold))
            ForEach($lines) { $line in
                HStack {
                    Picker("Konto", selection: $line.konto) {
                        Text("Velg konto").tag("")
                        ForEach(posting.kontoer) { Text("\($0.nr) \($0.navn)").tag($0.nr) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    AmountField(title: "Debet", value: $line.debet, color: .debet).frame(width: 120)
                    AmountField(title: "Kredit", value: $line.kredit, color: .kredit).frame(width: 120)
                    Button { lines.removeAll { $0.id == line.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(lines.count <= 1)
                        .help("Fjern linjen")
                }
            }
            Button("Legg til linje", systemImage: "plus") { lines.append(PostingAttemptLine()) }
                .buttonStyle(.borderless)
            HStack(spacing: 12) {
                Text("Debet \(NorwegianFormat.kroner(debet))").foregroundStyle(Color.debet)
                Text("·").foregroundStyle(.secondary)
                Text("Kredit \(NorwegianFormat.kroner(kredit))").foregroundStyle(Color.kredit)
                Text("·").foregroundStyle(.secondary)
                Text("Differanse \(NorwegianFormat.kroner(debet - kredit))").foregroundStyle(debet == kredit ? Color.ok : Color.bad)
            }
            .font(.callout.monospacedDigit())
        }
        .disabled(disabled)
        .onAppear { if lines.isEmpty { lines = [PostingAttemptLine(), PostingAttemptLine()] } }
    }
}
