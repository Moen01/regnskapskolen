import Foundation

/// The town's own numbers. Rates and deadlines stay in `satser.json`; these are game balance only.
public enum TownRules {
    public static let actionsPerDay = 12
    public static let bilagPerMonth = 5
    public static let startSatisfaction = 60
    public static let maxSatisfaction = 100
    public static let deliverBonus = 10
    public static let correctionMiss = -10
    /// A customer case answered right pleases the client.
    public static let caseBonus = 5
    public static let missedDeadline = -25
    public static let warnDaysBefore = 3
    /// A client finds an old error on its own: one day in `discoverOneIn`, once the error is
    /// `discoverAfterDays` old, at a cost in satisfaction.
    public static let discoverOneIn: UInt64 = 4
    public static let discoverAfterDays = 7
    public static let discoveredPenalty = -15
    /// Energy is spent per encounter, right or wrong alike, so it never gives the verdict away.
    public static let maxEnergy = 100
    public static let energyPerEncounter = 5
    public static let coffeeEnergy = 30
    public static let coffeePerDay = 1
    public static let portfolioSize = 6
    public static let trialWinsNeeded = 2
    public static let fagkontorWinsNeeded = 3
    /// 2a has one fagkontor and no other way to earn a contract, so the player starts with one per
    /// client to win by trial (R12). 2c brings more fagkontor badges and lowers this.
    public static let startContracts = 3
    public static let contractsPerBadge = 1
}
