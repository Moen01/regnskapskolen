import RegnskapKit
import SwiftUI

/// First launch: what this is, when to be reminded, and whether Claude is ready.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @State private var step = 0

    var body: some View {
        @Bindable var settings = store.settings
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in Capsule().fill(i <= step ? Color.skole : Color.gray.opacity(0.2)).frame(height: 4) }
            }
            Group {
                switch step {
                case 0:
                    Text("Velkommen til Regnskapsskolen").font(.title2.weight(.semibold))
                    Text("Tre små oppgaver om dagen i norsk regnskap: føre bilag, mva, lønn, frister, årsoppgjør. Hver oppgave peker på paragrafen den bygger på. Det du får til, kommer sjeldnere tilbake; det du bommer på, kommer snart igjen.")
                    Text("Appen bor i menylinjen. Tallet der er oppgavene som gjenstår i dag.").foregroundStyle(.secondary)
                case 1:
                    Text("Når vil du minnes på?").font(.title2.weight(.semibold))
                    Toggle("Daglig påminnelse", isOn: $settings.reminderOn)
                    DatePicker("Klokkeslett", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "nb_NO"))
                        .disabled(!settings.reminderOn)
                    WeekdayPicker(selected: $settings.reminderWeekdays).disabled(!settings.reminderOn)
                    Stepper("Oppgaver per dag: \(settings.dailyCount)", value: $settings.dailyCount, in: 1...10)
                default:
                    Text("Claude forklarer").font(.title2.weight(.semibold))
                    Text("Forklar, Spør og Vanskeligere oppgave bruker Claude Code på denne maskinen, med din egen innlogging. Uten Claude virker alt annet som før.")
                    ClaudeStatusRow()
                    Text("Bare oppgaven, fasiten og svaret ditt sendes. Fremdriften din blir på maskinen.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Tilbake") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("Neste") { step += 1 }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.skole)
                } else {
                    Button("Ferdig", action: finish).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.skole)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .onAppear { Task { await store.checkClaude() } }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.norwegian.date(bySettingHour: store.settings.reminderMinutes / 60, minute: store.settings.reminderMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.norwegian.dateComponents([.hour, .minute], from: date)
                store.settings.reminderMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 30)
            }
        )
    }

    private func finish() {
        store.settings.onboardingDone = true
        store.scheduleReminders()
        navigation.showOnboarding = false
    }
}
