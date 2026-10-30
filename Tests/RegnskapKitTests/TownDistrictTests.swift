import XCTest
@testable import RegnskapKit

final class TownDistrictTests: XCTestCase {
    static let town = TownFlowTests.town
    static let library = TownFlowTests.library
    static let regions = TownFlowTests.regions
    let day = DayKey(year: 2026, month: 4, day: 12)

    func state(map: String = "sentrum", x: Int, y: Int, facing: Facing, fullmakter: Set<String> = []) -> TownState {
        var s = TownState.new(content: Self.town, year: 2026)
        s.mapId = map
        s.walker = TownWalker(x: x, y: y, facing: facing)
        s.fullmakter = fullmakter
        return s
    }

    func flow(_ state: TownState) -> TownFlow {
        TownFlow(content: Self.town, state: state, deadlines: Self.library.deadlines, pool: TownFlowTests.pool, regions: Self.regions,
                 damage: [:], badges: [], ruleCards: Self.library.rules)
    }

    /// The regions with one topic cut to two puzzles: an office on that topic is still under construction.
    func regions(thin tema: String) -> [Region] {
        Self.regions.map { r in
            guard r.tema == tema else { return r }
            return Region(tema: r.tema, navn: r.navn, rekkefolge: r.rekkefolge, theme: r.theme, puzzles: Array(r.puzzles.prefix(2)),
                          gymLeader: nil, caught: 0, mastered: 0, unlocked: true, gymBadge: nil)
        }
    }

    // MARK: Districts

    func testDistrictsAreSortedByRekkefolge() {
        let districts = TownDistricts.all(in: Self.town)
        XCTAssertEqual(districts.map(\.id), ["sentrum", "havna"])
        XCTAssertEqual(districts.map(\.rekkefolge), [1, 2])
        XCTAssertEqual(districts[0].ankomst, TownSpot(x: 4, y: 3))
        XCTAssertNil(districts[0].fullmakt)
        XCTAssertEqual(districts[1].fullmakt, "havna")
        XCTAssertEqual(districts[0].navn, "Sentrum")
        // The offices of a district sit on every map that belongs to it, interiors included.
        XCTAssertEqual(Set(districts[0].offices.map(\.id)), ["mva", "lonn"])
        XCTAssertTrue(districts[1].offices.isEmpty)
    }

    func testInteriorBelongsToItsDistrict() {
        XCTAssertEqual(TownDistricts.district(of: "kontoret", in: Self.town)?.id, "sentrum")
        XCTAssertEqual(TownDistricts.district(of: "havna", in: Self.town)?.id, "havna")
        XCTAssertNil(TownDistricts.district(of: "finnes-ikke", in: Self.town))
    }

    func testMapWithoutBydelIsOpen() throws {
        let json = #"{"id":"fra-2b","navn":"Fra 2b","bredde":1,"hoyde":1,"ruter":["."],"dorer":[],"folk":[]}"#
        let old = try JSONDecoder().decode(TownMap.self, from: Data(json.utf8))
        XCTAssertNil(old.bydel)
        XCTAssertNil(old.rekkefolge)
        XCTAssertNil(old.ankomst)
        var town = Self.town
        town.kart.append(old)
        XCTAssertTrue(TownDistricts.isOpen("fra-2b", content: town, fullmakter: []))
        XCTAssertTrue(TownDistricts.isOpen("sentrum", content: town, fullmakter: []))
        XCTAssertTrue(TownDistricts.isOpen("kontoret", content: town, fullmakter: []))
        XCTAssertFalse(TownDistricts.isOpen("havna", content: town, fullmakter: []))
        XCTAssertTrue(TownDistricts.isOpen("havna", content: town, fullmakter: ["havna"]))
    }

    // MARK: Gate

    func testLockedGateStepsBack() {
        // (7, 4) is the square in front of the gate in the outer wall; the gate is at (7, 5).
        var f = flow(state(x: 7, y: 4, facing: .down))
        XCTAssertEqual(f.key(.down), .none)
        XCTAssertEqual(f.state.mapId, "sentrum")
        XCTAssertEqual(f.state.walker.x, 7)
        XCTAssertEqual(f.state.walker.y, 4)
        XCTAssertEqual(f.phase, .dialog)
        let said = f.pages.flatMap { $0 }.joined(separator: " ")
        XCTAssertTrue(said.contains("Veien er stengt."), said)
        XCTAssertTrue(said.contains("Du trenger fullmakt til Havna."), said)
    }

    func testOpenGateEnters() {
        var f = flow(state(x: 7, y: 4, facing: .down, fullmakter: ["havna"]))
        XCTAssertEqual(f.key(.down), .enteredDoor)
        XCTAssertEqual(f.state.mapId, "havna")
        XCTAssertEqual(f.state.walker.x, 4)
        XCTAssertEqual(f.state.walker.y, 6)
        XCTAssertEqual(f.phase, .walking)
    }

    // MARK: Fullmakt

    func testFullmaktNeedsEveryReadyOfficeOfThePreviousDistrict() {
        XCTAssertEqual(TownDistricts.earned(content: Self.town, badges: [], regions: Self.regions), [])
        XCTAssertEqual(TownDistricts.earned(content: Self.town, badges: ["fag-mva"], regions: Self.regions), [])
        XCTAssertEqual(TownDistricts.earned(content: Self.town, badges: ["fag-mva", "fag-lonn"], regions: Self.regions), ["havna"])
    }

    func testOfficeUnderConstructionIsNotRequired() {
        let thin = regions(thin: "lonn")
        XCTAssertFalse(TownTrials.fagkontorReady(FagkontorRef(id: "lonn", navn: "G", temaer: ["lonn"]), regions: thin))
        XCTAssertEqual(TownDistricts.earned(content: Self.town, badges: ["fag-mva"], regions: thin), ["havna"])
        // With no office ready at all, the gate is open from the start.
        let none = regions(thin: "lonn").map { r in
            r.tema == "mva" ? Region(tema: r.tema, navn: r.navn, rekkefolge: r.rekkefolge, theme: r.theme, puzzles: [], gymLeader: nil,
                                     caught: 0, mastered: 0, unlocked: true, gymBadge: nil) : r
        }
        XCTAssertEqual(TownDistricts.earned(content: Self.town, badges: [], regions: none), ["havna"])
    }

    func testGrantIsOnceAndNeverTakenBack() {
        var s = state(x: 4, y: 3, facing: .down)
        let both: Set<String> = ["fag-mva", "fag-lonn"]
        XCTAssertEqual(s.grantFullmakter(content: Self.town, badges: both, regions: Self.regions).map(\.id), ["havna"])
        XCTAssertEqual(s.fullmakter, ["havna"])
        XCTAssertEqual(s.grantFullmakter(content: Self.town, badges: both, regions: Self.regions), [])
        XCTAssertEqual(s.grantFullmakter(content: Self.town, badges: [], regions: Self.regions), [])
        XCTAssertEqual(s.fullmakter, ["havna"])
    }

    func testFullmakterSurviveTheSave() throws {
        let s = state(x: 4, y: 3, facing: .down, fullmakter: ["havna"])
        let back = try JSONDecoder().decode(TownState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.fullmakter, ["havna"])
        XCTAssertEqual(back, s)
    }

    func testSaveFrom2bOpensIn2c() throws {
        // Start from a real encoding, then strip the keys that 2b did not write.
        let sample = TownState.new(content: Self.town, year: 2026)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as! [String: Any]
        for key in ["fullmakter", "regelkort", "energy", "coffee", "coffeeTakenOn", "payrollFrom"] { object[key] = nil }
        object["mapId"] = "havna"
        object["clients"] = [String: Any]()
        object["contracts"] = 3
        var calendar = object["calendar"] as! [String: Any]
        calendar["today"] = "2026-04-12"
        object["calendar"] = calendar
        var s = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(s.fullmakter, [])
        XCTAssertEqual(s.contracts, 3)
        XCTAssertEqual(s.calendar.today, day)
        XCTAssertTrue(s.relocateIfLocked(content: Self.town))
        XCTAssertEqual(s.mapId, "kontoret")
        XCTAssertFalse(s.relocateIfLocked(content: Self.town))
        XCTAssertEqual(s.grantFullmakter(content: Self.town, badges: ["fag-mva"], regions: Self.regions), [])
        XCTAssertEqual(s.checkMissed(content: Self.town, deadlines: Self.library.deadlines), [])
    }

    // MARK: Fast travel

    func openTravel(_ f: inout TownFlow) {
        _ = f.openFristnav()
        let kart = f.rows.firstIndex { $0.id == "kart" } ?? 0
        for _ in 0..<kart { _ = f.key(.down) }
        _ = f.key(.a)
    }

    func testFristnavEndsWithKart() {
        var f = flow(state(x: 4, y: 3, facing: .down))
        _ = f.openFristnav()
        XCTAssertEqual(f.rows.last, PanelRow(id: "kart", text: "KART", full: "Reis til en bydel"))
    }

    func testTravelListsOnlyOpenDistricts() {
        var f = flow(state(x: 4, y: 3, facing: .down))
        openTravel(&f)
        XCTAssertEqual(f.phase, .travel)
        XCTAssertEqual(f.rows.map(\.text), ["SENTRUM"])
        var g = flow(state(x: 4, y: 3, facing: .down, fullmakter: ["havna"]))
        openTravel(&g)
        XCTAssertEqual(g.rows.map(\.text), ["SENTRUM", "HAVNA"])
        XCTAssertEqual(g.rows.map(\.marked), [true, false], "the district the player stands in is marked")
    }

    func testTravelPutsPlayerOnArrival() throws {
        var f = flow(state(x: 4, y: 3, facing: .left, fullmakter: ["havna"]))
        openTravel(&f)
        _ = f.key(.down)
        XCTAssertEqual(f.key(.a), .enteredDoor)
        let havna = try XCTUnwrap(TownDistricts.all(in: Self.town).first { $0.id == "havna" })
        XCTAssertEqual(f.state.mapId, "havna")
        XCTAssertEqual(f.state.walker, TownWalker(x: havna.ankomst.x, y: havna.ankomst.y, facing: .down))
        XCTAssertEqual(f.phase, .walking)
        XCTAssertFalse(TownAction.enteredDoor.spendsAction)
    }

    func testTravelToTheSameDistrictOnlyCloses() {
        var f = flow(state(x: 4, y: 3, facing: .left, fullmakter: ["havna"]))
        openTravel(&f)
        XCTAssertEqual(f.key(.a), .none)
        XCTAssertEqual(f.state.mapId, "sentrum")
        XCTAssertEqual(f.state.walker, TownWalker(x: 4, y: 3, facing: .left))
        XCTAssertEqual(f.phase, .walking)
    }

    func testTravelLinesFitTheBox() {
        var f = flow(state(x: 4, y: 3, facing: .down, fullmakter: ["havna"]))
        openTravel(&f)
        XCTAssertTrue(f.rows.allSatisfy { $0.text.count <= TownFlow.rowColumns })
        for pageIndex in f.pages.indices {
            XCTAssertLessThanOrEqual(f.pages[pageIndex].count, 6)
            XCTAssertTrue(f.pages[pageIndex].allSatisfy { $0.count <= 36 })
        }
    }
}
