import AppKit
import RegnskapKit
import SwiftUI

/// Innstillinger: appearance, reminder, daily count, Claude, content folder and about.
/// The section contents are shared; the playful theme lays them out as warm cards, the standard
/// theme as today's grouped Form.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @Environment(\.appTheme) private var theme

    var body: some View {
        @Bindable var settings = store.settings
        Group {
            if theme.isPlayful {
                ScrollView {
                    VStack(spacing: 16) {
                        SettingsCard(title: "Utseende") { utseendeRows }
                        SettingsCard(title: "Påminnelse") { reminderRows }
                        SettingsCard(title: "Claude") { claudeRows }
                        SettingsCard(title: "Innhold") { innholdRows }
                        SettingsCard(title: "Spill") { spillRows }
                        SettingsCard(title: "Oppdateringer") { oppdateringerRows }
                        SettingsCard(title: "Om") { omRows }
                    }
                    .padding(20)
                    .frame(maxWidth: 680)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedScreenBackground()
            } else {
                Form {
                    Section("Utseende") { utseendeRows }
                    Section("Påminnelse") { reminderRows }
                    Section("Claude") { claudeRows }
                    Section("Innhold") { innholdRows }
                    Section("Spill") { spillRows }
                    Section("Oppdateringer") { oppdateringerRows }
                    Section("Om") { omRows }
                }
                .formStyle(.grouped)
            }
        }
        .onChange(of: settings.reminderOn) { store.scheduleReminders() }
        .onChange(of: settings.reminderMinutes) { store.scheduleReminders() }
        .onChange(of: settings.reminderWeekdays) { store.scheduleReminders() }
        .onChange(of: settings.dailyCount) { store.scheduleReminders() }
        .onChange(of: settings.showDrafts) { store.reloadContent() }
        .onChange(of: settings.showGame) { if !settings.showGame, navigation.section == .game { navigation.section = .settings } }
    }

    @ViewBuilder private var utseendeRows: some View {
        @Bindable var settings = store.settings
        Toggle("Lekent tema (Catacloud)", isOn: $settings.playfulTheme)
        Text("Varme farger, runde kort, en regnskapsfører og små feiringer, inspirert av Catacloud. Skru det av for det nøkterne utseendet.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var reminderRows: some View {
        @Bindable var settings = store.settings
        Toggle("Minn meg på dagens oppgaver", isOn: $settings.reminderOn)
        DatePicker("Klokkeslett", selection: reminderTime, displayedComponents: .hourAndMinute)
            .environment(\.locale, Locale(identifier: "nb_NO"))
            .disabled(!settings.reminderOn)
        WeekdayPicker(selected: $settings.reminderWeekdays).disabled(!settings.reminderOn)
        Stepper("Oppgaver per dag: \(settings.dailyCount)", value: $settings.dailyCount, in: 1...10)
        Button("Send en testvarsling om 10 sekunder") { Reminder.shared.test() }
    }

    @ViewBuilder private var claudeRows: some View {
        @Bindable var settings = store.settings
        ClaudeStatusRow()
        Picker("Modell", selection: $settings.claudeModel) {
            Text("Sonnet (anbefalt)").tag("sonnet")
            Text("Opus (grundigere, tregere)").tag("opus")
            Text("Haiku (raskest)").tag("haiku")
        }
        Text("Når du trykker Forklar eller Spør, sendes oppgaven, fasiten og svaret ditt til Claude via Claude Code på denne maskinen. Fremdriften din sendes aldri.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var innholdRows: some View {
        @Bindable var settings = store.settings
        HStack {
            TextField("Innholdsmappe (tom = innholdet som følger med appen)", text: $settings.contentFolder)
                .onSubmit { store.reloadContent() }
            Button("Velg…", action: chooseFolder)
        }
        HStack {
            Button("Last inn på nytt") { store.reloadContent() }
            if let root = store.contentRoot { Text("Leser fra \(root.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
        }
        if let error = store.loadError { Text(error).font(.caption).foregroundStyle(Color.bad) }
        Toggle("Vis utkast (oppgaver som ikke er godkjent, også de Claude lager)", isOn: $settings.showDrafts)
    }

    @ViewBuilder private var spillRows: some View {
        @Bindable var settings = store.settings
        Toggle("Vis Spill i sidepanelet", isOn: $settings.showGame)
        Text("Paragrafjakten, Lynrunde og Debet eller kredit? Fremdriften og XP-en din beholdes når du skrur det av.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var oppdateringerRows: some View {
        @Bindable var settings = store.settings
        LabeledContent("Versjon") { Text(AppUpdater.currentVersion).monospacedDigit() }
        if AppUpdater.isDevelopmentBuild {
            Text("Dette er et utviklingsbygg og oppdaterer ikke seg selv.").font(.caption).foregroundStyle(.secondary)
        } else {
            if let update = store.availableUpdate {
                HStack {
                    Label("Versjon \(update.version) er klar", systemImage: "arrow.down.circle.fill").foregroundStyle(theme.isPlayful ? theme.accent : Color.skole)
                    Spacer()
                    Button(store.isUpdating ? "Oppdaterer…" : "Oppdater til \(update.version)") { Task { await store.installUpdate() } }
                        .buttonStyle(.borderedProminent).tint(.blue)
                        .disabled(store.isUpdating || update.assetURL == nil)
                }
                if !update.notes.isEmpty { MarkdownText(update.notes).font(.caption).frame(maxHeight: 160) }
            }
            if let state = store.updateState { Text(state).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Sjekk nå") { Task { await store.checkForAppUpdate(userInitiated: true) } }
                Spacer()
                Button("Utgivelser på GitHub") { NSWorkspace.shared.open(AppUpdater.releasesPage) }.buttonStyle(.borderless)
            }
            Toggle("Se etter oppdateringer", isOn: $settings.checkForUpdates)
        }
    }

    @ViewBuilder private var omRows: some View {
        LabeledContent("Fremdrift lagres i", value: ProgressStore.defaultURL.deletingLastPathComponent().path)
        Button("Kjør oppsett igjen") { navigation.showOnboarding = true }
    }

    /// Minutes from midnight as a Date on today's calendar day, for the time picker.
    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.norwegian.date(bySettingHour: store.settings.reminderMinutes / 60, minute: store.settings.reminderMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.norwegian.dateComponents([.hour, .minute], from: date)
                store.settings.reminderMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 30)
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Velg"
        panel.message = "Velg mappen Innhold/ (den med temaer.json)."
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.contentFolder = url.path
            store.reloadContent()
        }
    }
}

/// A settings section as a warm card, for the playful theme. Controls keep their native look inside it.
private struct SettingsCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).themedHeading().foregroundStyle(theme.secondaryText)
            VStack(alignment: .leading, spacing: 10) { content }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 16)
    }
}

/// Mon–Sun toggles; 1 = Monday as the settings store it.
struct WeekdayPicker: View {
    @Binding var selected: [Int]
    private let names = ["Ma", "Ti", "On", "To", "Fr", "Lø", "Sø"]

    var body: some View {
        LabeledContent("Ukedager") {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    Toggle(names[day - 1], isOn: Binding(
                        get: { selected.contains(day) },
                        set: { on in selected = on ? Array(Set(selected + [day])).sorted() : selected.filter { $0 != day } }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Claude Code's state with the buttons that fix it; shared by Settings and onboarding.
struct ClaudeStatusRow: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(store.claudeStatus.text)
                Spacer()
                Button("Sjekk på nytt") { Task { await store.checkClaude() } }.controlSize(.small)
            }
            switch store.claudeStatus {
            case .missing:
                HStack {
                    Button("Installer Claude Code…") { store.runInTerminal(ClaudeCLI.installCommand) }
                    Text("Åpner Terminal og kjører: \(ClaudeCLI.installCommand)").font(.caption).foregroundStyle(.secondary)
                }
            case .notSignedIn:
                HStack {
                    Button("Logg inn…") { store.runInTerminal(ClaudeCLI.loginCommand) }
                    Text("Åpner Terminal og kjører: \(ClaudeCLI.loginCommand)").font(.caption).foregroundStyle(.secondary)
                }
            case .ready, .unknown:
                EmptyView()
            }
        }
    }

    private var symbol: String {
        switch store.claudeStatus {
        case .ready: "checkmark.circle.fill"
        case .unknown: "clock"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch store.claudeStatus {
        case .ready: .ok
        case .unknown: .secondary
        default: .warn
        }
    }
}
