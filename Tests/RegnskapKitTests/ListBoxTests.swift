import XCTest
@testable import RegnskapKit

final class ListBoxTests: XCTestCase {
    func testListBoxIsThirtyFourColumns() {
        XCTAssertEqual(ListBox.columns, 34)
        XCTAssertEqual(ListBox.rowHeight, 7)
        XCTAssertEqual(ListBox.glyph, 4)
        // The cursor column and 34 glyphs of 4 px fit inside the 152 px list window less 5 px padding a side.
        XCTAssertLessThanOrEqual((ListBox.columns + 1) * ListBox.glyph, 152 - 2 * 5)
        // A title of 8 px glyphs still fits the window.
        XCTAssertLessThanOrEqual(ListBox.titleColumns * 8, 152 - 2 * 4)
    }

    func testRowsFollowTheHeight() {
        XCTAssertEqual(ListBox.rows(in: 72), 10)
        XCTAssertEqual(ListBox.rows(in: 6), 1, "a list always shows its cursor row")
        XCTAssertEqual(AnswerPanel.visibleRows, ListBox.rows(in: ListBox.windowRowSpace))
    }

    func testTownAndPanelUseTheListBox() {
        XCTAssertEqual(TownFlow.rowColumns, ListBox.columns)
        XCTAssertEqual(AnswerPanel.columns, ListBox.columns)
    }

    func testLongestTownRowFitsThirtyFour() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let town = library.town
        XCTAssertFalse(town.kart.isEmpty, "the repo has a town")
        let regions = Regions.build(topics: library.topics, pool: library.pool(includeDrafts: false), progress: LearnerProgress())
        let pool = Set(library.pool(includeDrafts: false).map(\.id))
        var longest = 0

        func check(_ f: TownFlow, _ label: String) {
            for row in f.rows {
                longest = max(longest, row.text.count)
                XCTAssertLessThanOrEqual(row.text.count, ListBox.columns, "\(label): «\(row.text)»")
            }
        }

        var base = TownState.new(content: town, year: 2026)
        for id in base.clients.keys { base.clients[id]!.met = true }
        for map in town.kart {
            for person in map.folk {
                var state = base
                state.mapId = map.id
                var f = TownFlow(content: town, state: state, deadlines: library.deadlines, pool: pool, regions: regions,
                                 damage: [:], badges: [], ruleCards: library.rules)
                _ = f.talk(to: person)
                check(f, person.id)
                var guardCount = 0
                while f.phase == .dialog, guardCount < 50 {
                    _ = f.key(.a)
                    check(f, person.id)
                    guardCount += 1
                }
            }
        }
        // The menu and each list it opens, and what each of their rows opens. Off the map, A opens the menu.
        var menu = TownFlow(content: town, state: base, deadlines: library.deadlines, pool: pool, regions: regions,
                            damage: [:], badges: [], ruleCards: library.rules)
        menu.state.mapId = "ingen"
        _ = menu.key(.a)
        XCTAssertEqual(menu.phase, .menu)
        check(menu, "menu")
        for i in 0..<3 {
            var list = menu
            while list.cursor < i { _ = list.key(.down) }
            _ = list.key(.a)
            check(list, "menu \(i)")
            for row in list.rows.indices {
                var g = list
                while g.cursor < row { _ = g.key(.down) }
                _ = g.key(.a)
                check(g, "menu \(i) row \(row)")
            }
        }
        // Rows now use the wider list; nothing past 17 would mean the rows are still cut at 17.
        XCTAssertGreaterThan(longest, 17)
    }
}
