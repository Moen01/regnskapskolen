import XCTest
@testable import RegnskapKit

final class LawNamesTests: XCTestCase {
    func testShortFallsBackToTheFullName() {
        let laws = LawNames(all: [LawName(navn: "bokføringsloven", kort: "bfl.", tittel: nil), LawName(navn: "inkassoforskriften", kort: nil, tittel: nil)])
        XCTAssertEqual(laws.short("bokføringsloven"), "bfl.")
        XCTAssertEqual(laws.short("inkassoforskriften"), "inkassoforskriften")
        XCTAssertEqual(laws.short("ukjent lov"), "ukjent lov")
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertEqual(LawNames.load(url: URL(fileURLWithPath: "/nonexistent/lover.json")).all, [])
    }

    func testMoveShortLabel() {
        let laws = LawNames(all: [LawName(navn: "bokføringsloven", kort: "bfl.", tittel: nil)])
        XCTAssertEqual(Move(lov: "bokføringsloven", paragraf: "§ 4").shortLabel(laws: laws), "bfl. § 4")
        XCTAssertEqual(Move(lov: "ferieloven", paragraf: "§ 10").shortLabel(laws: laws), "ferieloven § 10")
    }

    func testEveryLawInTheRepoHasAnEntryAndShortNamesAreUnique() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let known = Set(library.laws.all.map(\.navn))
        let used = Set(library.puzzles.flatMap { $0.lov.map(\.lov) } + library.rules.flatMap { $0.lov.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })
        XCTAssertTrue(used.subtracting(known).isEmpty, "mangler i lover.json: \(used.subtracting(known).sorted())")
        let shorts = library.laws.all.compactMap(\.kort)
        XCTAssertEqual(Set(shorts).count, shorts.count)
        XCTAssertTrue(shorts.allSatisfy { $0.count <= 8 }, "a short name longer than 8 does not fit the move list")
    }
}
