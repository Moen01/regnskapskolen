import XCTest
@testable import RegnskapKit

final class ContentValidatorTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)

    private func puzzle(_ fixture: String, mutate: (inout JSONValue) -> Void = { _ in }) throws -> Puzzle {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/puzzles/valid/\(fixture).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        mutate(&json)
        return try Puzzle.decode(json.data)
    }

    private func set(_ json: inout JSONValue, _ key: String, _ value: JSONValue) {
        var o = json.object ?? [:]
        o[key] = value
        json = .object(o)
    }

    func testRepoContentIsValid() {
        let problems = ContentValidator.validateAll(Self.library)
        XCTAssertTrue(problems.isEmpty, problems.map { "\($0.id): \($0.messages.joined(separator: "; "))" }.joined(separator: "\n"))
    }

    func testRejectsUnbalancedPosting() throws {
        let p = try puzzle("postering") { set(&$0, "fasit", .array([.object(["konto": .string("1920"), "side": .string("D"), "belop": .number(100)]),
                                                                       .object(["konto": .string("3000"), "side": .string("K"), "belop": .number(90)])])) }
        let messages = ContentValidator.validate(p, library: Self.library)
        XCTAssertTrue(messages.contains { $0.contains("balanserer ikke") }, messages.joined(separator: "; "))
    }

    func testRejectsUnknownAccount() throws {
        let p = try puzzle("postering") { set(&$0, "fasit", .array([.object(["konto": .string("1920"), "side": .string("D"), "belop": .number(100)]),
                                                                       .object(["konto": .string("9999"), "side": .string("K"), "belop": .number(100)])])) }
        XCTAssertTrue(ContentValidator.validate(p, library: Self.library).contains { $0.contains("9999") })
    }

    func testRejectsQuizIndexOutOfRange() throws {
        let p = try puzzle("quiz") { set(&$0, "svar", .number(7)) }
        XCTAssertTrue(ContentValidator.validate(p, library: Self.library).contains { $0.contains("svar") })
    }

    func testFristMustMatchRule() throws {
        let p = try puzzle("frist") { set(&$0, "fasit", .string("2026-08-10")) }
        let messages = ContentValidator.validate(p, library: Self.library)
        XCTAssertTrue(messages.contains { $0.contains("2026-08-31") }, messages.joined(separator: "; "))
    }

    func testRejectsMissingLawAndBadParagraph() throws {
        XCTAssertTrue(ContentValidator.validate(try puzzle("quiz") { set(&$0, "lov", .array([])) }, library: Self.library).contains { $0.contains("lov") })
        let bad = try puzzle("quiz") { set(&$0, "lov", .array([.object(["lov": .string("mval."), "paragraf": .string("§ 3-1 første ledd"), "tekst": .string("x")])])) }
        XCTAssertTrue(ContentValidator.validate(bad, library: Self.library).contains { $0.contains("paragraf") })
    }

    func testRejectsUnknownTopicDifficultyAndVATCode() throws {
        XCTAssertTrue(ContentValidator.validate(try puzzle("quiz") { set(&$0, "tema", .string("nope")) }, library: Self.library).contains { $0.contains("tema") })
        XCTAssertTrue(ContentValidator.validate(try puzzle("quiz") { set(&$0, "vanskelighet", .number(9)) }, library: Self.library).contains { $0.contains("vanskelighet") })
        XCTAssertTrue(ContentValidator.validate(try puzzle("mva") { set(&$0, "fasit", .object(["behandling": .string("30"), "fradrag": .bool(true)])) }, library: Self.library).contains { $0.contains("behandling") })
        XCTAssertTrue(ContentValidator.validate(try puzzle("klassifiser") { set(&$0, "kategorier", .array([.string("Eiendel")])) }, library: Self.library).contains { $0.contains("kategori") })
    }

    func testTownNamesNoRealAgency() {
        let town = Self.library.town
        var texts: [String] = []
        for map in town.kart {
            texts.append(map.navn)
            for p in map.folk {
                texts += p.tekst
                texts += (p.kontrollorer ?? []).map(\.navn)
                if let sensor = p.sensor { texts.append(sensor.navn) }
            }
        }
        for client in town.klienter {
            let l = client.replikker
            texts.append(client.navn)
            for group in [l.hilsen, l.drift, l.haug, l.tomHaug, l.glippetFrist, l.oppdagetFeil] { texts += group }
        }
        XCTAssertFalse(texts.isEmpty)
        for word in ["skatteetaten", "altinn", "brønnøysund", "regnskapsregisteret"] {
            XCTAssertFalse(texts.contains { $0.lowercased().contains(word) }, "tekst nevner «\(word)»")
        }
    }
}
