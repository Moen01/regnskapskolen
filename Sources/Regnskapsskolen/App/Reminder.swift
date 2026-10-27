import Foundation
import UserNotifications

/// The daily reminder, one repeating calendar trigger per chosen weekday. UserNotifications needs
/// a real app bundle, so `swift run` gets nothing.
@MainActor
final class Reminder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminder()
    var onOpen: (() -> Void)?
    /// Tapping an update notification opens Settings instead of the day's puzzles.
    var onOpenUpdate: (() -> Void)?
    nonisolated static let updatePrefix = "oppdatering-"

    private var available: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }
    private var center: UNUserNotificationCenter? { available ? .current() : nil }

    func requestAuthorization() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable _, _ in }
    }

    func schedule(minutes: Int, weekdays: [Int], count: Int, topics: [String]) {
        guard let center else { return }
        cancelAll()
        for weekday in weekdays {
            var components = DateComponents()
            components.hour = minutes / 60
            components.minute = minutes % 60
            components.weekday = weekday % 7 + 1  // 1 = Monday … 7 = Sunday → Apple's 1 = Sunday
            let content = UNMutableNotificationContent()
            content.title = "Regnskapsskolen"
            content.body = "Dagens \(count) oppgaver venter." + (topics.isEmpty ? "" : " Tema: \(topics.joined(separator: ", ")).")
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: "paaminnelse-\(weekday)", content: content, trigger: trigger))
        }
    }

    func cancelAll() {
        center?.removePendingNotificationRequests(withIdentifiers: (1...7).map { "paaminnelse-\($0)" })
    }

    /// A test notification in ten seconds, from Settings.
    func test() {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Regnskapsskolen"
        content.body = "Slik ser påminnelsen ut."
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
    }

    /// "Versjon 0.2.0 er klar", once per version.
    func notifyUpdate(version: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Regnskapsskolen"
        content.body = "Versjon \(version) er klar"
        center.add(UNNotificationRequest(identifier: Self.updatePrefix + version, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let isUpdate = response.notification.request.identifier.hasPrefix(Self.updatePrefix)
        await MainActor.run { isUpdate ? self.onOpenUpdate?() : self.onOpen?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
