import XCTest
@testable import RegnskapKit

final class BattleScriptTests: XCTestCase {
    private func encounter(gym: Bool = false, stage: Stage = .vill, id: String = "mva-quiz-01", context: EncounterContext = .wild) -> Encounter {
        let puzzle = try! Puzzle.decode(Data("""
        {"id":"\(id)","type":"quiz","tema":"mva","vanskelighet":2,"tittel":"Kontantsalg av en tjeneste","oppgave":"Hva gjelder?","lov":[{"lov":"bokføringsloven","paragraf":"§ 4","tekst":"Grunnleggende prinsipper."}],"forklaring":"Fordi **bfl.** sier det.","status":"godkjent","alternativer":["A","B"],"svar":0}
        """.utf8))
        return Encounter(puzzle: puzzle, stageBefore: stage, moves: [Move(lov: "bokføringsloven", paragraf: "§ 4")], isGymLeader: gym, context: context)
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

    func testTownIntrosAndResults() {
        let day = DayKey(year: 2026, month: 3, day: 7)
        let name = SpeciesName.name(for: "mva-quiz-01")
        XCTAssertEqual(BattleScript.intro(encounter(context: .bilag(client: "k"))), ["Bilag fra haugen!", "Kontantsalg av en tjeneste"])
        XCTAssertEqual(BattleScript.intro(encounter(context: .trial(client: "k"))), ["Prøvesak!", "Kontantsalg av en tjeneste"])
        XCTAssertEqual(BattleScript.intro(encounter(context: .fagkontor(name: "MVA-kontoret"))), ["MVA-kontoret vil teste deg!", "Kontantsalg av en tjeneste"])
        let correction = BattleScript.intro(encounter(context: .correction(client: "k", day: day)))
        XCTAssertEqual(correction.count, 1, "one page")
        if name.count <= 8 {
            XCTAssertEqual(TextWrap.lines(correction[0], columns: 18), ["Avstemmingen går", "ikke opp: \(name)", "07.03."])
        }
        XCTAssertEqual(BattleScript.intro(encounter(context: .kundesak(client: "k", name: "KAFÉ"))), ["KAFÉ lurer på", "noe!", "Kontantsalg av en tjeneste"])
        let e = encounter()
        XCTAssertEqual(BattleScript.result(.answered(ok: true), encounter: e), ["Kunden er", "fornøyd."])
        XCTAssertEqual(BattleScript.result(.answered(ok: false), encounter: e), ["Det stemte ikke."])
        XCTAssertEqual(BattleScript.result(.booked, encounter: e).map { TextWrap.lines($0, columns: 18) }, [["Bilaget er", "bokført."]])
        XCTAssertEqual(BattleScript.result(.corrected(ok: true), encounter: e), ["Feilen er rettet."])
        XCTAssertEqual(BattleScript.result(.corrected(ok: false), encounter: e).map { TextWrap.lines($0, columns: 18) },
                       [["Fortsatt feil.", "Kunden er mindre", "fornøyd."]])
    }

    func testScriptLinesFitEighteenColumns() throws {
        // The longest species name the generator makes, so the correction intro is tested at its widest.
        let longest = try XCTUnwrap((0..<2000).map { "mva-quiz-\($0)" }.first { SpeciesName.name(for: $0).count == SpeciesName.maxLength })
        let day = DayKey(year: 2026, month: 12, day: 31)
        let contexts: [EncounterContext] = [.bilag(client: "k"), .correction(client: "k", day: day), .trial(client: "k"), .fagkontor(name: "Fagkontor MVA")]
        for context in contexts {
            let pages = BattleScript.intro(encounter(id: longest, context: context))
            for page in pages {
                let lines = TextWrap.lines(page, columns: 18)
                XCTAssertTrue(lines.allSatisfy { $0.count <= 18 }, "\(context): \(lines)")
                if case .correction = context {
                    XCTAssertLessThanOrEqual(lines.count, 3, "one dialog page: \(lines)")
                    XCTAssertTrue(lines.joined(separator: " ").contains(SpeciesName.name(for: longest)), "wrapped, not cut: \(lines)")
                }
            }
        }
        for outcome: EncounterOutcome in [.booked, .corrected(ok: true), .corrected(ok: false)] {
            for page in BattleScript.result(outcome, encounter: encounter(id: longest)) {
                let lines = TextWrap.lines(page, columns: 18)
                XCTAssertTrue(lines.allSatisfy { $0.count <= 18 } && lines.count <= 3, "\(outcome): \(lines)")
            }
        }
    }

    func testExplanationIsPlainTextPlusLawLines() {
        XCTAssertEqual(BattleScript.explanation(encounter(), laws: laws), ["Fordi bfl. sier det.", "bfl. § 4: Grunnleggende prinsipper."])
    }

    func testKronerUsesAsciiMinusAndAPlainSpace() {
        XCTAssertEqual(BattleScript.kroner(-2500), "-2 500")
        XCTAssertEqual(BattleScript.kroner(1_250_000), "1 250 000")
    }
}
