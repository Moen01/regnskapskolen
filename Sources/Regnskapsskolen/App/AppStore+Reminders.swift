import AppKit
import Foundation
import RegnskapKit

extension AppStore {
    /// Re-plans the notifications from the settings. Called at launch and after a settings change.
    func scheduleReminders() {
        guard settings.reminderOn else { Reminder.shared.cancelAll(); return }
        let topics = today.compactMap { topic($0.tema)?.navn }
        Reminder.shared.schedule(minutes: settings.reminderMinutes, weekdays: settings.reminderWeekdays, count: settings.dailyCount, topics: Array(Set(topics)).sorted())
    }

    /// Runs `command` in Terminal, for the install and login steps the app cannot do itself.
    func runInTerminal(_ command: String) {
        let script = "#!/bin/zsh\n\(command)\necho\necho 'Ferdig. Lukk vinduet og gå tilbake til Regnskapsskolen.'\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("regnskapsskolen-\(UUID().uuidString.prefix(6)).command")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}
