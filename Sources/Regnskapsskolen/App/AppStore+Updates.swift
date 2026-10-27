import AppKit
import Foundation
import RegnskapKit

// App updates: a check against GitHub Releases, an install on request, and the loop that checks.
extension AppStore {
    static let updateInterval: TimeInterval = 6 * 3600
    private static var isScreenshotRun: Bool { ProcessInfo.processInfo.environment["REGNSKAP_SCREENSHOTS"] != nil }

    func checkForAppUpdate(userInitiated: Bool = false) async {
        lastUpdateCheck = Date()
        if AppUpdater.isDevelopmentBuild {
            updateState = "Dette er et utviklingsbygg og oppdaterer ikke seg selv."
            return
        }
        do {
            guard let latest = try await AppUpdater().latest() else {
                if userInitiated { updateState = "Ingen utgivelser ennå." }
                return
            }
            if AppUpdater.isNewer(latest.version, than: AppUpdater.currentVersion) {
                availableUpdate = latest
                updateState = nil
                if !userInitiated, settings.lastNotifiedUpdate != latest.tag {
                    settings.lastNotifiedUpdate = latest.tag
                    Reminder.shared.notifyUpdate(version: latest.version)
                }
            } else {
                availableUpdate = nil
                if userInitiated { updateState = "Du har nyeste versjon (\(AppUpdater.currentVersion))." }
            }
        } catch {
            if userInitiated { updateState = error.localizedDescription }
        }
    }

    func installUpdate() async {
        guard let release = availableUpdate, !isUpdating, !AppUpdater.isDevelopmentBuild else { return }
        isUpdating = true
        updateState = "Laster ned \(release.version)…"
        do {
            try await AppUpdater().install(release)
            updateState = "Installert. Starter på nytt…"
            AppDelegate.shared?.relaunch()
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil)
        } catch {
            updateState = error.localizedDescription
            isUpdating = false
        }
    }

    /// Thirty seconds after launch, then every six hours while the app runs. Never in screenshot
    /// mode and never for a development build.
    func startUpdateLoop() {
        guard !Self.isScreenshotRun, !AppUpdater.isDevelopmentBuild else { return }
        updateLoop?.cancel()
        updateLoop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                guard let self else { return }
                if self.settings.checkForUpdates, Date().timeIntervalSince(self.lastUpdateCheck) > Self.updateInterval {
                    await self.checkForAppUpdate()
                }
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }
}
