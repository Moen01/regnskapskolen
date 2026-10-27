import RegnskapKit
import SwiftUI

/// One law reference under an explanation: "mval. § 3-1" and the sentence it stands for.
struct LawBadge: View {
    let law: LawReference

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(law.label).font(.caption.weight(.semibold)).foregroundStyle(Color.skole)
            Text(law.tekst).font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skole.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
