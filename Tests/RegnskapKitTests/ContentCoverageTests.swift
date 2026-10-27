import XCTest
@testable import RegnskapKit

final class ContentCoverageTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)

    func testEveryTopicHasFourPuzzles() {
        for topic in Self.library.topics {
            XCTAssertGreaterThanOrEqual(Self.library.puzzles(tema: topic.id).count, 4, topic.id)
        }
    }

    func testAtLeastTwentyEdgeCases() {
        XCTAssertGreaterThanOrEqual(Self.library.puzzles.filter(\.isEdgeCase).count, 20)
    }

    func testEveryKindAppears() {
        for kind in PuzzleKind.allCases {
            XCTAssertTrue(Self.library.puzzles.contains { $0.kind == kind }, kind.rawValue)
        }
    }

    func testEveryTopicHasARuleCard() {
        for topic in Self.library.topics {
            XCTAssertFalse(Self.library.rules(tema: topic.id).isEmpty, "ingen regelkort for \(topic.id)")
        }
    }

    func testNoInternalNames() throws {
        let banned = ["catacloud", "jira", "intercom", "dev-"]
        for url in ContentLibrary.jsonFiles(under: ContentLocator.repoContent) {
            let text = try String(contentsOf: url, encoding: .utf8).lowercased()
            for word in banned { XCTAssertFalse(text.contains(word), "\(url.lastPathComponent) nevner \(word)") }
        }
    }
}
