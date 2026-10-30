import XCTest
@testable import RegnskapKit

final class TownAuditFlowTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)
    static let town = library.town
    var pool: [Puzzle] { Self.library.pool(includeDrafts: false) }
    var offices: [FagkontorRef] { Self.town.kart.flatMap(\.folk).compactMap(\.fagkontor) }

    func ref(_ id: String, _ temaer: [String]) -> FagkontorRef { FagkontorRef(id: id, navn: id, temaer: temaer) }

    var desk: TownPerson {
        let examiners = [ref("k1", ["grunnlag", "kontoplan"]), ref("k2", ["mva"]), ref("k3", ["lonn", "periodisering"]), ref("k4", ["arsoppgjor", "avskrivning"])]
        return TownPerson(id: "avgift", rolle: .bokettersyn, x: 1, y: 1, klient: nil, fagkontor: nil, tekst: ["Velkommen til Avgiftskontoret."],
                          kontrollorer: examiners, sensor: ref("sensor", ["resultat-balanse", "reskontro-bank", "valuta-korrigeringer"]))
    }

    func flow(today: DayKey, badges: Set<String>? = nil, pool puzzles: [Puzzle]? = nil, edit: (inout TownState) -> Void = { _ in }) -> TownFlow {
        var s = TownState.new(content: Self.town, year: 2026)
        s.calendar = TownCalendar(start: today)
        edit(&s)
        let regions = Regions.build(topics: Self.library.topics, pool: puzzles ?? pool, progress: LearnerProgress())
        return TownFlow(content: Self.town, state: s, deadlines: Self.library.deadlines, pool: Set(pool.map(\.id)), regions: regions,
                        damage: [:], badges: badges ?? Set(offices.map(TownTrials.badgeKey)), ruleCards: Self.library.rules)
    }

    func text(_ f: TownFlow) -> String { f.pages.map { $0.joined(separator: " ") }.joined(separator: " ") }

    func readDialog(_ f: inout TownFlow) -> TownAction {
        var action = TownAction.none
        var count = 0
        while f.phase == .dialog, count < 50 { action = f.key(.a); count += 1 }
        return action
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> DayKey { DayKey(year: y, month: m, day: d) }

    func testDeskWithoutAllBadgesShowsTheCount() {
        let seven = Set(offices.dropFirst().map(TownTrials.badgeKey))
        var f = flow(today: day(2027, 1, 4), badges: seven)
        XCTAssertEqual(f.talk(to: desk), .none)
        XCTAssertTrue(text(f).contains("Kom tilbake med alle fagmerkene."))
        XCTAssertTrue(text(f).contains("MERKER 7/8"))
    }

    func testDeskUnderConstructionWhenThePanelHasTooFewPuzzles() {
        var f = flow(today: day(2027, 1, 4), pool: [])
        _ = f.talk(to: desk)
        // No puzzles means no ready office, so the badges are all there; the panel is empty.
        XCTAssertTrue(text(f).contains("Avgiftskontoret er under bygging."))
    }

    func testDeskBeforeTheYearEndsTellsTheDate() {
        var f = flow(today: day(2026, 9, 15))
        _ = f.talk(to: desk)
        XCTAssertTrue(text(f).contains("Bokettersynet for 2026 starter 1. januar 2027."), text(f))
        XCTAssertEqual(readDialog(&f), .none)
        XCTAssertEqual(f.phase, .walking)
    }

    func testDeskOffersTheAuditInJanuary() {
        var f = flow(today: day(2027, 1, 4))
        _ = f.talk(to: desk)
        XCTAssertTrue(text(f).contains("Bokettersynet for 2026 gjelder alle klientene dine."), text(f))
        _ = readDialog(&f)
        XCTAssertEqual(f.phase, .choice)
        XCTAssertTrue(text(f).contains("Starte bokettersynet?"))
        XCTAssertEqual(f.key(.a), .startAudit(year: 2026))
        XCTAssertEqual(f.phase, .walking)
    }

    func testDeskAfterATryToday() {
        var f = flow(today: day(2027, 1, 4)) { $0.auditTriedOn = $0.calendar.today }
        _ = f.talk(to: desk)
        XCTAssertEqual(f.pages, [["Vi fortsetter i morgen."]])
    }

    func testDeskAfterAPassTellsTheNextAudit() {
        var f = flow(today: day(2027, 2, 10)) { $0.revidert = [2026] }
        _ = f.talk(to: desk)
        XCTAssertTrue(text(f).contains("Bokettersynet for 2026 er avsluttet uten merknader."))
        XCTAssertTrue(text(f).contains("Neste bokettersyn er 1. januar 2028."), text(f))
    }

    func testStartAuditSpendsAnAction() {
        XCTAssertTrue(TownAction.startAudit(year: 2026).spendsAction)
    }

    func testDeskLinesFitTheBox() {
        var flows = [
            flow(today: day(2027, 1, 4), badges: []),
            flow(today: day(2027, 1, 4), pool: []),
            flow(today: day(2026, 9, 15)),
            flow(today: day(2027, 1, 4)),
            flow(today: day(2027, 1, 4)) { $0.auditTriedOn = $0.calendar.today },
            flow(today: day(2027, 2, 10)) { $0.revidert = [2026] },
        ]
        for i in flows.indices {
            _ = flows[i].talk(to: desk)
            XCTAssertFalse(flows[i].pages.isEmpty)
            for page in flows[i].pages {
                XCTAssertLessThanOrEqual(page.count, 4, "\(page)")
                XCTAssertTrue(page.allSatisfy { $0.count <= 36 }, "\(page)")
            }
        }
    }

    func testBokettersynSpriteIsSixteenBySixteen() {
        for facing in [Facing.up, .down, .left, .right] {
            let sprite = TileSprite.person(.bokettersyn, facing: facing)
            XCTAssertEqual(sprite.width, 16)
            XCTAssertEqual(sprite.height, 16)
        }
        // Glasses like the fagkontor and a tie like the sjef.
        let front = TileSprite.person(.bokettersyn, facing: .down)
        XCTAssertNotEqual(front, TileSprite.person(.folk, facing: .down))
        XCTAssertNotEqual(front, TileSprite.person(.fagkontor, facing: .down))
        XCTAssertNotEqual(front, TileSprite.person(.sjef, facing: .down))
    }
}
