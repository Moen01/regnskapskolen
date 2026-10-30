import XCTest
@testable import RegnskapKit

final class TownEnergyTests: XCTestCase {
    static let library = TownFlowTests.library
    static let town = TownFlowTests.town

    func day(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }

    private let machine = TownPerson(id: "kaffe", rolle: .kaffe, x: 2, y: 1, klient: nil, fagkontor: nil, tekst: [])

    private func flow(_ state: TownState) -> TownFlow {
        TownFlow(content: Self.town, state: state, deadlines: Self.library.deadlines, pool: TownFlowTests.pool,
                 regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
    }

    func testTwentyEncountersEmptyTheEnergy() {
        var s = TownState.new(content: Self.town, year: 2026)
        XCTAssertEqual(s.energy, TownRules.maxEnergy)
        for i in 1...20 {
            let empty = s.spendEncounter()
            XCTAssertEqual(empty, i == 20, "encounter \(i)")
        }
        XCTAssertEqual(s.energy, 0)
        XCTAssertTrue(s.spendEncounter(), "never below zero")
        XCTAssertEqual(s.energy, 0)
    }

    func testWrongAndRightCostTheSame() {
        // The cost has no input for the verdict: one call, one price.
        var s = TownState.new(content: Self.town, year: 2026)
        _ = s.spendEncounter()
        XCTAssertEqual(s.energy, TownRules.maxEnergy - TownRules.energyPerEncounter)
    }

    func testCollapseWakesAtTheOfficeNextMorningWithFullEnergy() {
        var s = TownState.new(content: Self.town, year: 2026)
        let home = s.walker
        s.mapId = "butikken"
        s.walker = TownWalker(x: 1, y: 1, facing: .left)
        s.calendar = TownCalendar(start: day(1, 5))
        s.energy = 0
        _ = s.collapse(content: Self.town, deadlines: Self.library.deadlines, pool: [])
        XCTAssertEqual(s.mapId, "kontoret")
        XCTAssertEqual(s.walker, home)
        XCTAssertEqual(s.calendar.today, day(1, 6), "tomorrow, not the next event")
        XCTAssertEqual(s.calendar.actionsToday, 0)
        XCTAssertEqual(s.energy, TownRules.maxEnergy)
    }

    func testCollapseRegistersAMissedDeadlineOnce() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.clients["kafeen"]!.status = .active
        s.calendar = TownCalendar(start: day(1, 21))
        let missed = s.collapse(content: Self.town, deadlines: Self.library.deadlines, pool: [])
        XCTAssertEqual(missed.filter { $0.client == "kafeen" }.map(\.kind.id), ["trekk-2026-01"])
        XCTAssertEqual(s.clients["kafeen"]!.missed, ["trekk-2026-01"])
        XCTAssertEqual(s.checkMissed(content: Self.town, deadlines: Self.library.deadlines), [])
    }

    func testBedFillsEnergy() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.energy = 10
        _ = s.sleep(content: Self.town, deadlines: Self.library.deadlines, pool: [])
        XCTAssertEqual(s.energy, TownRules.maxEnergy)
    }

    func testOneCoffeePerDay() {
        var f = flow(TownState.new(content: Self.town, year: 2026))
        _ = f.talk(to: machine)
        XCTAssertEqual(f.state.coffee, 1)
        XCTAssertEqual(f.state.coffeeTakenOn, day(1, 1))
        XCTAssertEqual(f.pages.flatMap { $0 }.joined(separator: " "), "Du tar en kaffe med deg.")
        _ = f.key(.a)
        _ = f.talk(to: machine)
        XCTAssertEqual(f.state.coffee, 1)
        XCTAssertEqual(f.pages.flatMap { $0 }.joined(separator: " "), "Kannen er tom til i morgen.")
        _ = f.key(.a)
        _ = f.state.sleep(content: Self.town, deadlines: Self.library.deadlines, pool: [])
        _ = f.talk(to: machine)
        XCTAssertEqual(f.state.coffee, 2, "a new day, a new cup")
    }

    func testDrinkingCoffeeGivesThirtyNotAboveHundred() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.coffee = 2
        s.energy = 50
        var f = flow(s)
        f.openBag()
        XCTAssertEqual(f.phase, .bag)
        _ = f.key(.a)
        XCTAssertEqual(f.state.energy, 50 + TownRules.coffeeEnergy)
        XCTAssertEqual(f.state.coffee, 1)
        XCTAssertEqual(f.rows.first?.text, "KAFFE x1")
        _ = f.key(.a)
        XCTAssertEqual(f.state.energy, TownRules.maxEnergy, "capped at the maximum")
        XCTAssertEqual(f.state.coffee, 0)
        _ = f.key(.a)
        XCTAssertEqual(f.state.energy, TownRules.maxEnergy)
        XCTAssertEqual(f.state.coffee, 0)
    }

    func testBagListsCoffeeAndContracts() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.coffee = 3
        s.contracts = 2
        var f = flow(s)
        f.openBag()
        XCTAssertEqual(f.phase, .bag)
        XCTAssertEqual(f.rows.map(\.text), ["KAFFE x3", "AVTALER x2"])
        XCTAssertEqual(TownFlow.mainMenu, ["FRISTNAV", "PORTEFØLJE", "BAG", "SAMLING", "TRENING", "LAGRE"])
    }

    func testOldSaveHasFullEnergy() throws {
        var s = TownState.new(content: Self.town, year: 2026)
        s.energy = 5
        s.coffee = 2
        s.coffeeTakenOn = day(1, 1)
        let back = try JSONDecoder().decode(TownState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.energy, 5)
        XCTAssertEqual(back.coffee, 2)
        XCTAssertEqual(back.coffeeTakenOn, day(1, 1))

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        for key in ["energy", "coffee", "coffeeTakenOn"] { object[key] = nil }
        let old = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.energy, TownRules.maxEnergy)
        XCTAssertEqual(old.coffee, 0)
        XCTAssertNil(old.coffeeTakenOn)
    }
}
