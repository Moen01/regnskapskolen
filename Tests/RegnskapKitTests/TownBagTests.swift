import XCTest
@testable import RegnskapKit

final class TownBagTests: XCTestCase {
    static let library = TownFlowTests.library
    static let town = TownFlowTests.town

    private var card: RuleCard { Self.library.rules[0] }
    private var other: RuleCard { Self.library.rules[1] }

    private func flow(_ state: TownState? = nil) -> TownFlow {
        TownFlow(content: Self.town, state: state ?? TownState.new(content: Self.town, year: 2026), deadlines: Self.library.deadlines,
                 pool: TownFlowTests.pool, regions: TownFlowTests.regions, damage: [:], badges: [], ruleCards: Self.library.rules)
    }

    private func pile(gives id: String?) -> TownPerson {
        TownPerson(id: "funn-1", rolle: .funn, x: 1, y: 1, klient: nil, fagkontor: nil, tekst: [], gir: id)
    }

    private func text(_ f: TownFlow) -> String { f.pages.flatMap { $0 }.joined(separator: " ") }

    func testFindingACardOnce() {
        var f = flow()
        _ = f.talk(to: pile(gives: card.id))
        XCTAssertEqual(f.pages.flatMap { $0 }.first, "Du fant et regelkort!")
        XCTAssertTrue(text(f).contains(card.tittel.split(separator: " ")[0]))
        XCTAssertEqual(f.state.regelkort, [card.id])
        XCTAssertEqual(f.state.found, ["funn-1"])
        _ = f.key(.a)
        _ = f.key(.a)
        _ = f.talk(to: pile(gives: card.id))
        XCTAssertEqual(text(f), "Det er ikke mer her.")
        XCTAssertEqual(f.state.regelkort, [card.id])
    }

    func testBagListsCardsAndFullmakter() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.regelkort = [card.id, other.id]
        s.fullmakter = ["havna"]
        var f = flow(s)
        f.openBag()
        XCTAssertEqual(f.rows.map(\.text), ["KAFFE x0", "AVTALER x\(s.contracts)", "REGELKORT x2", "FULLMAKT x1"])
        _ = f.key(.down); _ = f.key(.down); _ = f.key(.down)
        _ = f.key(.a)
        XCTAssertTrue(text(f).contains("Havna"), text(f))
        var empty = flow()
        empty.openBag()
        for _ in 0..<3 { _ = empty.key(.down) }
        _ = empty.key(.a)
        XCTAssertEqual(text(empty), "Ingen fullmakter ennå.")
        var none = flow()
        none.openBag()
        _ = none.key(.down); _ = none.key(.down)
        _ = none.key(.a)
        XCTAssertEqual(text(none), "Du har ingen regelkort.")
    }

    func testEquipAndUnequip() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.regelkort = [card.id, other.id]
        var f = flow(s)
        f.openBag()
        _ = f.key(.down); _ = f.key(.down)
        _ = f.key(.a)
        XCTAssertEqual(f.phase, .cards)
        XCTAssertEqual(f.rows.count, 2)
        let target = f.rows.firstIndex { $0.id == other.id } ?? 0
        for _ in 0..<target { _ = f.key(.down) }
        XCTAssertTrue(f.rows[target].full?.hasSuffix("Legges til trekkene i neste kamp.") == true)
        _ = f.key(.a)
        XCTAssertEqual(f.state.equippedCard, other.id)
        XCTAssertEqual(f.rows.filter(\.marked).map(\.id), [other.id])
        _ = f.key(.a)
        XCTAssertNil(f.state.equippedCard)
        XCTAssertTrue(f.rows.filter(\.marked).isEmpty)
        XCTAssertEqual(text(f), "Kortet er lagt tilbake.")
    }

    func testTakeEquippedCardIsOneBattle() {
        var s = TownState.new(content: Self.town, year: 2026)
        s.equippedCard = card.id
        XCTAssertEqual(s.takeEquippedCard(), card.id)
        XCTAssertNil(s.takeEquippedCard())
        XCTAssertNil(s.equippedCard)
    }

    func testEquippedCardJoinsTheOwnCardsOnce() {
        var s = TownState.new(content: Self.town, year: 2026)
        XCTAssertEqual(s.ownCards([card], all: Self.library.rules).map(\.id), [card.id])
        s.equippedCard = other.id
        XCTAssertEqual(s.ownCards([card], all: Self.library.rules).map(\.id), [card.id, other.id])
        XCTAssertEqual(s.ownCards([card, other], all: Self.library.rules).map(\.id), [card.id, other.id])
        s.equippedCard = "finnes-ikke"
        XCTAssertEqual(s.ownCards([card], all: Self.library.rules).map(\.id), [card.id])
    }

    func testOldSaveHasNoCardsOrFinds() throws {
        var s = TownState.new(content: Self.town, year: 2026)
        s.found = ["funn-1"]
        s.equippedCard = card.id
        let round = try JSONDecoder().decode(TownState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.found, ["funn-1"])
        XCTAssertEqual(round.equippedCard, card.id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        json.removeValue(forKey: "found")
        json.removeValue(forKey: "equippedCard")
        let old = try JSONDecoder().decode(TownState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.found.isEmpty)
        XCTAssertNil(old.equippedCard)
    }
}
