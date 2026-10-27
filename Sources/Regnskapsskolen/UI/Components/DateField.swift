import RegnskapKit
import SwiftUI

/// A day typed as "dd.mm.åååå", with a month calendar for those who would rather click. The field
/// is the fast path for someone who already knows the date; the calendar is the big target.
/// `day` always equals what the text parses to, so an unfinished or wrong date reads as no date.
struct DateField: View {
    @Binding var day: DayKey?
    /// Shows the calendar under the field instead of behind a button.
    var inlineCalendar = false
    @State private var text = ""
    @State private var showCalendar = false

    private var invalid: Bool { !text.isEmpty && NorwegianFormat.parseDay(text) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("dd.mm.åååå", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 110)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.bad, lineWidth: invalid ? 1 : 0))
                    .help("Skriv datoen som dd.mm.åååå")
                if !inlineCalendar {
                    Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Velg i kalenderen")
                        .popover(isPresented: $showCalendar, arrowEdge: .bottom) { calendar.padding(10) }
                }
            }
            if inlineCalendar { calendar }
            if invalid { Text("Skriv datoen som dd.mm.åååå, for eksempel 10.06.2026.").font(.caption).foregroundStyle(Color.bad) }
        }
        .onAppear { text = day.map { NorwegianFormat.date($0.date) } ?? "" }
        .onChange(of: text) { day = NorwegianFormat.parseDay(text) }
        .onChange(of: day) {
            // A pick in the calendar rewrites the text; typing never does, so "1.6.2026" stays as typed.
            if NorwegianFormat.parseDay(text) != day { text = day.map { NorwegianFormat.date($0.date) } ?? "" }
        }
    }

    private var calendar: some View { MonthCalendar(selected: $day) }
}
