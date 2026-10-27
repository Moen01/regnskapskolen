import XCTest
@testable import RegnskapKit

final class MarkdownBlocksTests: XCTestCase {
    func testParagraphsHeadingsAndBullets() {
        let text = """
        # Tittel

        Første avsnitt
        fortsetter her.

        - ett
        - to

        1. en
        2. to
        """
        XCTAssertEqual(MarkdownBlocks.parse(text), [
            .heading(level: 1, text: "Tittel"),
            .paragraph("Første avsnitt fortsetter her."),
            .bullets(["ett", "to"]),
            .bullets(["1. en", "2. to"]),
        ])
    }

    func testTableSkipsTheSeparatorRow() {
        let text = """
        | Hva | Frist |
        |---|---|
        | Skattemelding | 31. mai |
        | Innsending | **31. juli** |
        """
        XCTAssertEqual(MarkdownBlocks.parse(text), [
            .table(header: ["Hva", "Frist"], rows: [["Skattemelding", "31. mai"], ["Innsending", "**31. juli**"]]),
        ])
    }

    func testBlocksEndWithoutABlankLine() {
        XCTAssertEqual(MarkdownBlocks.parse("## A\nTekst\n- punkt"), [.heading(level: 2, text: "A"), .paragraph("Tekst"), .bullets(["punkt"])])
        XCTAssertEqual(MarkdownBlocks.parse("   \n\n"), [])
    }

    func testRepoRuleCardsParseIntoMoreThanOneBlock() throws {
        let cards = RuleCard.load(folder: ContentLocator.repoContent.appendingPathComponent("regler"))
        XCTAssertFalse(cards.isEmpty)
        for card in cards { XCTAssertGreaterThan(MarkdownBlocks.parse(card.body).count, 1, card.id) }
    }
}
