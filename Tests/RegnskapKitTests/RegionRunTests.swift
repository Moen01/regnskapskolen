import XCTest
@testable import RegnskapKit

final class RegionRunTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    let today = DayKey(string: "2026-10-28")!
    var pool: [Puzzle] { Self.library.pool(includeDrafts: true) }
    func region(_ tema: String, progress: LearnerProgress = LearnerProgress()) -> Region {
        Regions.build(topics: Self.library.topics, pool: pool, progress: progress).first { $0.tema == tema }!
    }
    func run(_ tema: String, progress: LearnerProgress = LearnerProgress(), seed: UInt64 = 1) -> RegionRun {
        RegionRun(region: region(tema, progress: progress), progress: progress, today: today, regionCards: Self.library.rules(tema: tema), otherCards: Self.library.rules.filter { $0.tema != tema }, seed: seed)
    }
    /// The fasit for every kind the game can meet.
    func correct(_ p: Puzzle) -> PuzzleAttempt {
        switch p.payload {
        case .quiz(let q): .quiz(q.svar)
        case .vat(let v): .vat(behandling: v.fasit.behandling, fradrag: v.fasit.fradrag)
        case .case(let c): .case(c.svar)
        case .number(let n): .number(NorwegianFormat.kroner(n.svar))
        case .deadline(let d): .deadline(d.fasit)
        case .classify(let c): .classify(Dictionary(uniqueKeysWithValues: c.elementer.enumerated().map { ($0.offset, $0.element.svar) }))
        case .spot(let s): .spot(Set(s.elementer.enumerated().filter { $0.element.feil }.map(\.offset)))
        case .posting(let p): .posting(p.fasit.map { PostingAttemptLine(konto: $0.konto, debet: $0.side == .debet ? $0.belop : nil, kredit: $0.side == .kredit ? $0.belop : nil) })
        }
    }

    func testFirstEncounterIsWildAndEasyAndMovesAreOfferedWhenHittable() {
        var r = run("mva")
        r.nextEncounter(progress: LearnerProgress(), today: today)
        let e = r.current!
        XCTAssertEqual(e.stageBefore, .vill)
        XCTAssertFalse(e.isGymLeader)
        XCTAssertEqual(e.puzzle.vanskelighet, r.region.puzzles.filter { $0.id != r.region.gymLeader?.id }.map(\.vanskelighet).min())
        if Moves.canHit(e.puzzle, regionCards: Self.library.rules(tema: "mva")) { XCTAssertFalse(e.moves.isEmpty) } else { XCTAssertTrue(e.moves.isEmpty) }
    }

    func testCatchWithAHitDoublesDamageAndXP() throws {
        var progress = LearnerProgress()
        var r = run("mva")
        var found: Encounter?
        for _ in 0..<20 {   // walk until an encounter offers a hitting move
            r.nextEncounter(progress: progress, today: today)
            guard let e = r.current else { break }
            if e.moves.contains(where: { Moves.hits($0, e.puzzle) }) { found = e; break }
            r.choose(nil); _ = r.answer(correct(e.puzzle), progress: progress, today: today); r.proceed()
        }
        let e = try XCTUnwrap(found)
        let hit = try XCTUnwrap(e.moves.first { Moves.hits($0, e.puzzle) })
        let damageBefore = r.damage, xpBefore = r.xp, caughtBefore = r.caught
        r.choose(hit)
        let (outcome, result) = try XCTUnwrap(r.answer(correct(e.puzzle), progress: progress, today: today))
        XCTAssertEqual(outcome, .caught(stage: .klekket, superEffective: true))
        XCTAssertEqual(result, AttemptResult(puzzleId: e.puzzle.id, correctFirstTry: true))
        XCTAssertEqual(r.damage - damageBefore, e.puzzle.vanskelighet * 200)
        XCTAssertEqual(r.xp - xpBefore, XP.forPuzzle(vanskelighet: e.puzzle.vanskelighet, correctFirstTry: true) * 2)
        XCTAssertEqual(r.caught, caughtBefore + 1); XCTAssertEqual(r.phase, .result(outcome))
        Scheduler.record(result, on: today, progress: &progress)
        XCTAssertEqual(progress.puzzles[e.puzzle.id]?.box, 1)
    }

    func testEscapeCostsHPAndAWrongRuleGivesNoBonus() throws {
        var r = run("lonn")
        r.nextEncounter(progress: LearnerProgress(), today: today)
        let e = try XCTUnwrap(r.current)
        r.choose(nil)
        let (outcome, result) = try XCTUnwrap(r.answer(.quiz(-1), progress: LearnerProgress(), today: today))
        XCTAssertEqual(outcome, .escaped(hpLost: e.puzzle.vanskelighet * 500))
        XCTAssertEqual(r.hp, RegionRun.hp - e.puzzle.vanskelighet * 500)
        XCTAssertEqual(result.correctFirstTry, false)
        XCTAssertEqual(r.damage, 0); XCTAssertEqual(r.xp, 0); XCTAssertEqual(r.escaped, 1)
        r.proceed(); XCTAssertEqual(r.phase, .encounter)
    }

    func testEmptyHPEndsTheRunAndCutsSavedDamageByAQuarter() throws {
        var progress = LearnerProgress()
        progress.game.regionDamage["lonn"] = 800
        var r = run("lonn", progress: progress)
        XCTAssertEqual(r.damage, 800, "continues from the saved damage")
        var guardCount = 0
        while r.hp > 0, guardCount < 30 {
            guardCount += 1
            r.nextEncounter(progress: progress, today: today)
            guard r.current != nil else { break }
            r.choose(nil); _ = r.answer(.quiz(-1), progress: progress, today: today)
            r.proceed()
        }
        XCTAssertEqual(r.hp, 0)
        XCTAssertEqual(r.phase, .finished)
        XCTAssertEqual(r.damageToSave, 600)
        XCTAssertEqual(r.summary.hpLeft, 0)
    }

    func testGymLeaderComesOnlyWhenTheMeterIsFullAndEarnsTheBadge() throws {
        var progress = LearnerProgress()
        progress.game.regionDamage["periodisering"] = 10_000   // well past the target
        var r = run("periodisering", progress: progress)
        XCTAssertTrue(r.gymReady)
        r.nextEncounter(progress: progress, today: today)
        let e = try XCTUnwrap(r.current)
        XCTAssertTrue(e.isGymLeader)
        XCTAssertEqual(e.puzzle.id, r.region.gymLeader?.id)
        r.choose(nil)
        _ = r.answer(correct(e.puzzle), progress: progress, today: today)
        XCTAssertTrue(r.gymBadgeEarned)
        XCTAssertEqual(r.xp, XP.forPuzzle(vanskelighet: e.puzzle.vanskelighet, correctFirstTry: true) + RegionRun.gymXP)
        XCTAssertTrue(r.summary.gymBadge)
        r.proceed(); r.nextEncounter(progress: progress, today: today)
        XCTAssertFalse(r.current?.isGymLeader ?? false, "the leader is not met twice in a run")
    }

    func testAnsweredTodayComesLastAndGivesNoXP() throws {
        var progress = LearnerProgress()
        let lonn = pool.filter { $0.tema == "lonn" }.sorted { $0.id < $1.id }
        for p in lonn { progress.puzzles[p.id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: today, due: today.adding(days: 1)) }
        progress.puzzles[lonn[0].id] = PuzzleProgress(box: 1, attempts: 1, correct: 1, lastSeen: today.adding(days: -3), due: today.adding(days: -2))
        var r = run("lonn", progress: progress)
        r.nextEncounter(progress: progress, today: today)
        XCTAssertEqual(r.current?.puzzle.id, lonn[0].id, "the one due review comes first")
        r.choose(nil); _ = r.answer(correct(lonn[0]), progress: progress, today: today); r.proceed()
        r.nextEncounter(progress: progress, today: today)
        let e = try XCTUnwrap(r.current)
        let xpBefore = r.xp, damageBefore = r.damage, caughtBefore = r.caught
        r.choose(nil)
        let (outcome, _) = try XCTUnwrap(r.answer(correct(e.puzzle), progress: progress, today: today))
        XCTAssertEqual(outcome, .repeated, "already answered today: no catch, no damage, no XP")
        XCTAssertEqual(r.xp, xpBefore); XCTAssertEqual(r.damage, damageBefore); XCTAssertEqual(r.caught, caughtBefore)
    }

    func testAWildCreatureMetTodayComesLastAndIsNotCaughtAgain() throws {
        var progress = LearnerProgress()
        let lonn = pool.filter { $0.tema == "lonn" }.sorted { $0.id < $1.id }
        progress.puzzles[lonn[0].id] = PuzzleProgress(box: 0, attempts: 1, correct: 0, lastSeen: today, due: today)   // escaped earlier today
        var r = run("lonn", progress: progress)
        r.nextEncounter(progress: progress, today: today)
        XCTAssertNotEqual(r.current?.puzzle.id, lonn[0].id, "a creature met today is not first")
        var seen = 0
        while let e = r.current, e.puzzle.id != lonn[0].id, seen < 20 {
            seen += 1; r.choose(nil); _ = r.answer(correct(e.puzzle), progress: progress, today: today); r.proceed(); r.nextEncounter(progress: progress, today: today)
        }
        let e = try XCTUnwrap(r.current)
        XCTAssertEqual(e.puzzle.id, lonn[0].id, "it comes last")
        r.choose(nil)
        let (outcome, result) = try XCTUnwrap(r.answer(correct(e.puzzle), progress: progress, today: today))
        XCTAssertEqual(outcome, .repeated)
        XCTAssertTrue(result.correctFirstTry)
    }

    func testTheRuleMustBeChosenBeforeAnsweringWhenThereAreMoves() throws {
        var r = run("mva")
        var e: Encounter?
        for _ in 0..<20 { r.nextEncounter(progress: LearnerProgress(), today: today); guard let c = r.current else { break }; if !c.moves.isEmpty { e = c; break }; r.choose(nil); _ = r.answer(correct(c.puzzle), progress: LearnerProgress(), today: today); r.proceed() }
        let encounter = try XCTUnwrap(e)
        XCTAssertFalse(r.hasChosen)
        XCTAssertNil(r.answer(correct(encounter.puzzle), progress: LearnerProgress(), today: today), "no answer before the rule is chosen")
        r.choose(nil)
        XCTAssertTrue(r.hasChosen)
        XCTAssertNotNil(r.answer(correct(encounter.puzzle), progress: LearnerProgress(), today: today))
    }

    func testACorrectAnswerWithAWrongRuleGivesSingleDamage() throws {
        var r = run("mva")
        var e: Encounter?
        for _ in 0..<20 { r.nextEncounter(progress: LearnerProgress(), today: today); guard let c = r.current else { break }; if !c.moves.isEmpty { e = c; break }; r.choose(nil); _ = r.answer(correct(c.puzzle), progress: LearnerProgress(), today: today); r.proceed() }
        let encounter = try XCTUnwrap(e)
        let miss = try XCTUnwrap(encounter.moves.first { !Moves.hits($0, encounter.puzzle) })
        let before = r.damage
        r.choose(miss)
        let (outcome, _) = try XCTUnwrap(r.answer(correct(encounter.puzzle), progress: LearnerProgress(), today: today))
        XCTAssertEqual(outcome, .caught(stage: .klekket, superEffective: false))
        XCTAssertEqual(r.damage - before, encounter.puzzle.vanskelighet * 100)
    }

    func testTheLeaderIsAnOrdinaryCreatureOnceTheBadgeIsHeld() throws {
        var progress = LearnerProgress()
        progress.game.badges["gym-periodisering"] = today.adding(days: -1)
        let held = region("periodisering", progress: progress)
        XCTAssertNotNil(held.gymBadge)
        var r = RegionRun(region: held, progress: progress, today: today, regionCards: Self.library.rules(tema: "periodisering"), otherCards: [], seed: 1)
        var ids: Set<String> = []
        for _ in 0..<held.puzzles.count {
            r.nextEncounter(progress: progress, today: today)
            guard let e = r.current else { break }
            XCTAssertFalse(e.isGymLeader)
            ids.insert(e.puzzle.id)
            r.choose(nil); _ = r.answer(correct(e.puzzle), progress: progress, today: today); r.proceed()
        }
        XCTAssertTrue(ids.contains(held.gymLeader!.id), "the former leader is met like any other creature")
    }

    func testAWrongAnswerOnACaughtCreatureSendsItBackToTheWild() throws {
        var progress = LearnerProgress()
        let lonn = pool.filter { $0.tema == "lonn" }
        for p in lonn { progress.puzzles[p.id] = PuzzleProgress(box: 2, attempts: 2, correct: 2, lastSeen: today.adding(days: -5), due: today.adding(days: -2)) }
        var r = run("lonn", progress: progress)
        r.nextEncounter(progress: progress, today: today)
        let e = try XCTUnwrap(r.current)
        XCTAssertEqual(e.stageBefore, .ung)
        r.choose(nil)
        let (_, result) = try XCTUnwrap(r.answer(.quiz(-1), progress: progress, today: today))
        Scheduler.record(result, on: today, progress: &progress)
        XCTAssertEqual(progress.puzzles[e.puzzle.id]?.box, 0, "back to the wild")
    }

    func testEmptyRegionFinishesAtOnce() {
        let empty = Region(tema: "tom", navn: "Tom", rekkefolge: 99, theme: Regions.themes["mva"]!, puzzles: [], gymLeader: nil, caught: 0, mastered: 0, unlocked: true, gymBadge: nil)
        var r = RegionRun(region: empty, progress: LearnerProgress(), today: today, regionCards: [], otherCards: [], seed: 1)
        r.nextEncounter(progress: LearnerProgress(), today: today)
        XCTAssertNil(r.current); XCTAssertEqual(r.phase, .finished)
    }
}
