import Foundation

/// The town's own numbers. Rates and deadlines stay in `satser.json`; these are game balance only.
public enum TownRules {
    public static let actionsPerDay = 12
    public static let bilagPerMonth = 5
    public static let startSatisfaction = 60
    public static let maxSatisfaction = 100
    public static let deliverBonus = 10
    public static let correctionMiss = -10
    public static let missedDeadline = -25
    public static let warnDaysBefore = 3
    public static let portfolioSize = 6
    public static let trialWinsNeeded = 2
    public static let fagkontorWinsNeeded = 3
    /// 2a has one fagkontor and no other way to earn a contract, so the player starts with one per
    /// client to win by trial (R12). 2c brings more fagkontor badges and lowers this.
    public static let startContracts = 3
    public static let contractsPerBadge = 1
}
