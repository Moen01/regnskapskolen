import XCTest
@testable import RegnskapKit

final class RuleCardTests: XCTestCase {
    func testLoadsRules() {
        let rules = RuleCard.load(folder: ContentLocator.repoContent.appendingPathComponent("regler"))
        XCTAssertGreaterThanOrEqual(rules.count, 14)
        for rule in rules {
            XCTAssertFalse(rule.lov.isEmpty, rule.id)
            XCTAssertNotNil(rule.kilde, rule.id)
            XCTAssertFalse(rule.paragrafer.isEmpty, rule.id)
            XCTAssertFalse(rule.body.isEmpty, rule.id)
            XCTAssertLessThan(rule.body.split(separator: " ").count, 320, "\(rule.id) is over 320 words")
        }
        let topics = try! Topics(url: ContentLocator.repoContent.appendingPathComponent("temaer.json"))
        for rule in rules { XCTAssertTrue(topics.contains(rule.tema), "\(rule.id): ukjent tema \(rule.tema)") }
    }

    func testFrontMatterParsing() {
        let text = "---\ntittel: \"Quoted title\"\nlov: bokføringsloven\nparagrafer: § 4, § 7\ntema: grunnlag\n---\nBody line 1\n\nBody line 2\n"
        let card = RuleCard.parse(text, id: "x")
        XCTAssertEqual(card?.tittel, "Quoted title")
        XCTAssertEqual(card?.paragrafer, ["§ 4", "§ 7"])
        XCTAssertEqual(card?.body, "Body line 1\n\nBody line 2")
        XCTAssertNil(card?.kilde)
        XCTAssertNil(RuleCard.parse("no front matter", id: "y"))
    }

    func testLibraryExposesRulesPerTopic() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        XCTAssertFalse(library.rules(tema: "mva").isEmpty)
        XCTAssertTrue(library.rules(tema: "mva").allSatisfy { $0.tema == "mva" })
    }
}
