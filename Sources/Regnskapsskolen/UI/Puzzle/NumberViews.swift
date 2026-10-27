import RegnskapKit
import SwiftUI

/// "Regn ut": one amount, with the unit beside it.
struct NumberView: View {
    let answer: NumberAnswer
    @Binding var text: String
    var disabled = false

    var body: some View {
        HStack {
            TextField("Svar", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 180)
            if let unit = answer.enhet { Text(unit).foregroundStyle(.secondary) }
        }
        .disabled(disabled)
    }
}

/// "Frist": the event and a date picker.
struct DeadlineView: View {
    let deadline: Deadline
    @Binding var day: DayKey?
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deadline.hendelse)
            DatePicker("Frist", selection: Binding(get: { day?.date ?? Date() }, set: { day = DayKey($0) }), displayedComponents: .date)
                .datePickerStyle(.field)
                .environment(\.locale, Locale(identifier: "nb_NO"))
                .frame(width: 220)
            if day == nil { Text("Velg en dato.").font(.caption).foregroundStyle(.secondary) }
        }
        .disabled(disabled)
    }
}
