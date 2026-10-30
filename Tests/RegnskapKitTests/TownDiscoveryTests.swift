import XCTest
@testable import RegnskapKit

final class TownDiscoveryTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static let town = try! TownContent.load(folder: TownContentTests.fixtureTown)
    let pool: Set<String> = ["mva-quiz-001", "grunnlag-quiz-010"]
    let jan = MonthKey(year: 2026, month: 1)

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    /// The roll the rule describes; the tests pick days from it so they cannot pass by luck.
    func rolls(_ error: OpenError, on day: DayKey) -> Bool {
        var generator = SplitMix64(seed: SpeciesName.fnv1a("\(error.id)|\(day.string)"))
        return generator.next() % TownRules.discoverOneIn == 0
    }

    func error(_ puzzle: String = "mva-quiz-001", on day: DayKey) -> OpenError {
        OpenError(puzzleId: puzzle, client: "kafeen", month: MonthKey(day), day: day, boxBefore: 0)
    }

    func state(errors: [OpenError], today: DayKey) -> TownState {
        var s = TownState.new(content: Self.town, year: 2026)
        s.calendar = TownCalendar(start: today)
        s.clients["kafeen"]!.status = .active
        s.clients["kafeen"]!.openErrors = errors
        return s
    }

    func discover(_ s: inout TownState, on day: DayKey, pool: Set<String>? = nil) -> [OpenError] {
        s.discover(day: day, content: Self.town, pool: pool ?? self.pool).map(\.error)
    }

    /// A booking day whose error is rolled to be found `after` days later.
    func errorFoundAfter(_ after: Int, puzzle: String = "mva-quiz-001") -> OpenError {
        for offset in 0..<200 {
            let e = error(puzzle, on: day(1, 1).adding(days: offset))
            if rolls(e, on: e.day.adding(days: after)) { return e }
        }
        fatalError("no day rolls a hit")
    }

    func testSameDaySameErrorSameResult() {
        let e = errorFoundAfter(9)
        let today = e.day.adding(days: 9)
        var a = state(errors: [e], today: today)
        var b = state(errors: [e], today: today)
        let first = discover(&a, on: today)
        XCTAssertEqual(first.map(\.id), [e.id])
        XCTAssertTrue(first[0].discovered)
        XCTAssertEqual(discover(&b, on: today), first)
        XCTAssertEqual(a, b)
        // A day the roll misses finds nothing.
        let miss = (7..<80).first { !rolls(e, on: e.day.adding(days: $0)) }!
        var c = state(errors: [e], today: today)
        XCTAssertEqual(discover(&c, on: e.day.adding(days: miss)), [])
    }

    func testOnlyErrorsOlderThanSevenDays() {
        let e = errorFoundAfter(3)
        var s = state(errors: [e], today: e.day.adding(days: 3))
        XCTAssertEqual(discover(&s, on: e.day.adding(days: 3)), [], "rolls a hit, but the error is too young")
        XCTAssertFalse(s.clients["kafeen"]!.openErrors[0].discovered)
        let later = (7..<80).filter { rolls(e, on: e.day.adding(days: $0)) }.first
        XCTAssertNotNil(later)
        XCTAssertEqual(discover(&s, on: e.day.adding(days: later!)).map(\.id), [e.id])
        XCTAssertEqual(TownRules.discoverAfterDays, 7)
        XCTAssertEqual(discover(&s, on: e.day.adding(days: later!)), [], "found once")
    }

    func testHiddenDraftIsNeverDiscovered() {
        let e = errorFoundAfter(8, puzzle: "grunnlag-quiz-010")
        var s = state(errors: [e], today: e.day.adding(days: 8))
        for offset in 7..<120 {
            XCTAssertEqual(discover(&s, on: e.day.adding(days: offset), pool: ["mva-quiz-001"]), [])
        }
        XCTAssertFalse(s.clients["kafeen"]!.openErrors[0].discovered)
        XCTAssertEqual(discover(&s, on: e.day.adding(days: 8)).map(\.id), [e.id], "visible again: found")
    }

    func testDiscoveryCostsFifteen() {
        let e = errorFoundAfter(9)
        var s = state(errors: [e], today: e.day.adding(days: 9))
        let before = s.clients["kafeen"]!.satisfaction
        _ = discover(&s, on: e.day.adding(days: 9))
        XCTAssertEqual(s.clients["kafeen"]!.satisfaction, before + TownRules.discoveredPenalty)
        XCTAssertEqual(TownRules.discoveredPenalty, -15)

        var low = state(errors: [e], today: e.day.adding(days: 9))
        low.clients["kafeen"]!.satisfaction = 10
        _ = discover(&low, on: e.day.adding(days: 9))
        XCTAssertEqual(low.clients["kafeen"]!.satisfaction, 0)
        XCTAssertEqual(low.clients["kafeen"]!.status, .archived)
    }

    func testDiscoveredErrorStillBlocksTheClose() {
        var e = error(on: day(1, 10))
        e.discovered = true
        var s = state(errors: [e], today: day(2, 5))
        s.clients["kafeen"]!.closeIfClean(jan, pool: pool)
        XCTAssertFalse(s.clients["kafeen"]!.closedMonths.contains(jan))
        s.clients["kafeen"]!.correct(e, ok: true)
        s.clients["kafeen"]!.closeIfClean(jan, pool: pool)
        XCTAssertTrue(s.clients["kafeen"]!.closedMonths.contains(jan))
    }

    func testSpendActionAndSleepFindErrorsAndTellThem() {
        let e = errorFoundAfter(9)
        let today = e.day.adding(days: 9)
        var s = state(errors: [e], today: today)
        for _ in 0..<TownRules.actionsPerDay { _ = s.spendAction(content: Self.town, deadlines: Self.library.deadlines, pool: pool) }
        let tomorrow = today.adding(days: 1)
        XCTAssertEqual(s.calendar.today, tomorrow)
        let expected = rolls(e, on: tomorrow)
        XCTAssertEqual(s.clients["kafeen"]!.openErrors[0].discovered, expected)
        XCTAssertEqual(s.takeDiscoveries().count, expected ? 1 : 0)
        XCTAssertEqual(s.takeDiscoveries(), [], "taken once")

        // A sleep over several days rolls every one of them.
        var sleeper = state(errors: [e], today: e.day.adding(days: 7))
        while sleeper.calendar.today < e.day.adding(days: 60), !sleeper.clients["kafeen"]!.openErrors[0].discovered {
            _ = sleeper.sleep(content: Self.town, deadlines: Self.library.deadlines, pool: pool)
        }
        XCTAssertTrue(sleeper.clients["kafeen"]!.openErrors[0].discovered)
        XCTAssertEqual(sleeper.takeDiscoveries().map(\.id), [e.id])
    }

    func counterRows(_ s: TownState) -> [String] {
        var f = TownFlow(content: Self.town, state: s, deadlines: Self.library.deadlines, pool: pool, regions: [], damage: [:], ruleCards: Self.library.rules)
        _ = f.key(.a)
        return f.phase == .counter ? f.rows.map(\.text).filter { $0.hasPrefix("KAFÉ") } : []
    }

    func testCounterOffersFixDiscoveredFirst() {
        var e = error(on: day(1, 10))
        e.discovered = true
        var s = state(errors: [e], today: day(2, 5))
        s.mapId = "kontoret"
        s.walker = TownWalker(x: 1, y: 3, facing: .up)
        let rows = counterRows(s)
        XCTAssertEqual(rows.first, "KAFÉ RETT FEIL", "\(rows)")

        var hidden = s
        var hiddenError = error("grunnlag-quiz-010", on: e.day)
        hiddenError.discovered = true
        hidden.clients["kafeen"]!.openErrors = [hiddenError]
        let visible: Set<String> = ["mva-quiz-001"]
        var f = TownFlow(content: Self.town, state: hidden, deadlines: Self.library.deadlines, pool: visible, regions: [], damage: [:], ruleCards: Self.library.rules)
        _ = f.key(.a)
        XCTAssertFalse(f.rows.map(\.text).contains("KAFÉ RETT FEIL"))

        var undiscovered = s
        undiscovered.clients["kafeen"]!.openErrors[0].discovered = false
        XCTAssertFalse(counterRows(undiscovered).contains("KAFÉ RETT FEIL"))

        var g = TownFlow(content: Self.town, state: s, deadlines: Self.library.deadlines, pool: pool, regions: [], damage: [:], ruleCards: Self.library.rules)
        _ = g.key(.a)
        XCTAssertEqual(g.key(.a), .fixDiscovered(client: "kafeen"))
    }

    func testDiscoveryTextsNameTheClientAndTitleAndWrapAtEighteenColumns() {
        let e = error(on: day(1, 3))
        let long = "En tittel med et ordsomeraltforlangtforenlinje"
        let texts = TownFlow.discoveryTexts([e], content: Self.town, title: { $0 == e.puzzleId ? long : nil })
        let client = Self.town.client("kafeen")!
        XCTAssertEqual(texts, ["\(client.navn): \(long)"] + client.replikker.oppdagetFeil)
        let lines = TownFlow.paged(texts).flatMap { $0 }
        XCTAssertTrue(lines.allSatisfy { $0.count <= TownFlow.columns }, "\(lines)")
        // No title known: the id stands in, so the line is never empty.
        XCTAssertEqual(TownFlow.discoveryTexts([e], content: Self.town, title: { _ in nil }).first, "\(client.navn): \(e.puzzleId)")
    }

    func testCollapseTextsTellTheDayOfWaking() {
        let texts = TownFlow.collapseTexts(wokeOn: day(4, 11))
        XCTAssertEqual(texts, ["Du sovnet av utmattelse.", "Du våknet på kontoret 11.04."])
        XCTAssertTrue(TownFlow.paged(texts).flatMap { $0 }.allSatisfy { $0.count <= TownFlow.columns })
    }

    func testFixDiscoveredCostsAnAction() {
        XCTAssertTrue(TownAction.fixDiscovered(client: "kafeen").spendsAction)
    }

    func testOldSaveErrorsAreNotDiscovered() throws {
        // An error as phase 2a wrote it: encode a current one and drop the new key.
        var current = try JSONSerialization.jsonObject(with: JSONEncoder().encode(error(on: day(1, 3)))) as! [String: Any]
        XCTAssertNotNil(current.removeValue(forKey: "discovered"))
        let json = String(decoding: try JSONSerialization.data(withJSONObject: current), as: UTF8.self)
        let e = try JSONDecoder().decode(OpenError.self, from: Data(json.utf8))
        XCTAssertFalse(e.discovered)
        var found = e
        found.discovered = true
        XCTAssertTrue(try JSONDecoder().decode(OpenError.self, from: JSONEncoder().encode(found)).discovered)
    }
}
