import XCTest
@testable import RegnskapKit

/// Reads from the tutor's side while the app reloads on the main actor. Run with
/// `swift test --sanitize=thread --filter ContentLibraryConcurrencyTests` to make a race visible.
final class ContentLibraryConcurrencyTests: XCTestCase {
    func testReloadWhileReadingHasNoDataRace() throws {
        let library = try ContentLibrary(root: ContentLocator.repoContent)
        let tutor = Tutor(library: library, model: "sonnet")
        DispatchQueue.concurrentPerform(iterations: 40) { i in
            if i % 4 == 0 {
                try? library.reload()
                tutor.model = i % 8 == 0 ? "opus" : "sonnet"
            } else {
                _ = library.pool(includeDrafts: true).count
                _ = library.puzzle(id: "grunnlag-001")
                _ = library.rules(tema: "mva").count
                _ = library.rates.mvaSatser.count
                _ = tutor.model
                library.generatedInMemory = []
            }
        }
        XCTAssertFalse(library.puzzles.isEmpty)
    }
}
