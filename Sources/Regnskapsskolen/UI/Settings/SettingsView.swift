import AppKit
import RegnskapKit
import SwiftUI

/// Innstillinger: reminder, daily count, Claude, content folder and about.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Påminnelse") {
                Toggle("Minn meg på dagens oppgaver", isOn: $settings.reminderOn)
                DatePicker("Klokkeslett", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "nb_NO"))
                    .disabled(!settings.reminderOn)
                WeekdayPicker(selected: $settings.reminderWeekdays).disabled(!settings.reminderOn)
                Stepper("Oppgaver per dag: \(settings.dailyCount)", value: $settings.dailyCount, in: 1...10)
                Button("Send en testvarsling om 10 sekunder") { Reminder.shared.test() }
            }
            Section("Claude") {
                ClaudeStatusRow()
                Picker("Modell", selection: $settings.claudeModel) {
                    Text("Sonnet (anbefalt)").tag("sonnet")
                    Text("Opus (grundigere, tregere)").tag("opus")
                    Text("Haiku (raskest)").tag("haiku")
                }
                Text("Når du trykker Forklar eller Spør, sendes oppgaven, fasiten og svaret ditt til Claude via Claude Code på denne maskinen. Fremdriften din sendes aldri.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Innhold") {
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
            Section("Spill") {
                Toggle("Vis Spill i sidepanelet", isOn: $settings.showGame)
                Text("Paragrafjakten, Lynrunde og Debet eller kredit? Fremdriften og XP-en din beholdes når du skrur det av.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Oppdateringer") {
                LabeledContent("Versjon") { Text(AppUpdater.currentVersion).monospacedDigit() }
                if AppUpdater.isDevelopmentBuild {
                    Text("Dette er et utviklingsbygg og oppdaterer ikke seg selv.").font(.caption).foregroundStyle(.secondary)
                } else {
                    if let update = store.availableUpdate {
                        HStack {
                            Label("Versjon \(update.version) er klar", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.skole)
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
            Section("Om") {
                LabeledContent("Fremdrift lagres i", value: ProgressStore.defaultURL.deletingLastPathComponent().path)
                Button("Kjør oppsett igjen") { navigation.showOnboarding = true }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.reminderOn) { store.scheduleReminders() }
        .onChange(of: settings.reminderMinutes) { store.scheduleReminders() }
        .onChange(of: settings.reminderWeekdays) { store.scheduleReminders() }
        .onChange(of: settings.dailyCount) { store.scheduleReminders() }
        .onChange(of: settings.showDrafts) { store.reloadContent() }
        .onChange(of: settings.showGame) { if !settings.showGame, navigation.section == .game { navigation.section = .settings } }
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
