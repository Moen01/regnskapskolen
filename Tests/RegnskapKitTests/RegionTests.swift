import XCTest
@testable import RegnskapKit

final class RegionTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    var topics: [Topic] { Self.library.topics }
    var pool: [Puzzle] { Self.library.pool(includeDrafts: true) }

    func testStages() {
        XCTAssertEqual(Stage.of(box: nil), .vill); XCTAssertEqual(Stage.of(box: 0), .vill)
        XCTAssertEqual(Stage.of(box: 1), .klekket); XCTAssertEqual(Stage.of(box: 4), .mester); XCTAssertEqual(Stage.of(box: 9), .mester)
        XCTAssertEqual(Stage.allCases.map(\.navn), ["Vill", "Klekket", "Ung", "Voksen", "Mester"])
    }

    func testEveryTopicHasAThemeAndARegionInOrder() {
        let regions = Regions.build(topics: topics, pool: pool, progress: LearnerProgress())
        XCTAssertEqual(regions.map(\.tema), topics.sorted { $0.rekkefolge < $1.rekkefolge }.map(\.id))
        for region in regions { XCTAssertFalse(region.theme.setning.isEmpty, region.tema); XCTAssertFalse(region.theme.symbol.isEmpty, region.tema) }
        XCTAssertTrue(regions[0].unlocked)
        XCTAssertFalse(regions[1].unlocked, "nothing caught yet")
    }

    func testGymLeaderPrefersEdgeCasesThenDifficultyThenId() {
        let mva = pool.filter { $0.tema == "mva" }
        let leader = Regions.gymLeader(of: mva)!
        XCTAssertTrue(leader.isEdgeCase)
        XCTAssertEqual(leader.vanskelighet, mva.filter(\.isEdgeCase).map(\.vanskelighet).max())
        XCTAssertEqual(leader.id, mva.filter { $0.isEdgeCase && $0.vanskelighet == leader.vanskelighet }.map(\.id).min())
        let plain = pool.filter { $0.tema == "kontoplan" }   // no edge cases among the drafts
        XCTAssertEqual(Regions.gymLeader(of: plain)?.vanskelighet, plain.map(\.vanskelighet).max())
        XCTAssertNil(Regions.gymLeader(of: []))
    }

    func testUnlockFollowsCaughtRatioAndSkipsEmptyRegions() {
        let approved = Self.library.pool(includeDrafts: false)   // kontoplan and resultat-balanse are empty here
        var progress = LearnerProgress()
        for p in approved.filter({ $0.tema == "grunnlag" }) { progress.puzzles[p.id] = PuzzleProgress(box: 1, attempts: 1, correct: 1) }
        let regions = Regions.build(topics: topics, pool: approved, progress: progress)
        let byTema = Dictionary(uniqueKeysWithValues: regions.map { ($0.tema, $0) })
        XCTAssertTrue(byTema["kontoplan"]!.isEmpty)
        XCTAssertTrue(byTema["kontoplan"]!.unlocked, "an empty region inherits the status of the one before")
        XCTAssertTrue(byTema["bilag-bokforingsloven"]!.unlocked, "grunnlag fully caught, the two empty regions do not block")
        XCTAssertFalse(byTema["perioder-frister"]!.unlocked, "bilag has one puzzle, not caught")
        XCTAssertEqual(byTema["grunnlag"]!.caughtRatio, 1)
    }

    func testCountsAndDamageTarget() {
        var progress = LearnerProgress()
        let lonn = pool.filter { $0.tema == "lonn" }
        progress.puzzles[lonn[0].id] = PuzzleProgress(box: 3, attempts: 1, correct: 1)
        progress.puzzles[lonn[1].id] = PuzzleProgress(box: 1, attempts: 1, correct: 1)
        let region = Regions.build(topics: topics, pool: pool, progress: progress).first { $0.tema == "lonn" }!
        XCTAssertEqual(region.caught, 2); XCTAssertEqual(region.mastered, 1)
        let leader = region.gymLeader!
        XCTAssertEqual(region.damageTarget, lonn.filter { $0.id != leader.id }.map { $0.vanskelighet * 100 }.reduce(0, +) / 2)
        let single = Region(tema: "x", navn: "x", rekkefolge: 99, theme: Regions.themes["mva"]!, puzzles: [lonn[0]], gymLeader: lonn[0], caught: 0, mastered: 0, unlocked: true, gymBadge: nil)
        XCTAssertEqual(single.damageTarget, 0, "a one-puzzle region's leader is ready at once")
    }
}
