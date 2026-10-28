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
}
