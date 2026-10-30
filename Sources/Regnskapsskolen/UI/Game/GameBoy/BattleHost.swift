import RegnskapKit

/// What `BattleScreen` needs from whoever drives the fight. The adventure maps it onto the store;
/// other games supply their own closures, so the screen never knows which game it serves.
struct BattleHost {
    let encounter: () -> Encounter?
    let session: () -> PuzzleSession?
    /// The result of the last answer, or nil while the learner is still answering.
    let outcome: () -> EncounterOutcome?
    /// The client's HP; nil hides the HP bar (a game without one).
    let hp: () -> Int?
    let choose: (Move?) -> Void
    /// Judges the attempt kept in the session.
    let attack: () -> Void
    let flee: () -> Void
    let next: () -> Void
    // Beyond the brief: the screen builds its flow from the content library and writes the
    // learner's attempt back into the session, so the host must offer both.
    let library: () -> ContentLibrary?
    let setAttempt: (PuzzleAttempt) -> Void
    /// The stage to show instead of the encounter's own; nil keeps `stageBefore`.
    var stage: () -> Stage? = { nil }

    @MainActor
    static func adventure(_ store: AppStore) -> BattleHost {
        BattleHost(
            encounter: { store.run?.current },
            session: { store.encounterSession },
            outcome: {
                guard case .result(let outcome) = store.run?.phase else { return nil }
                return outcome
            },
            hp: { store.run?.hp },
            choose: { store.chooseMove($0) },
            attack: { store.answerEncounter() },
            flee: { store.endRun() },
            next: { store.proceedEncounter() },
            library: { store.library },
            setAttempt: { store.encounterSession?.attempt = $0 })
    }

    /// A bilag or a correction at a client: no HP (a bilag cannot flee, FLYKT just leaves the desk),
    /// and the stage the bilag had before booking, since Kit shows every bilag as fresh.
    @MainActor
    static func bilag(_ store: AppStore) -> BattleHost {
        BattleHost(
            encounter: { store.bilagRun?.current },
            session: { store.townSession },
            outcome: {
                guard case .result(let outcome) = store.bilagRun?.phase else { return nil }
                return outcome
            },
            hp: { nil },
            choose: { store.bilagRun?.choose($0) },
            attack: { store.answerBilag() },
            flee: { store.finishBilag() },
            next: { store.proceedBilag() },
            library: { store.library },
            setAttempt: { store.townSession?.attempt = $0 },
            stage: { store.bilagStage })
    }

    /// A customer case: the same `BilagRun` as a bilag, but its verdict is told and the creature
    /// keeps the encounter's own stage. No HP: FLYKT leaves the case open for another day.
    @MainActor
    static func kundesak(_ store: AppStore) -> BattleHost {
        var host = bilag(store)
        host.stage = { nil }
        return host
    }

    /// A client's trial or a fagkontor: a `RegionRun` with the client's HP, scored by `TrialScore`.
    @MainActor
    static func townTrial(_ store: AppStore) -> BattleHost {
        BattleHost(
            encounter: { store.townRun?.current },
            session: { store.townSession },
            outcome: {
                guard case .result(let outcome) = store.townRun?.phase else { return nil }
                return outcome
            },
            hp: { store.townRun?.hp },
            choose: { store.townRun?.choose($0) },
            attack: { store.answerTownRun() },
            flee: { store.finishTownRun() },
            next: { store.proceedTownRun() },
            library: { store.library },
            setAttempt: { store.townSession?.attempt = $0 })
    }

    /// The bokettersyn: one trust meter over the open errors and the examiners. FLYKT ends the
    /// audit as a fail; the stage is the encounter's own (an error carries its box from before).
    @MainActor
    static func audit(_ store: AppStore) -> BattleHost {
        BattleHost(
            encounter: { store.auditRun?.current },
            session: { store.townSession },
            outcome: {
                guard case .result(let outcome) = store.auditRun?.phase else { return nil }
                return outcome
            },
            hp: { store.auditRun?.hp },
            choose: { store.auditRun?.choose($0) },
            attack: { store.answerAudit() },
            flee: { store.finishAudit() },
            next: { store.proceedAudit() },
            library: { store.library },
            setAttempt: { store.townSession?.attempt = $0 })
    }
}
