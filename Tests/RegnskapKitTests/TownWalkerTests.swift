import XCTest
@testable import RegnskapKit

final class TownWalkerTests: XCTestCase {
    private func person(_ id: String, x: Int, y: Int, rolle: PersonRole = .folk) -> TownPerson {
        TownPerson(id: id, rolle: rolle, x: x, y: y, klient: nil, fagkontor: nil, tekst: ["Hei"])
    }

    private func map(_ rows: [String], doors: [Door] = [], folk: [TownPerson] = []) -> TownMap {
        TownMap(id: "test", navn: "Test", bredde: rows[0].count, hoyde: rows.count, ruter: rows, dorer: doors, folk: folk, fullmakt: nil)
    }

    func testTurnsBeforeMoving() {
        let m = map(["...", "...", "..."])
        var w = TownWalker(x: 1, y: 1, facing: .down)
        XCTAssertEqual(w.step(.right, on: m), .turned)
        XCTAssertEqual(w.facing, .right)
        XCTAssertEqual(w.x, 1)
        XCTAssertEqual(w.y, 1)
        XCTAssertEqual(w.step(.right, on: m), .moved)
        XCTAssertEqual(w.x, 2)
    }

    func testMovesOntoFloor() {
        let m = map(["...", ",..", "..."])
        var w = TownWalker(x: 1, y: 1, facing: .up)
        XCTAssertEqual(w.step(.up, on: m), .moved)
        XCTAssertEqual(w.y, 0)
        w = TownWalker(x: 1, y: 1, facing: .left)
        XCTAssertEqual(w.step(.left, on: m), .moved)
        XCTAssertEqual(w.x, 0)
        XCTAssertEqual(w.step(.down, on: m), .turned)
        XCTAssertEqual(w.step(.down, on: m), .moved)
        XCTAssertEqual(w.y, 2)
    }

    func testBlockedByWallWaterAndPeople() {
        let m = map(["#~.", "...", "..."], folk: [person("p", x: 1, y: 1)])
        var w = TownWalker(x: 0, y: 1, facing: .up)
        XCTAssertEqual(w.step(.up, on: m), .blocked)
        w = TownWalker(x: 1, y: 2, facing: .up)
        XCTAssertEqual(w.step(.up, on: m), .blocked)
        w = TownWalker(x: 2, y: 1, facing: .left)
        XCTAssertEqual(w.step(.left, on: m), .blocked)
        XCTAssertEqual(w.x, 2)
        let water = map(["~.."])
        var v = TownWalker(x: 1, y: 0, facing: .left)
        XCTAssertEqual(v.step(.left, on: water), .blocked)
    }

    func testDoorEventWhenSteppingOnDoor() {
        let door = Door(x: 1, y: 0, til: "sentrum", tilX: 3, tilY: 4)
        let m = map([".D.", "..."], doors: [door])
        var w = TownWalker(x: 1, y: 1, facing: .up)
        XCTAssertEqual(w.step(.up, on: m), .door(door))
        XCTAssertEqual(w.x, 1)
        XCTAssertEqual(w.y, 0)
    }

    func testTalkToPersonInFront() {
        let p = person("p", x: 1, y: 0)
        let m = map([".,.", "..."], folk: [p])
        var w = TownWalker(x: 1, y: 1, facing: .up)
        XCTAssertEqual(w.step(.a, on: m), .talk(p))
        XCTAssertEqual(w.step(.a, on: map(["...", "..."])), .nothing)
        XCTAssertEqual(w.step(.tab, on: m), .nothing)
    }

    func testTalkAcrossCounter() {
        let clerk = person("s", x: 1, y: 0, rolle: .skranke)
        let m = map([".,.", ".=.", "..."], folk: [clerk])
        var w = TownWalker(x: 1, y: 2, facing: .up)
        XCTAssertEqual(w.step(.a, on: m), .talk(clerk))
        XCTAssertEqual(w.step(.up, on: m), .blocked)
        // A counter with nobody behind it is just a counter.
        let empty = map([".,.", ".=.", "..."])
        XCTAssertEqual(w.step(.a, on: empty), .nothing)
    }

    func testCannotLeaveTheMap() {
        let m = map(["..", ".."])
        var w = TownWalker(x: 0, y: 0, facing: .up)
        XCTAssertEqual(w.step(.up, on: m), .blocked)
        XCTAssertEqual(w.step(.left, on: m), .turned)
        XCTAssertEqual(w.step(.left, on: m), .blocked)
        w = TownWalker(x: 1, y: 1, facing: .right)
        XCTAssertEqual(w.step(.right, on: m), .blocked)
        XCTAssertEqual(w.step(.down, on: m), .turned)
        XCTAssertEqual(w.step(.down, on: m), .blocked)
        XCTAssertEqual(w.x, 1)
        XCTAssertEqual(w.y, 1)
    }
}
