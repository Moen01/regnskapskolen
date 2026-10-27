import RegnskapKit
import SwiftUI

/// A kroner field: accepts "1 250", "1250", "1250,00" and "1.250,00", shows "1 250,00" once left.
struct AmountField: View {
    let title: String
    @Binding var value: Decimal?
    var color: Color = .primary
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(color)
            .focused($focused)
            .onAppear { text = value.map { NorwegianFormat.kroner($0) } ?? "" }
            .onChange(of: text) { _, new in
                value = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : NorwegianFormat.parseAmount(new)
            }
            .onChange(of: focused) { _, now in
                if !now, let value { text = NorwegianFormat.kroner(value) }
            }
            .onChange(of: value) { _, new in
                // A reset from outside (a new puzzle) clears the field; typing is left alone.
                if new == nil, !focused { text = "" }
            }
    }
}
