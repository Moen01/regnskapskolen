import XCTest
@testable import RegnskapKit

final class BattleScriptTests: XCTestCase {
    private func encounter(gym: Bool = false, stage: Stage = .vill) -> Encounter {
        let puzzle = try! Puzzle.decode(Data("""
        {"id":"mva-quiz-01","type":"quiz","tema":"mva","vanskelighet":2,"tittel":"Kontantsalg av en tjeneste","oppgave":"Hva gjelder?","lov":[{"lov":"bokføringsloven","paragraf":"§ 4","tekst":"Grunnleggende prinsipper."}],"forklaring":"Fordi **bfl.** sier det.","status":"godkjent","alternativer":["A","B"],"svar":0}
        """.utf8))
        return Encounter(puzzle: puzzle, stageBefore: stage, moves: [Move(lov: "bokføringsloven", paragraf: "§ 4")], isGymLeader: gym)
    }
    private let laws = LawNames(all: [LawName(navn: "bokføringsloven", kort: "bfl.", tittel: nil)])

    func testIntroNamesTheSpeciesThenTheTitle() {
        let name = SpeciesName.name(for: "mva-quiz-01")
        XCTAssertEqual(BattleScript.intro(encounter()), ["En vill \(name) dukket opp!", "Kontantsalg av en tjeneste"])
        XCTAssertEqual(BattleScript.intro(encounter(gym: true))[0], "Gym-lederen \(name) stiller!")
        XCTAssertEqual(BattleScript.intro(encounter(stage: .ung))[0], "\(name) (UNG) vil kjempe igjen!")
    }

    func testMoveUsed() {
        XCTAssertEqual(BattleScript.moveUsed(Move(lov: "bokføringsloven", paragraf: "§ 4"), laws: laws), "Du brukte bfl. § 4!")
        XCTAssertEqual(BattleScript.moveUsed(nil, laws: laws), "Du angrep uten regel!")
    }

    func testResultLines() {
        let name = SpeciesName.name(for: "mva-quiz-01")
        XCTAssertEqual(BattleScript.result(.caught(stage: .klekket, superEffective: true), encounter: encounter()),
                       ["Det er supereffektivt!", "\(name) ble fanget! Trinn: KLEKKET"])
        XCTAssertEqual(BattleScript.result(.caught(stage: .ung, superEffective: false), encounter: encounter()),
                       ["Treff!", "\(name) ble fanget! Trinn: UNG"])
        XCTAssertEqual(BattleScript.result(.escaped(hpLost: 1000), encounter: encounter()),
                       ["Bom!", "\(name) flyktet! Kunden mistet 1 000 kr."])
        XCTAssertEqual(BattleScript.result(.repeated, encounter: encounter()),
                       ["Riktig, men \(name) er alt møtt i dag.", "Den kommer igjen i morgen."])
    }

    func testExplanationIsPlainTextPlusLawLines() {
        XCTAssertEqual(BattleScript.explanation(encounter(), laws: laws), ["Fordi bfl. sier det.", "bfl. § 4: Grunnleggende prinsipper."])
    }

    func testKronerUsesAsciiMinusAndAPlainSpace() {
        XCTAssertEqual(BattleScript.kroner(-2500), "-2 500")
        XCTAssertEqual(BattleScript.kroner(1_250_000), "1 250 000")
    }
}
