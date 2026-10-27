import RegnskapKit
import SwiftUI

/// A month of big, clickable days. Pure SwiftUI: the system calendar picker on macOS draws days
/// about 18 points wide, which is too small to hit without care.
struct MonthCalendar: View {
    @Binding var selected: DayKey?
    @State private var year: Int
    @State private var month: Int

    private static let cell = CGSize(width: 36, height: 30)
    private static let weekdays = ["M", "T", "O", "T", "F", "L", "S"]
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .norwegian
        f.locale = Locale(identifier: "nb_NO")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    init(selected: Binding<DayKey?>) {
        _selected = selected
        let shown = selected.wrappedValue ?? DayKey.today()
        _year = State(initialValue: shown.year)
        _month = State(initialValue: shown.month)
    }

    private var today: DayKey { DayKey.today() }
    private var title: String {
        let text = Self.monthFormatter.string(from: DayKey(year: year, month: month, day: 1).date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button { step(months: -1) } label: { Image(systemName: "chevron.left") }.help("Forrige måned")
                Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                Button("I dag") { show(today) }.font(.caption)
                Button { step(months: 1) } label: { Image(systemName: "chevron.right") }.help("Neste måned")
            }
            .buttonStyle(.borderless)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { _, name in
                        Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: Self.cell.width)
                    }
                }
                let days = DayKey.monthGrid(year: year, month: month)
                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        ForEach(days[row * 7..<(row + 1) * 7], id: \.self) { day in dayButton(day) }
                    }
                }
            }
        }
        .frame(width: Self.cell.width * 7 + 12)
        .onChange(of: selected) { if let selected { show(selected) } }
    }

    private func dayButton(_ day: DayKey) -> some View {
        let inMonth = day.month == month && day.year == year
        let isSelected = day == selected
        return Button { selected = day } label: {
            Text("\(day.day)")
                .font(.body.monospacedDigit())
                .frame(width: Self.cell.width, height: Self.cell.height)
                .foregroundStyle(isSelected ? Color.white : inMonth ? (day.isWeekend ? Color.secondary : Color.primary) : Color.secondary.opacity(0.5))
                .background(isSelected ? Color.skole : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.skole, lineWidth: day == today && !isSelected ? 1 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(NorwegianFormat.date(day.date))
    }

    private func step(months: Int) {
        show(DayKey(year: year, month: month, day: 1).adding(months: months))
    }

    private func show(_ day: DayKey) {
        year = day.year
        month = day.month
    }
}
