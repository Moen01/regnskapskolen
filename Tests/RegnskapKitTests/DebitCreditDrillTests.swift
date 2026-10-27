import XCTest
@testable import RegnskapKit

final class DebitCreditDrillTests: XCTestCase {
    static let chart = try! ContentLibrary(root: ContentLocator.repoContent).chart
    func drill(seed: UInt64 = 1) -> DebitCreditDrill { DebitCreditDrill(chart: Self.chart, seed: seed, startedAt: 0) }

    func testCardsCoverEveryAccountTwiceExceptDisponering() {
        let cards = DebitCreditDrill.cards(chart: Self.chart)
        let counted = Self.chart.all.filter { $0.type != .disponering }
        XCTAssertEqual(cards.count, counted.count * 2)
        for account in counted { XCTAssertEqual(cards.filter { $0.account.nr == account.nr }.count, 2, account.nr) }
        XCTAssertFalse(cards.contains { $0.account.type == .disponering })
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
    }

    func testAnswersFollowOkerPa() {
        for card in DebitCreditDrill.cards(chart: Self.chart) {
            XCTAssertEqual(card.answer, card.increases ? card.account.okerPa : card.account.okerPa.other, card.id)
        }
    }

    func testExplanationsForNormalAndContraAccounts() throws {
        func card(_ nr: String) -> DrillCard { DrillCard(account: Self.chart.account(nr)!, increases: true) }
        XCTAssertEqual(card("4300").explanation, "4300 er en kostnad. Kostnader øker på debet.")
        XCTAssertEqual(card("2400").explanation, "2400 er gjeld. Gjeld øker på kredit.")
        XCTAssertEqual(card("1920").explanation, "1920 er en eiendel. Eiendeler øker på debet.")
        XCTAssertEqual(card("3000").explanation, "3000 er en inntekt. Inntekter øker på kredit.")
        XCTAssertEqual(card("2050").explanation, "2050 er egenkapital. Egenkapital øker på kredit.")
        let contra = card("1580")
        XCTAssertTrue(contra.isContra)
        XCTAssertEqual(contra.explanation, try XCTUnwrap(contra.account.merknad) + " Den øker på kredit.")
        XCTAssertFalse(card("4300").isContra)
    }

    func testEveryContraAccountHasANote() {
        for card in DebitCreditDrill.cards(chart: Self.chart) where card.isContra {
            XCTAssertFalse((card.account.merknad ?? "").isEmpty, "\(card.account.nr) needs a merknad for its explanation")
        }
        XCTAssertTrue(DebitCreditDrill.cards(chart: Self.chart).contains { $0.account.nr == "2080" && $0.isContra })
    }

    func testScoringSpeedBonusAndFeedbackPause() {
        var d = drill()
        let first = d.current!
        XCTAssertEqual(d.answer(first.answer, at: 1.0), 15, "10 × 1.0 plus the speed bonus")
        XCTAssertEqual(d.phase, .question(shownAt: 1.0))
        let second = d.current!
        XCTAssertEqual(d.answer(second.answer, at: 3.0), 12, "10 × 1.25, no bonus after 2 s")
        XCTAssertEqual(d.score, 27); XCTAssertEqual(d.correct, 2); XCTAssertEqual(d.answered, 2)
        let third = d.current!
        XCTAssertEqual(d.answer(third.answer.other, at: 4.0), 0)
        XCTAssertEqual(d.phase, .feedback(since: 4.0))
        XCTAssertEqual(d.lastCorrect, false)
        XCTAssertEqual(d.combo.multiplier, 1.0)
        XCTAssertEqual(d.remaining(at: 10), 56, "paused since 4.0")
        d.next(at: 5.0); XCTAssertEqual(d.phase, .feedback(since: 4.0))
        d.next(at: 5.5); XCTAssertEqual(d.phase, .question(shownAt: 5.5))
        XCTAssertEqual(d.remaining(at: 5.5), 56)
    }

    func testRoundEndsAtSixtySecondsAndTheQueueWrapsAround() {
        var d = drill()
        let total = DebitCreditDrill.cards(chart: Self.chart).count
        for i in 0..<total { _ = d.answer(d.current!.answer, at: Double(i) * 0.1) }
        XCTAssertNotNil(d.current, "the queue refills")
        XCTAssertEqual(d.answered, total)
        d.tick(at: 60); XCTAssertEqual(d.phase, .finished)
        XCTAssertNil(d.answer(.debet, at: 61))
        XCTAssertEqual(d.summary.game, .debetKredit)
        XCTAssertEqual(d.summary.correct, total)
    }

    func testSeededOrder() {
        XCTAssertEqual(drill(seed: 3).queue.map(\.id), drill(seed: 3).queue.map(\.id))
        XCTAssertNotEqual(drill(seed: 3).queue.map(\.id), drill(seed: 4).queue.map(\.id))
    }
}
