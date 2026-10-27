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

/// "Frist": the event, a field to type the date in and a calendar to click in.
struct DeadlineView: View {
    let deadline: Deadline
    @Binding var day: DayKey?
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deadline.hendelse)
            Text("Skriv fristen, eller velg dagen i kalenderen.").font(.caption).foregroundStyle(.secondary)
            DateField(day: $day, inlineCalendar: true)
        }
        .disabled(disabled)
    }
}
