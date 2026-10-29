import XCTest
@testable import RegnskapKit

final class TownTrialsTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    let today = DayKey(string: "2026-02-03")!
    var pool: [Puzzle] { Self.library.pool(includeDrafts: false) }

    func trialClient(_ provesak: [String]) -> TownClient {
        let ids = provesak.map { "\"\($0)\"" }.joined(separator: ",")
        let lines = "{\"hilsen\":[],\"drift\":[],\"haug\":[],\"tomHaug\":[],\"glippetFrist\":[]}"
        let json = """
        {"id":"kafe","navn":"Kafé AS","bransje":"b","selskapsform":"as","mvaRegistrert":true,"ansatte":1,
         "sted":{"kart":"m","x":0,"y":0},"oppgaver":[],"provesak":[\(ids)],"replikker":\(lines),"status":"godkjent"}
        """
        return try! JSONDecoder().decode(TownClient.self, from: Data(json.utf8))
    }

    func puzzle(_ id: String, tema: String, vanskelighet: Int, edge: Bool) -> Puzzle {
        let tags = edge ? "[\"edge-case\"]" : "[]"
        return try! Puzzle.decode(Data("""
        {"id":"\(id)","type":"quiz","tema":"\(tema)","vanskelighet":\(vanskelighet),"tags":\(tags),"tittel":"T","oppgave":"O","lov":[{"lov":"bokføringsloven","paragraf":"§ 4","tekst":"T."}],"forklaring":"F","status":"godkjent","alternativer":["A","B"],"svar":0}
        """.utf8))
    }

    func testTrialCountsRepeatedAsWin() throws {
        let ids = ["mva-quiz-001", "mva-quiz-002", "mva-quiz-003"]
        let client = trialClient(ids)
        let region = TownTrials.trialRegion(for: client, pool: pool, progress: LearnerProgress())
        XCTAssertEqual(region.tema, "provesak-kafe")
        XCTAssertEqual(Set(region.puzzles.map(\.id)), Set(ids))
        XCTAssertNil(region.gymLeader)
        XCTAssertTrue(region.unlocked)

        // Every trial puzzle was answered in Trening earlier today: the run says .repeated.
        var progress = LearnerProgress()
        for id in ids { Scheduler.record(AttemptResult(puzzleId: id, correctFirstTry: true), on: today, progress: &progress) }
        var run = RegionRun(region: region, progress: progress, today: today, regionCards: Self.library.rules(tema: "mva"),
                            otherCards: [], seed: 1, context: .trial(client: client.id))
        var score = TrialScore()
        run.nextEncounter(progress: progress, today: today)
        while let e = run.current {
            XCTAssertEqual(e.context, .trial(client: client.id))
            guard case .quiz(let q) = e.puzzle.payload else { return XCTFail("quiz only") }
            run.choose(nil)
            let (outcome, _) = try XCTUnwrap(run.answer(.quiz(q.svar), progress: progress, today: today))
            XCTAssertEqual(outcome, .repeated)
            score.add(outcome)
            run.proceed()
            run.nextEncounter(progress: progress, today: today)
        }
        XCTAssertEqual(score.wins, 3)
        XCTAssertTrue(score.won(needed: TownRules.trialWinsNeeded))
    }

    func testTrialRegionLeavesOutPuzzlesOutsideThePool() {
        let region = TownTrials.trialRegion(for: trialClient(["mva-quiz-001", "finnes-ikke-001"]), pool: pool, progress: LearnerProgress())
        XCTAssertEqual(region.puzzles.map(\.id), ["mva-quiz-001"])
    }

    func testTwoOfThreeWinsTheTrial() {
        var score = TrialScore()
        score.add(.caught(stage: .klekket, superEffective: false))
        score.add(.escaped(hpLost: 500))
        XCTAssertFalse(score.won(needed: 2))
        score.add(.repeated)
        XCTAssertEqual(score.wins, 2)
        XCTAssertEqual(score.losses, 1)
        XCTAssertTrue(score.won(needed: 2))
        score.add(.booked)
        score.add(.corrected(ok: true))
        XCTAssertEqual(score.wins, 2, "town outcomes are not trial outcomes")
    }

    func testFagkontorPicksThreeHardestEdgeCasesFirst() throws {
        let puzzles = [
            puzzle("mva-a", tema: "mva", vanskelighet: 5, edge: false),
            puzzle("mva-b", tema: "mva", vanskelighet: 2, edge: true),
            puzzle("mva-c", tema: "mva", vanskelighet: 4, edge: true),
            puzzle("lonn-a", tema: "lonn", vanskelighet: 5, edge: true),
            puzzle("mva-d", tema: "mva", vanskelighet: 3, edge: false),
        ]
        let ref = FagkontorRef(id: "mva", navn: "Fagkontor MVA", temaer: ["mva"])
        let region = try XCTUnwrap(TownTrials.fagkontorRegion(ref, pool: puzzles, progress: LearnerProgress()))
        XCTAssertEqual(region.puzzles.map(\.id), ["mva-c", "mva-b", "mva-a"])
        XCTAssertNil(region.gymLeader)
        XCTAssertTrue(region.unlocked)
        XCTAssertNil(TownTrials.fagkontorRegion(ref, pool: Array(puzzles.prefix(2)), progress: LearnerProgress()), "fewer than three")
        XCTAssertEqual(TownTrials.badgeKey(ref), "fag-mva")
    }

    func testFagkontorOpensWhenEveryThemeReachedItsTarget() {
        let regions = Regions.build(topics: Self.library.topics, pool: pool, progress: LearnerProgress())
        let ref = FagkontorRef(id: "mva", navn: "Fagkontor MVA", temaer: ["mva", "lonn"])
        let target = { (tema: String) in regions.first { $0.tema == tema }!.damageTarget }
        XCTAssertGreaterThan(target("mva"), 0)
        XCTAssertFalse(TownTrials.fagkontorOpen(ref, regions: regions, damage: [:]))
        XCTAssertFalse(TownTrials.fagkontorOpen(ref, regions: regions, damage: ["mva": target("mva"), "lonn": target("lonn") - 1]))
        XCTAssertTrue(TownTrials.fagkontorOpen(ref, regions: regions, damage: ["mva": target("mva"), "lonn": target("lonn")]))
        let unknown = FagkontorRef(id: "x", navn: "X", temaer: ["finnes-ikke"])
        XCTAssertFalse(TownTrials.fagkontorOpen(unknown, regions: regions, damage: ["finnes-ikke": 10_000]))
    }
}
