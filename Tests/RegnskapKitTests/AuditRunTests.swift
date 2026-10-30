import XCTest
@testable import RegnskapKit

final class AuditRunTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    let today = DayKey(year: 2027, month: 1, day: 12)
    let jan = MonthKey(year: 2026, month: 12)
    let client = makeLedgerClient()
    var content: TownContent { TownContent(bransjer: [], klienter: [client], kart: []) }
    var cards: [RuleCard] { Self.library.rules }

    func puzzle(_ id: String, tema: String = "mva", difficulty: Int = 2) -> Puzzle {
        try! Puzzle.decode(Data("""
        {"id":"\(id)","type":"quiz","tema":"\(tema)","vanskelighet":\(difficulty),"tags":[],"tittel":"T \(id)","oppgave":"O","lov":[{"lov":"bokføringsloven","paragraf":"§ 4","tekst":"T."}],"forklaring":"F","status":"godkjent","alternativer":["A","B"],"svar":0}
        """.utf8))
    }
    func error(_ puzzle: Puzzle, day: Int = 14) -> OpenError {
        OpenError(puzzleId: puzzle.id, client: client.id, month: jan, day: DayKey(year: 2026, month: 12, day: day), boxBefore: 2)
    }
    func examiner(_ name: String, _ puzzles: [Puzzle], sensor: Bool = false) -> AuditExaminer {
        AuditExaminer(ref: FagkontorRef(id: name.lowercased(), navn: name, temaer: ["mva"]), puzzles: puzzles, isSensor: sensor)
    }
    let right = PuzzleAttempt.quiz(0)
    let wrong = PuzzleAttempt.quiz(-1)

    func run(errors: [Puzzle], panel: [AuditExaminer] = [], extra: [Puzzle] = [], hidden: [OpenError] = [], equipped: String? = nil) -> AuditRun {
        let pool = errors + panel.flatMap(\.puzzles) + extra
        return AuditRun(year: 2026, errors: errors.map { error($0) } + hidden, panel: panel, puzzles: pool, content: content,
                        progress: LearnerProgress(), cards: cards, equipped: equipped, seed: 1)
    }

    /// Answers the current encounter and moves on.
    @discardableResult
    func play(_ r: inout AuditRun, _ attempt: PuzzleAttempt) -> EncounterOutcome? {
        r.choose(nil)
        let out = r.answer(attempt, progress: LearnerProgress(), today: today)?.outcome
        r.proceed()
        return out
    }

    func testReviewComesBeforeTheExaminers() {
        let errs = [puzzle("e1"), puzzle("e2")]
        var r = run(errors: errs, panel: [examiner("Kontrollør Aas", [puzzle("x1")]), examiner("Sensor Berg", [puzzle("s1")], sensor: true)])
        XCTAssertEqual(r.current?.context, .auditError(client: client.id, name: "TEST", day: DayKey(year: 2026, month: 12, day: 14)))
        XCTAssertEqual(r.currentError, error(errs[0]))
        XCTAssertEqual(r.current?.stageBefore, .ung)
        play(&r, right)
        XCTAssertEqual(r.current?.puzzle.id, "e2")
        play(&r, right)
        XCTAssertEqual(r.current?.context, .examiner(name: "Kontrollør Aas", first: true))
        XCTAssertEqual(r.currentExaminer?.ref.navn, "Kontrollør Aas")
        XCTAssertNil(r.currentError)
        play(&r, right)
        XCTAssertEqual(r.current?.context, .examiner(name: "Sensor Berg", first: true))
    }

    func testStepChangesOnEveryEncounterEvenWithTheSamePuzzle() {
        let shared = puzzle("e1")
        var r = run(errors: [shared, shared], panel: [examiner("Kontrollør Aas", [shared])])
        XCTAssertEqual(r.step, 1)
        play(&r, right)
        XCTAssertEqual(r.current?.puzzle.id, "e1")
        XCTAssertEqual(r.step, 2)
        play(&r, right)
        XCTAssertEqual(r.current?.puzzle.id, "e1")
        XCTAssertEqual(r.step, 3)
        play(&r, right)
        XCTAssertNil(r.current)
        XCTAssertEqual(r.step, 3)
    }

    func testSecondPuzzleOfAnExaminerContinues() {
        var r = run(errors: [], panel: [examiner("Kontrollør Aas", [puzzle("x1"), puzzle("x2")])])
        XCTAssertEqual(r.current?.context, .examiner(name: "Kontrollør Aas", first: true))
        play(&r, right)
        XCTAssertEqual(r.current?.context, .examiner(name: "Kontrollør Aas", first: false))
    }

    func testRightCorrectionCostsNothing() throws {
        var r = run(errors: [puzzle("e1")])
        r.choose(nil)
        let done = try XCTUnwrap(r.answer(right, progress: LearnerProgress(), today: today))
        XCTAssertEqual(done.outcome, .audited(ok: true, hpLost: 0))
        XCTAssertEqual(done.result, AttemptResult(puzzleId: "e1", correctFirstTry: true))
        XCTAssertEqual(r.hp, 10_000)
        XCTAssertEqual(r.fixed.count, 1)
        XCTAssertTrue(r.standing.isEmpty)
    }

    func testWrongCorrectionCostsTheErrorCost() throws {
        var r = run(errors: [puzzle("e1")])
        r.choose(nil)
        let done = try XCTUnwrap(r.answer(wrong, progress: LearnerProgress(), today: today))
        XCTAssertEqual(done.outcome, .audited(ok: false, hpLost: TownRules.auditErrorCost))
        XCTAssertEqual(r.hp, 9_000)
        XCTAssertEqual(r.standing.count, 1)
        XCTAssertEqual(done.result.correctFirstTry, false)
    }

    func testExaminerMissCostsByDifficulty() throws {
        var r = run(errors: [], panel: [examiner("Kontrollør Aas", [puzzle("x1", difficulty: 3)])])
        r.choose(nil)
        let done = try XCTUnwrap(r.answer(wrong, progress: LearnerProgress(), today: today))
        XCTAssertEqual(done.outcome, .audited(ok: false, hpLost: 1_500))
        XCTAssertEqual(r.hp, 8_500)
        XCTAssertEqual(r.remarks, 1)
    }

    func testReportedLossIsClampedToTheTrustLeft() throws {
        // Difficulty 3 costs 1 500 per miss: after six misses 1 000 is left, so the seventh reports 1 000.
        let panel = (0..<7).map { examiner("Kontrollør \($0)", [puzzle("x\($0)", difficulty: 3)]) }
        var r = run(errors: [], panel: panel)
        for _ in 0..<6 { play(&r, wrong) }
        XCTAssertEqual(r.hp, 1_000)
        r.choose(nil)
        let done = try XCTUnwrap(r.answer(wrong, progress: LearnerProgress(), today: today))
        XCTAssertEqual(done.outcome, .audited(ok: false, hpLost: 1_000))
        XCTAssertEqual(r.hp, 0)
    }

    func testMustChooseAMoveWhenOneIsOffered() {
        let real = Self.library.pool(includeDrafts: false).first { $0.kind == .quiz && Moves.canHit($0, regionCards: Self.library.rules(tema: $0.tema)) }!
        var r = run(errors: [real])
        XCTAssertFalse(r.current!.moves.isEmpty)
        XCTAssertNil(r.answer(.quiz(-1), progress: LearnerProgress(), today: today))
        XCTAssertFalse(r.hasChosen)
    }

    func testHPZeroEndsTheAuditAtOnce() {
        let errs = (1...10).map { puzzle("e\($0)") }
        var r = run(errors: errs, panel: [examiner("Kontrollør Aas", [puzzle("x1")])])
        for _ in 0..<10 { play(&r, wrong) }
        XCTAssertEqual(r.hp, 0)
        XCTAssertEqual(r.phase, .finished)
        XCTAssertFalse(r.won)
        XCTAssertNil(r.currentExaminer)
        XCTAssertEqual(r.standing.count, 10)
    }

    func testWinNeedsTheWholePanel() {
        var r = run(errors: [puzzle("e1")], panel: [examiner("Kontrollør Aas", [puzzle("x1")]), examiner("Sensor Berg", [puzzle("s1")], sensor: true)])
        play(&r, right)
        play(&r, right)
        XCTAssertFalse(r.won)
        XCTAssertEqual(r.phase, .encounter)
        play(&r, right)
        XCTAssertEqual(r.phase, .finished)
        XCTAssertTrue(r.completed)
        XCTAssertTrue(r.won)
        XCTAssertEqual(r.hp, 10_000)
    }

    func testFleeIsALoss() {
        var r = run(errors: [puzzle("e1"), puzzle("e2")])
        play(&r, right)
        r.finish()
        XCTAssertEqual(r.phase, .finished)
        XCTAssertFalse(r.completed)
        XCTAssertFalse(r.won)
    }

    func testHiddenErrorIsLeftOut() {
        let ghost = OpenError(puzzleId: "borte", client: client.id, month: jan, day: DayKey(year: 2026, month: 12, day: 2), boxBefore: 1)
        var r = run(errors: [puzzle("e1")], hidden: [ghost])
        play(&r, right)
        XCTAssertEqual(r.phase, .finished)
        XCTAssertEqual(r.hp, 10_000)
        XCTAssertTrue(r.standing.isEmpty)
        XCTAssertEqual(r.fixed.count, 1)
    }

    func testEquippedCardCountsInEveryEncounter() throws {
        let card = try XCTUnwrap(Self.library.rules.first { $0.tema != "mva" })
        let real = Self.library.pool(includeDrafts: false).filter { $0.kind == .quiz && $0.tema == card.tema }
        guard let hittable = real.first(where: { Moves.canHit($0, regionCards: [card]) }) else { return XCTFail("no puzzle on \(card.id)") }
        var r = run(errors: [hittable], equipped: card.id)
        let moves = try XCTUnwrap(r.current).moves
        XCTAssertTrue(moves.contains { Moves.hits($0, hittable) }, "the equipped card's move is on offer")
        r.choose(nil)
        _ = r.answer(right, progress: LearnerProgress(), today: today)
    }

    func testAuditHPMatchesTheBattleBar() {
        XCTAssertEqual(AuditRun.hp, RegionRun.hp)
    }

    func testResultTexts() {
        let won = TownFlow.auditResultTexts(won: true, year: 2026, today: today, standing: 0, newBadge: true)
        XCTAssertEqual(won, ["Bokettersynet er avsluttet uten merknader.", "Regnskapsåret 2027 er i gang.", "Du fikk merket «Revisorens beste venn»!"])
        XCTAssertEqual(TownFlow.auditResultTexts(won: true, year: 2026, today: today, standing: 0, newBadge: false).count, 2)
        let wonWithErrors = TownFlow.auditResultTexts(won: true, year: 2026, today: today, standing: 2, newBadge: false)
        XCTAssertFalse(wonWithErrors.joined().contains("uten merknader"))
        XCTAssertEqual(wonWithErrors.last, "2 feil fra 2026 står fortsatt åpne.")
        let lost = TownFlow.auditResultTexts(won: false, year: 2026, today: today, standing: 3, newBadge: false)
        XCTAssertEqual(lost, ["Bokettersynet er avbrutt.", "Du er tilbake på kontoret. Merkene dine er i behold.", "3 feil står fortsatt åpne."])
        XCTAssertEqual(TownFlow.auditResultTexts(won: false, year: 2026, today: today, standing: 0, newBadge: true).count, 2)
    }
}
