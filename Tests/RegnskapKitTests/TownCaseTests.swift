import XCTest
@testable import RegnskapKit

/// Customer cases: a person in town asks an active client's question. The verdict is told, a right
/// answer pleases the client, and each case is offered once.
final class TownCaseTests: XCTestCase {
    static let library = TownFlowTests.library
    static let town = TownFlowTests.town
    let today = DayKey(string: "2026-02-03")!
    let puzzleId = "mva-quiz-001"
    let client = "kafeen"

    private var person: TownPerson {
        TownPerson(id: "sak-kafeen", rolle: .kundesak, x: 1, y: 1, klient: client, fagkontor: nil, tekst: ["Kan du hjelpe?"], oppgave: puzzleId)
    }

    private func puzzle() throws -> Puzzle { try XCTUnwrap(Self.library.puzzle(id: puzzleId)) }

    private func quizAttempt(_ p: Puzzle, right: Bool) -> PuzzleAttempt {
        guard case .quiz(let q) = p.payload else { fatalError("quiz only") }
        return .quiz(right ? q.svar : -1)
    }

    private func caseRun() throws -> BilagRun {
        let town = try XCTUnwrap(Self.town.client(client))
        let cards = Self.library.rules(tema: "mva")
        return BilagRun(client: town, puzzles: [try puzzle()], kind: .kundesak(puzzle: puzzleId), errors: [],
                        bransjeCards: cards, otherCards: Self.library.rules.filter { $0.tema != "mva" }, seed: 1)
    }

    private func flow(status: ClientStatus, done: Set<String> = []) -> TownFlow {
        var s = TownState.new(content: Self.town, year: 2026)
        s.clients[client] = ClientState(status: status, satisfaction: 60, met: true, casesDone: done)
        return TownFlow(content: Self.town, state: s, deadlines: Self.library.deadlines, pool: TownFlowTests.pool,
                        regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
    }

    private func read(_ f: inout TownFlow) {
        for _ in 0..<50 where f.phase == .dialog { _ = f.key(.a) }
    }

    func testCaseShowsTheVerdictAndTheExplanation() throws {
        let p = try puzzle()
        var r = try caseRun()
        let encounter = try XCTUnwrap(r.current)
        XCTAssertEqual(encounter.context, .kundesak(client: client, name: "KAFÉ"))
        r.choose(nil)
        let wrong = try XCTUnwrap(r.answer(quizAttempt(p, right: false), progress: LearnerProgress(), today: today))
        XCTAssertEqual(wrong.outcome, .answered(ok: false))
        XCTAssertFalse(wrong.result.correctFirstTry)
        XCTAssertEqual(wrong.damage, 0)
        r.proceed()
        XCTAssertEqual(r.phase, .finished, "one meeting")

        var good = try caseRun()
        good.choose(nil)
        let right = try XCTUnwrap(good.answer(quizAttempt(p, right: true), progress: LearnerProgress(), today: today))
        XCTAssertEqual(right.outcome, .answered(ok: true))
        XCTAssertEqual(right.damage, p.vanskelighet * RegionRunRules.damagePerLevel)

        // R7: a puzzle already answered today deals no damage.
        var seen = LearnerProgress()
        Scheduler.record(AttemptResult(puzzleId: p.id, correctFirstTry: true), on: today, progress: &seen)
        var again = try caseRun()
        again.choose(nil)
        XCTAssertEqual(again.answer(quizAttempt(p, right: true), progress: seen, today: today)?.damage, 0)

        // Both verdicts lead on to the explanation, like a correction.
        for ok in [true, false] {
            var f = BattleFlow(encounter: encounter, laws: Self.library.laws, cards: [], rates: Self.library.rates.mvaSatser,
                               attempt: .empty(for: .quiz))
            var a = PuzzleAttempt.empty(for: .quiz)
            f.showOutcome(.answered(ok: ok))
            while f.hasMorePages { _ = f.handle(.a, attempt: &a) }
            XCTAssertEqual(f.handle(.a, attempt: &a), .none)
            XCTAssertEqual(f.phase, .explanation, "ok: \(ok)")
        }
    }

    func testRightCaseGivesFive() throws {
        var s = ClientState(status: .active, satisfaction: 60, met: true)
        s.answerCase(puzzleId, ok: true)
        XCTAssertEqual(s.satisfaction, 60 + TownRules.caseBonus)
        XCTAssertEqual(TownRules.caseBonus, 5)
        XCTAssertEqual(s.casesDone, [puzzleId])

        var miss = ClientState(status: .active, satisfaction: 60, met: true)
        miss.answerCase(puzzleId, ok: false)
        XCTAssertEqual(miss.satisfaction, 60, "a wrong answer costs nothing")
        XCTAssertEqual(miss.casesDone, [puzzleId])

        var full = ClientState(status: .active, satisfaction: 98, met: true)
        full.answerCase(puzzleId, ok: true)
        XCTAssertEqual(full.satisfaction, TownRules.maxSatisfaction)
    }

    func testOldSaveWithoutCasesDecodesEmpty() throws {
        let old = ClientState(status: .active, satisfaction: 70, met: true, casesDone: ["x"])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "casesDone")
        let decoded = try JSONDecoder().decode(ClientState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.casesDone, [])
        XCTAssertEqual(decoded.satisfaction, 70)
        let again = try JSONDecoder().decode(ClientState.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(again, old)
    }

    func testCaseIsOfferedOnce() {
        var f = flow(status: .active)
        _ = f.talk(to: person)
        read(&f)
        XCTAssertEqual(f.phase, .choice)
        XCTAssertEqual(f.pages, [["Hjelpe nå?"]])
        XCTAssertEqual(f.key(.a), .startCase(client: client, puzzle: puzzleId))
        XCTAssertTrue(TownAction.startCase(client: client, puzzle: puzzleId).spendsAction)

        var declined = flow(status: .active)
        _ = declined.talk(to: person)
        read(&declined)
        _ = declined.key(.down)
        XCTAssertEqual(declined.key(.a), .none, "NEI starts nothing")
        XCTAssertEqual(declined.phase, .walking)

        var done = flow(status: .active, done: [puzzleId])
        _ = done.talk(to: person)
        XCTAssertEqual(done.pages, [["Kan du hjelpe?"]])
        read(&done)
        XCTAssertEqual(done.phase, .walking, "the text alone, no choice")
    }

    func testCaseNeedsAnActiveClient() {
        for status in [ClientStatus.prospect, .archived] {
            var f = flow(status: status)
            _ = f.talk(to: person)
            XCTAssertEqual(f.pages, [["Jeg er ikke kunde hos deg."]], "\(status)")
            read(&f)
            XCTAssertEqual(f.phase, .walking)
        }
    }

    func testCaseScriptLinesFitTheDialogBox() throws {
        let p = try puzzle()
        for name in ["KAFÉ", "NETTBUTIKKEN", "LEGEKONTORET"] {
            let e = Encounter(puzzle: p, stageBefore: .vill, moves: [], isGymLeader: false, context: .kundesak(client: client, name: name))
            XCTAssertEqual(BattleScript.intro(e), ["\(name) lurer på noe!", p.tittel])
            let texts = BattleScript.intro(e) + BattleScript.result(.answered(ok: true), encounter: e) + BattleScript.result(.answered(ok: false), encounter: e)
            for page in BattleFlow.paged(texts) {
                XCTAssertLessThanOrEqual(page.count, BattleFlow.rows, "\(page)")
                XCTAssertTrue(page.allSatisfy { $0.count <= BattleFlow.columns }, "\(page)")
            }
        }
        let e = Encounter(puzzle: p, stageBefore: .vill, moves: [], isGymLeader: false, context: .kundesak(client: client, name: "KAFÉ"))
        XCTAssertEqual(BattleScript.result(.answered(ok: true), encounter: e), ["Kunden er fornøyd."])
        XCTAssertEqual(BattleFlow.paged(BattleScript.result(.answered(ok: true), encounter: e)), [["Kunden er fornøyd."]], "one page")
        XCTAssertEqual(BattleScript.result(.answered(ok: false), encounter: e), ["Det stemte ikke."])
    }
}
