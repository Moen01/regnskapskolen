import RegnskapKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Regnskapsskolen").font(.headline)
                Spacer()
                Label("\(store.streak)", systemImage: "flame").foregroundStyle(.orange)
            }
            Text(NorwegianFormat.date(Date())).foregroundStyle(.secondary).font(.caption)
            if store.today.isEmpty {
                Text("Ingen oppgaver i dag. Sjekk innholdsmappen i Innstillinger.").foregroundStyle(.secondary)
            } else {
                ForEach(store.today) { puzzle in
                    HStack(spacing: 8) {
                        Image(systemName: store.isCompletedToday(puzzle) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.isCompletedToday(puzzle) ? Color.ok : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(puzzle.tittel).lineLimit(1)
                            Text("\(store.topic(puzzle.tema)?.navn ?? puzzle.tema) · \(puzzle.kind.navn) · nivå \(puzzle.vanskelighet)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            Spacer(minLength: 0)
            if let update = store.availableUpdate, !AppUpdater.isDevelopmentBuild {
                Button { Task { await store.installUpdate() } } label: {
                    Label(store.isUpdating ? "Oppdaterer…" : "Oppdater til \(update.version)", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.blue)
                .disabled(store.isUpdating || update.assetURL == nil)
            }
            HStack {
                Button(store.remainingToday > 0 ? "Åpne dagens oppgaver" : "Åpne Regnskapsskolen") {
                    AppDelegate.shared?.showMainWindow(section: .today)
                }.buttonStyle(.borderedProminent).tint(.skole)
                Spacer()
                Button("Avslutt") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340, height: 360, alignment: .top)
    }
}
