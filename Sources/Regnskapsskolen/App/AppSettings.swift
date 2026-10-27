import Foundation
import Observation

/// The learner's preferences, in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    /// Minutes from midnight; default 08:30.
    var reminderMinutes: Int { didSet { defaults.set(reminderMinutes, forKey: "paaminnelse.tid") } }
    /// 1 = Monday … 7 = Sunday.
    var reminderWeekdays: [Int] { didSet { defaults.set(reminderWeekdays, forKey: "paaminnelse.ukedager") } }
    var reminderOn: Bool { didSet { defaults.set(reminderOn, forKey: "paaminnelse.paa") } }
    var dailyCount: Int { didSet { defaults.set(dailyCount, forKey: "dagligAntall") } }
    var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "claude.modell") } }
    var contentFolder: String { didSet { defaults.set(contentFolder, forKey: "innholdMappe") } }
    var showDrafts: Bool { didSet { defaults.set(showDrafts, forKey: "visUtkast") } }
    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboarding.v1") } }
    /// The sandbox case the journal belongs to, so "Sjekk mot fasit" survives a relaunch.
    var sandboxCaseId: String { didSet { defaults.set(sandboxCaseId, forKey: "sandkasse.case") } }
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "oppdateringer.sjekk") } }
    /// The tag last announced with a notification, so one version is announced once.
    var lastNotifiedUpdate: String { didSet { defaults.set(lastNotifiedUpdate, forKey: "oppdateringer.varslet") } }

    init() {
        reminderMinutes = defaults.object(forKey: "paaminnelse.tid") as? Int ?? 8 * 60 + 30
        reminderWeekdays = defaults.array(forKey: "paaminnelse.ukedager") as? [Int] ?? [1, 2, 3, 4, 5]
        reminderOn = defaults.object(forKey: "paaminnelse.paa") as? Bool ?? true
        dailyCount = defaults.object(forKey: "dagligAntall") as? Int ?? 3
        claudeModel = defaults.string(forKey: "claude.modell") ?? "sonnet"
        contentFolder = defaults.string(forKey: "innholdMappe") ?? ""
        showDrafts = defaults.bool(forKey: "visUtkast")
        onboardingDone = defaults.bool(forKey: "onboarding.v1")
        sandboxCaseId = defaults.string(forKey: "sandkasse.case") ?? ""
        checkForUpdates = defaults.object(forKey: "oppdateringer.sjekk") as? Bool ?? true
        lastNotifiedUpdate = defaults.string(forKey: "oppdateringer.varslet") ?? ""
    }

    var reminderTimeText: String { String(format: "%02d:%02d", reminderMinutes / 60, reminderMinutes % 60) }
}
