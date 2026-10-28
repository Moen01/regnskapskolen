import RegnskapKit
import SwiftUI

struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation

    /// Spill is hidden until the learner turns it on in Innstillinger; screenshots show every screen.
    private var sections: [AppSection] {
        AppSection.allCases.filter { $0 != .game || store.settings.showGame || AppStore.isScreenshotRun }
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            // Rows take their selection tag from the ForEach id, so the id must be the AppSection
            // itself: with the default String id the AppSection binding never matches a row.
            List(sections, id: \.self, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .today ? store.remainingToday : 0)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(store.streak) dager på rad", systemImage: "flame").font(.caption)
                    Text(store.claudeStatus.isReady ? "Claude er klar" : store.claudeStatus.text).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        } detail: {
            Group {
                if let error = store.loadError, store.library == nil {
                    ContentUnavailableView("Innholdet mangler", systemImage: "folder.badge.questionmark", description: Text(error))
                } else if let puzzle = store.openPuzzle {
                    PuzzleView(puzzle: puzzle, onResult: { store.record($0) }, onNext: store.openFromToday ? { nextToday(after: puzzle) } : nil)
                        .id(puzzle.id)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button("Tilbake", systemImage: "chevron.left") { store.openPuzzle = nil }
                            }
                        }
                } else {
                    switch navigation.section {
                    case .today: TodayView()
                    case .practice: TopicsView()
                    case .game: GameHubView()
                    case .sandbox: SandboxView()
                    case .rules: RulesView()
                    case .stats: StatsView()
                    case .settings: SettingsView()
                    }
                }
            }
            .frame(minWidth: 600)
        }
        // Picking a section in the sidebar is the way out of an open puzzle, not only the back button.
        .onChange(of: navigation.section) { store.openPuzzle = nil }
        .sheet(isPresented: $navigation.showOnboarding) { OnboardingView() }
        .overlay(alignment: .bottom) {
            if let notice = store.contentNotice ?? store.loadError, store.library != nil {
                Text(notice).font(.caption).padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8)).padding()
            }
        }
    }

    private func nextToday(after puzzle: Puzzle) {
        if let next = store.nextToday(after: puzzle) { store.open(next, fromToday: true) } else { store.openPuzzle = nil }
    }
}
