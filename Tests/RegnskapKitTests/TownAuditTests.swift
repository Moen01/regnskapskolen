import XCTest
@testable import RegnskapKit

final class TownAuditTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static let town = library.town
    var pool: [Puzzle] { Self.library.pool(includeDrafts: false) }
    var regions: [Region] { Regions.build(topics: Self.library.topics, pool: pool, progress: LearnerProgress()) }
    var offices: [FagkontorRef] { Self.town.kart.flatMap(\.folk).compactMap(\.fagkontor) }

    func office(_ id: String) -> FagkontorRef { offices.first { $0.id == id }! }
    func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

    func state(today: DayKey) -> TownState {
        var s = TownState.new(content: Self.town, year: 2026)
        s.calendar = TownCalendar(start: today)
        return s
    }

    // MARK: Opening

    func testAuditNeedsEveryReadyBadge() {
        let all = Set(offices.map(TownTrials.badgeKey))
        XCTAssertEqual(offices.count, 8)
        let seven = all.subtracting([TownTrials.badgeKey(offices[0])])
        let partial = TownAudit.badgeCount(content: Self.town, badges: seven, regions: regions)
        XCTAssertEqual(partial.held, 7)
        XCTAssertEqual(partial.needed, 8)
        XCTAssertFalse(TownAudit.ready(content: Self.town, badges: seven, regions: regions))
        XCTAssertTrue(TownAudit.ready(content: Self.town, badges: all, regions: regions))
    }

    func testOfficeUnderConstructionDoesNotBlockTheAudit() {
        let thin = Regions.build(topics: Self.library.topics, pool: pool.filter { $0.tema != "grunnlag" }, progress: LearnerProgress())
        let badges = Set(offices.filter { $0.id != "bilag" }.map(TownTrials.badgeKey))
        XCTAssertFalse(badges.contains("fag-bilag"))
        XCTAssertEqual(TownAudit.badgeCount(content: Self.town, badges: badges, regions: thin).needed, 7)
        XCTAssertTrue(TownAudit.ready(content: Self.town, badges: badges, regions: thin))
    }

    // MARK: Year

    func testAuditYearIsTheYearThatEnded() {
        XCTAssertNil(state(today: day(2026, 12, 31)).auditYear)
        XCTAssertEqual(state(today: day(2027, 1, 1)).auditYear, 2026)
        var done = state(today: day(2027, 1, 1))
        done.revidert = [2026]
        XCTAssertNil(done.auditYear)
        XCTAssertEqual(state(today: day(2028, 3, 1)).auditYear, 2027)
    }

    // MARK: Review

    func testReviewTakesOpenErrorsOfTheAuditedYearOnly() throws {
        var s = state(today: day(2027, 1, 5))
        let ids = Self.town.klienter.map(\.id)
        func error(_ puzzle: String, _ client: String, _ y: Int, _ m: Int) -> OpenError {
            OpenError(puzzleId: puzzle, client: client, month: MonthKey(year: y, month: m), day: day(y, m, 10), boxBefore: 1)
        }
        s.clients[ids[0]] = .fresh(.active)
        s.clients[ids[0]]?.openErrors = [error("mva-quiz-001", ids[0], 2026, 11), error("mva-quiz-002", ids[0], 2027, 1), error("hidden-draft", ids[0], 2026, 11)]
        s.clients[ids[1]] = .fresh(.archived)
        s.clients[ids[1]]?.openErrors = [error("mva-quiz-001", ids[1], 2026, 5)]
        let found = TownAudit.reviewed(s, year: 2026, pool: ["mva-quiz-001", "mva-quiz-002"])
        XCTAssertEqual(found.map(\.puzzleId), ["mva-quiz-001"])
        XCTAssertEqual(found.map(\.client), [ids[0]])
    }

    // MARK: Panel

    func panel(_ pool: [Puzzle]) -> [AuditExaminer] {
        TownAudit.panel(examiners: [office("mva"), office("lonn")], sensor: sensorRef, content: Self.town, pool: pool)
    }

    var sensorRef: FagkontorRef { FagkontorRef(id: "sensor", navn: "Sensor", temaer: ["bilag-bokforingsloven", "kontoplan", "grunnlag", "perioder-frister"]) }

    func testExaminersSkipTheFagkontorPuzzles() throws {
        let mva = try XCTUnwrap(panel(pool).first)
        XCTAssertEqual(mva.ref.id, "mva")
        let office = try XCTUnwrap(TownTrials.fagkontorRegion(office("mva"), pool: pool, progress: LearnerProgress()))
        XCTAssertEqual(mva.puzzles.count, 3)
        XCTAssertTrue(Set(mva.puzzles.map(\.id)).isDisjoint(with: office.puzzles.map(\.id)))
    }

    func testThinTopicFallsBackToTheFagkontorPuzzles() throws {
        let thin = pool.filter { $0.tema != "arsoppgjor" || Set(pool.filter { $0.tema == "arsoppgjor" }.map(\.id).sorted().prefix(4)).contains($0.id) }
            .filter { $0.tema != "resultat-balanse" }
        let ref = FagkontorRef(id: "ars", navn: "Ars", temaer: ["arsoppgjor"])
        let result = TownAudit.panel(examiners: [ref], sensor: sensorRef, content: Self.town, pool: thin)
        let examiner = try XCTUnwrap(result.first { $0.ref.id == "ars" })
        let officeIds = Set(TownTrials.ranked(office("arsoppgjor").temaer, pool: thin).prefix(3).map(\.id))
        XCTAssertEqual(examiner.puzzles.count, 3)
        XCTAssertEqual(examiner.puzzles.filter { officeIds.contains($0.id) }.count, 2)
    }

    func testSensorTakesThreeTopics() throws {
        let result = panel(pool)
        let sensor = try XCTUnwrap(result.last)
        XCTAssertTrue(sensor.isSensor)
        XCTAssertEqual(sensor.puzzles.count, 3)
        XCTAssertEqual(Set(sensor.puzzles.map(\.tema)).count, 3)
        let used = Set(result.dropLast().flatMap(\.puzzles).map(\.id))
        XCTAssertTrue(used.isDisjoint(with: sensor.puzzles.map(\.id)))
    }

    func testPanelHasNoDuplicates() {
        let ids = panel(pool).flatMap(\.puzzles).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids.count, 9)
    }

    func testExaminerWithoutPuzzlesIsLeftOut() {
        let empty = FagkontorRef(id: "tom", navn: "Tom", temaer: ["finnes-ikke"])
        let result = TownAudit.panel(examiners: [empty], sensor: sensorRef, content: Self.town, pool: pool)
        XCTAssertEqual(result.map(\.ref.id), ["sensor"])
    }

    // MARK: Pass and fail

    func testPassStartsTheNewYear() {
        var s = state(today: day(2027, 1, 5))
        s.sandboxCleared = ["kafe-001"]
        s.energy = 10
        s.coffee = 2
        s.coffeeTakenOn = day(2027, 1, 4)
        s.fullmakter = ["havna"]
        s.regelkort = ["r1"]
        s.found = ["f1"]
        s.contracts = 4
        let before = s
        s.passAudit(year: 2026)
        XCTAssertEqual(s.revidert, [2026])
        XCTAssertEqual(s.auditTriedOn, day(2027, 1, 5))
        XCTAssertEqual(s.sandboxCleared, [])
        XCTAssertEqual(s.energy, 100)
        XCTAssertNil(s.coffeeTakenOn)
        XCTAssertEqual(s.coffee, before.coffee)
        XCTAssertEqual(s.clients, before.clients)
        XCTAssertEqual(s.fullmakter, before.fullmakter)
        XCTAssertEqual(s.regelkort, before.regelkort)
        XCTAssertEqual(s.found, before.found)
        XCTAssertEqual(s.contracts, before.contracts)
    }

    func testFailSendsThePlayerToTheOffice() {
        var s = state(today: day(2027, 1, 5))
        s.mapId = "havna"
        s.walker = TownWalker(x: 1, y: 1, facing: .down)
        let id = Self.town.klienter[0].id
        s.clients[id]?.openErrors = [OpenError(puzzleId: "p", client: id, month: MonthKey(year: 2026, month: 5), day: day(2026, 5, 3), boxBefore: 0)]
        let before = s.clients
        s.failAudit(content: Self.town)
        let spot = TownState.officeSpot(Self.town)
        XCTAssertEqual(s.mapId, "kontoret")
        XCTAssertEqual(s.walker, spot.walker)
        XCTAssertEqual(s.auditTriedOn, day(2027, 1, 5))
        XCTAssertEqual(s.clients, before)
    }

    func testBeginAuditMarksTheAttempt() {
        var s = state(today: day(2027, 1, 5))
        s.beginAudit()
        XCTAssertEqual(s.auditTriedOn, day(2027, 1, 5))
    }

    func testSaveFrom2cOpensIn2d() throws {
        var s = state(today: day(2027, 1, 4))
        s.sandboxCleared = ["kafe-001"]
        let data = try JSONEncoder().encode(s)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["revidert", "auditTriedOn", "annualFrom"] { json[key] = nil }
        let old = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.revidert, [])
        XCTAssertNil(old.auditTriedOn)
        XCTAssertEqual(old.annualFrom, day(2027, 1, 4))
        XCTAssertEqual(old.sandboxCleared, ["kafe-001"])
        XCTAssertEqual(old.auditYear, 2026)
    }

    func testNewFieldsRoundTrip() throws {
        var s = state(today: day(2027, 1, 4))
        s.passAudit(year: 2026)
        XCTAssertEqual(try JSONDecoder().decode(TownState.self, from: JSONEncoder().encode(s)), s)
    }

    func testAuditPassedGivesTheBadgeOnce() {
        var progress = LearnerProgress()
        XCTAssertEqual(Badges.award(.auditPassed, on: day(2027, 1, 5), progress: &progress).map(\.id), ["revisorens-beste-venn"])
        XCTAssertEqual(Badges.award(.auditPassed, on: day(2028, 1, 5), progress: &progress), [])
    }
}
