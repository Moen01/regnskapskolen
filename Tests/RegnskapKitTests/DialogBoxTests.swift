import XCTest
@testable import RegnskapKit

final class DialogBoxTests: XCTestCase {
    func testDialogBoxIsThirtySixBySix() {
        XCTAssertEqual(DialogBox.columns, 36)
        XCTAssertEqual(DialogBox.rows, 6)
        XCTAssertEqual(DialogBox.glyph, 4)
        // 36 glyphs of 4 px leave 8 px on each side of the 160 px screen.
        XCTAssertEqual(DialogBox.columns * DialogBox.glyph + 2 * 8, 160)
    }

    func testBattleAndTownUseTheDialogBox() {
        XCTAssertEqual(BattleFlow.columns, DialogBox.columns)
        XCTAssertEqual(BattleFlow.rows, DialogBox.rows)
        XCTAssertEqual(TownFlow.columns, DialogBox.columns)
        XCTAssertEqual(TownFlow.rows, DialogBox.rows)
    }

    func testLongestTownLineFitsThirtySix() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let town = library.town
        XCTAssertFalse(town.kart.isEmpty, "the repo has a town")
        let regions = Regions.build(topics: library.topics, pool: library.pool(includeDrafts: false), progress: LearnerProgress())
        let pool = Set(library.pool(includeDrafts: false).map(\.id))
        var longest = 0

        func check(_ f: TownFlow, _ label: String) {
            for page in f.pages {
                XCTAssertLessThanOrEqual(page.count, DialogBox.rows, "\(label): \(page)")
                for line in page {
                    longest = max(longest, line.count)
                    XCTAssertLessThanOrEqual(line.count, DialogBox.columns, "\(label): «\(line)»")
                }
            }
        }

        let base = TownState.new(content: town, year: 2026)
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
        // Lines now use the wider box; a town that never goes past 18 would mean the paging still wraps at 18.
        XCTAssertGreaterThan(longest, 18)
    }
}
