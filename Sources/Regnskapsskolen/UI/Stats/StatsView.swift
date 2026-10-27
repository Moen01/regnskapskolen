import RegnskapKit
import SwiftUI

/// Statistikk: streak, days done, the Leitner boxes, mastery per topic and the last 30 days.
struct StatsView: View {
    @Environment(AppStore.self) private var store

    private var progress: LearnerProgress { store.progress }
    private var pool: [Puzzle] { store.pool }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Statistikk")
                HStack(spacing: 12) {
                    StatTile(value: "\(store.streak)", label: "dager på rad", symbol: "flame", color: .orange)
                    StatTile(value: "\(progress.daysCompleted)", label: "dager fullført", symbol: "checkmark.seal", color: .ok)
                    StatTile(value: "\(progress.totalCorrect)/\(progress.totalAttempts)", label: "riktig på første forsøk", symbol: "target", color: .skole)
                    StatTile(value: "\(pool.filter { progress.puzzles[$0.id] != nil }.count)/\(pool.count)", label: "oppgaver sett", symbol: "square.stack", color: .debet)
                }
                Text("Siste 30 dager").font(.headline)
                DayStrip(progress: progress, today: store.todayKey)
                Text("Bokser").font(.headline)
                BoxHistogram(pool: pool, progress: progress)
                Text("Mestring per tema").font(.headline)
                VStack(spacing: 8) {
                    ForEach(store.library?.topics ?? []) { topic in
                        HStack {
                            Text(topic.navn).frame(width: 220, alignment: .leading)
                            MasteryBar(value: store.mastery(topic.id))
                            Text("\(Int(store.mastery(topic.id) * 100)) %").font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One square per day: green when the set was done, amber when started, grey otherwise.
struct DayStrip: View {
    let progress: LearnerProgress
    let today: DayKey

    var body: some View {
        HStack(spacing: 4) {
            ForEach((0..<30).reversed(), id: \.self) { offset in
                let day = today.adding(days: -offset)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(day))
                    .frame(height: 18)
                    .help(NorwegianFormat.date(day.date))
            }
        }
    }

    private func color(_ day: DayKey) -> Color {
        guard let record = progress.days[day.string] else { return Color.gray.opacity(0.15) }
        if record.done { return .ok }
        return record.completed.isEmpty ? Color.gray.opacity(0.15) : .warn
    }
}

/// How many puzzles sit in each Leitner box; unseen ones have their own bar.
struct BoxHistogram: View {
    let pool: [Puzzle]
    let progress: LearnerProgress

    private var counts: [(label: String, count: Int, color: Color)] {
        let seen = pool.compactMap { progress.puzzles[$0.id]?.box }
        var rows: [(String, Int, Color)] = [("Ikke sett", pool.count - seen.count, .secondary)]
        for box in 0...Scheduler.topBox {
            let days = Scheduler.intervals[box]
            let label = box == 0 ? "Boks 0 · samme dag" : "Boks \(box) · \(days) dag\(days == 1 ? "" : "er")"
            rows.append((label, seen.filter { $0 == box }.count, box == 0 ? .bad : box < 3 ? .warn : .ok))
        }
        return rows.map { (label: $0.0, count: $0.1, color: $0.2) }
    }

    var body: some View {
        let most = max(1, counts.map(\.count).max() ?? 1)
        VStack(spacing: 6) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.label).font(.callout).frame(width: 170, alignment: .leading)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 3).fill(row.color.opacity(0.7))
                            .frame(width: max(2, geometry.size.width * CGFloat(row.count) / CGFloat(most)))
                    }
                    .frame(height: 14)
                    Text("\(row.count)").font(.caption).monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
        }
    }
}
