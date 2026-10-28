import XCTest
@testable import RegnskapKit

final class SpeciesNameTests: XCTestCase {
    func testSameIdSameName() {
        XCTAssertEqual(SpeciesName.name(for: "grunnlag-postering-01"), SpeciesName.name(for: "grunnlag-postering-01"))
    }

    func testNameIsFiveToNineUppercaseLetters() {
        for id in ["a", "mva-quiz-07", "lonn-sak-02", "x-y-z-123"] {
            let name = SpeciesName.name(for: id)
            XCTAssertTrue((5...9).contains(name.count), name)
            XCTAssertTrue(name.allSatisfy { $0.isLetter && $0.isUppercase }, name)
        }
    }

    func testNoTwoPuzzlesInTheRepoShareAName() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let names = library.puzzles.map { SpeciesName.name(for: $0.id) }
        XCTAssertEqual(Set(names).count, names.count, "duplicate species names")
    }
}
