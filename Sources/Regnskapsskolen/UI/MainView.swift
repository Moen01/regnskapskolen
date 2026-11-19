import RegnskapKit
import SwiftUI

struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @Environment(\.appTheme) private var theme

    /// Spill is hidden until the learner turns it on in Innstillinger; screenshots show every screen.
    private var sections: [AppSection] {
        AppSection.allCases.filter { $0 != .game || store.settings.showGame || AppStore.isScreenshotRun }
    }

    /// Standard theme keeps the system `List`; the playful theme draws warm rows with an accent selection.
    @ViewBuilder private var sidebar: some View {
        @Bindable var navigation = navigation
        if theme.isPlayful {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(sections) { section in
                        Button { navigation.section = section } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.symbol).frame(width: 22)
                                Text(section.title)
                                Spacer()
                                if section == .today, store.remainingToday > 0 {
                                    Text("\(store.remainingToday)").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 1).background(theme.accent, in: Capsule())
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(navigation.section == section ? theme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(navigation.section == section ? theme.accent : theme.primaryText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .themedScreenBackground()
        } else {
            // Rows take their selection tag from the ForEach id, so the id must be the AppSection
            // itself: with the default String id the AppSection binding never matches a row.
            List(sections, id: \.self, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .today ? store.remainingToday : 0)
            }
        }
    }

    var body: some View {
        @Bindable var navigation = navigation
        ZStack {
        NavigationSplitView {
            sidebar
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
                Text(notice).font(.caption).foregroundStyle(theme.isPlayful ? theme.primaryText : .primary)
                    .padding(10)
                    .background(theme.isPlayful ? AnyShapeStyle(theme.cardBackground) : AnyShapeStyle(.thinMaterial), in: RoundedRectangle(cornerRadius: theme.isPlayful ? 14 : 8))
                    .shadow(color: .black.opacity(theme.isPlayful ? 0.1 : 0), radius: 10, y: 3)
                    .padding()
            }
        }

            // A celebration earned inside the game or on the puzzle screen waits as a full-window layer
            // until the learner is back on a plain screen, so it never covers the Game Boy UI or the
            // explanation. It sits beside the split view, not inside it, so it covers the sidebar too.
            if theme.celebrationsEnabled, navigation.section != .game, store.openPuzzle == nil,
               let celebration = store.pendingCelebration {
                CelebrationOverlay(celebration: celebration) { store.pendingCelebration = nil }
                    .animation(.easeOut(duration: 0.3), value: store.pendingCelebration)
            }
        }
    }

    private func nextToday(after puzzle: Puzzle) {
        if let next = store.nextToday(after: puzzle) { store.open(next, fromToday: true) } else { store.openPuzzle = nil }
    }
}
