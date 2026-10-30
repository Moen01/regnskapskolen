import XCTest
@testable import RegnskapKit

final class TownValidatorTests: XCTestCase {
    static let library = try! ContentLibrary(root: ContentLocator.repoContent)

    /// Loads the fixture town after editing one of its JSON files. `file` is relative to `Fixtures/by`.
    private func town(editing file: String? = nil, adding extra: [String: Any] = [:], edit: (inout [String: Any]) -> Void = { _ in }) throws -> TownContent {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("by-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: TownContentTests.fixtureTown, to: folder)
        if let file {
            let url = folder.appendingPathComponent(file)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            edit(&json)
            try JSONSerialization.data(withJSONObject: json).write(to: url)
        }
        for (path, json) in extra {
            try JSONSerialization.data(withJSONObject: json).write(to: folder.appendingPathComponent(path))
        }
        return try TownContent.load(folder: folder)
    }

    /// Sentrum's gate to Havna, kept when a test replaces the doors of Sentrum so Havna stays reachable.
    private var havnaGate: [String: Any] { ["x": 7, "y": 5, "til": "havna", "tilX": 4, "tilY": 6] }

    private func messages(_ town: TownContent) -> [String] {
        ContentValidator.validateTown(town, library: Self.library).flatMap { p in p.messages.map { "\(p.id): \($0)" } }
    }

    private func assertOneProblem(_ town: TownContent, id: String, contains: String, file: StaticString = #filePath, line: UInt = #line) {
        let all = messages(town)
        XCTAssertEqual(all.count, 1, all.joined(separator: "\n"), file: file, line: line)
        XCTAssertTrue(all.first?.hasPrefix(id) == true && all.first?.contains(contains) == true, all.joined(separator: "\n"), file: file, line: line)
    }

    private func person(_ id: String, x: Int, y: Int, rolle: String = "folk", extra: [String: Any] = [:]) -> [String: Any] {
        ["id": id, "rolle": rolle, "x": x, "y": y, "tekst": ["Hei."]].merging(extra) { $1 }
    }

    func testValidFixtureTownHasNoProblems() throws {
        XCTAssertEqual(messages(try town()), [])
    }

    // Rule 1
    func testRejectsRowOfWrongLength() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["ruter"] = ["##########", "#,,,,,,,,#", "#,......,#", "#,,,,,,,,#", "#,,,D,,,#", "#######D##"] }
        assertOneProblem(t, id: "kart:sentrum", contains: "lengde")
    }

    func testRejectsWrongRowCountAndUnknownTile() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["hoyde"] = 7 }
        assertOneProblem(t, id: "kart:sentrum", contains: "rader")
        let u = try town(editing: "kart/sentrum.json") { $0["ruter"] = ["##########", "#,,,,,,,,#", "#,..?...,#", "#,,,,,,,,#", "#,,,D,,,,#", "#######D##"] }
        assertOneProblem(u, id: "kart:sentrum", contains: "?")
    }

    // Rule 2
    func testRejectsDoorNotOnDoorTile() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["dorer"] = [["x": 5, "y": 4, "til": "kontoret", "tilX": 3, "tilY": 4], self.havnaGate] }
        assertOneProblem(t, id: "kart:sentrum", contains: "dør")
    }

    func testRejectsDoorToMissingMap() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["dorer"] = [["x": 4, "y": 4, "til": "finnes-ikke", "tilX": 3, "tilY": 4], self.havnaGate] }
        assertOneProblem(t, id: "kart:sentrum", contains: "finnes-ikke")
    }

    func testRejectsDoorLandingOnWall() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["dorer"] = [["x": 4, "y": 4, "til": "kontoret", "tilX": 0, "tilY": 0], self.havnaGate] }
        assertOneProblem(t, id: "kart:sentrum", contains: "gangbar")
    }

    func testRejectsDoorLandingOnPerson() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["dorer"] = [["x": 4, "y": 4, "til": "kontoret", "tilX": 3, "tilY": 2], self.havnaGate] }
        assertOneProblem(t, id: "kart:sentrum", contains: "person")
    }

    // Rule 3
    func testRejectsPersonOutsideMap() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["folk"] = [self.person("sjef", x: 20, y: 2, rolle: "sjef")] }
        assertOneProblem(t, id: "kart:kontoret", contains: "utenfor")
    }

    func testRejectsTwoPeopleOnSameTile() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["folk"] = [self.person("a", x: 3, y: 2), self.person("b", x: 3, y: 2)] }
        assertOneProblem(t, id: "kart:kontoret", contains: "samme rute")
    }

    func testRejectsClientPersonWithUnknownClient() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["folk"] = [self.person("k", x: 3, y: 2, rolle: "klient", extra: ["klient": "spoekelset"])] }
        assertOneProblem(t, id: "kart:kontoret", contains: "spoekelset")
    }

    func testRejectsFagkontorWithUnknownTheme() throws {
        let office: [String: Any] = ["id": "fk", "navn": "Fagkontor", "temaer": ["finnes-ikke"]]
        let t = try town(editing: "kart/kontoret.json") { $0["folk"] = [self.person("f", x: 3, y: 2, rolle: "fagkontor", extra: ["fagkontor": office])] }
        assertOneProblem(t, id: "kart:kontoret", contains: "finnes-ikke")
    }

    // Rule 4
    func testRejectsUnreachableMap() throws {
        let island: [String: Any] = ["id": "oey", "navn": "Oey", "bydel": "sentrum", "bredde": 3, "hoyde": 3, "ruter": ["###", "#.#", "###"], "dorer": [], "folk": []]
        let t = try town(adding: ["kart/oey.json": island])
        assertOneProblem(t, id: "kart:oey", contains: "nås ikke")
    }

    // Rule 5
    func testRejectsUnknownIndustry() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["bransje"] = "ukjent" }
        assertOneProblem(t, id: "klient:butikken", contains: "ukjent")
    }

    func testRejectsUnknownPuzzleId() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["oppgaver"] = ["mva-quiz-001", "mva-quiz-999"] }
        assertOneProblem(t, id: "klient:butikken", contains: "mva-quiz-999")
    }

    func testRejectsTrialWithWrongCount() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["provesak"] = ["mva-quiz-001", "mva-quiz-002"] }
        assertOneProblem(t, id: "klient:butikken", contains: "prøvesak")
    }

    func testRejectsVatTermWithoutRegistration() throws {
        let t = try town(editing: "klienter/konsulenten.json") { $0["mvaTermin"] = "aarlig" }
        assertOneProblem(t, id: "klient:konsulenten", contains: "mvaTermin")
    }

    func testRejectsRegisteredClientWithoutVatTerm() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["mvaTermin"] = nil }
        assertOneProblem(t, id: "klient:butikken", contains: "mvaTermin")
    }

    func testRejectsPlaceWithoutClientPerson() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["sted"] = ["kart": "sentrum", "x": 3, "y": 2] }
        assertOneProblem(t, id: "klient:butikken", contains: "sted")
    }

    func testRejectsTwoStartClients() throws {
        let t = try town(editing: "klienter/konsulenten.json") { $0["startklient"] = true }
        assertOneProblem(t, id: "by:startklient", contains: "startklient")
    }

    func testRejectsNoStartClient() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["startklient"] = false }
        assertOneProblem(t, id: "by:startklient", contains: "startklient")
    }

    func testRejectsTownWithNoClients() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("by-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: TownContentTests.fixtureTown, to: folder)
        for name in ["butikken", "konsulenten"] { try FileManager.default.removeItem(at: folder.appendingPathComponent("klienter/\(name).json")) }
        let t = try TownContent.load(folder: folder)
        XCTAssertTrue(messages(t).contains { $0.hasPrefix("by:startklient") })
    }

    func testEmptyTownHasNoProblems() {
        XCTAssertEqual(messages(.empty), [])
    }

    // Rule 6
    func testRejectsVatTaskForUnregisteredClient() throws {
        let t = try town(editing: "klienter/konsulenten.json") { $0["oppgaver"] = ["grunnlag-quiz-010", "mva-behandling-001"] }
        assertOneProblem(t, id: "klient:konsulenten", contains: "mva-behandling-001")
    }

    func testRejectsVatAccountPostingForUnregisteredClient() throws {
        let t = try town(editing: "klienter/konsulenten.json") { $0["oppgaver"] = ["grunnlag-quiz-010", "grunnlag-001"] }
        assertOneProblem(t, id: "klient:konsulenten", contains: "grunnlag-001")
    }

    func testAllowsVatTaskForRegisteredClient() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["oppgaver"] = ["mva-behandling-001", "grunnlag-001"] }
        XCTAssertEqual(messages(t), [])
    }

    // Rule 11
    private func withCase(client: String, puzzle: String?) throws -> TownContent {
        var extra: [String: Any] = ["klient": client]
        if let puzzle { extra["oppgave"] = puzzle }
        return try town(editing: "kart/sentrum.json") { json in
            var folk = json["folk"] as! [[String: Any]]
            folk.append(person("sak-1", x: 4, y: 2, rolle: "kundesak", extra: extra))
            json["folk"] = folk
        }
    }

    func testAllowsCaseWithQuizOrSak() throws {
        XCTAssertEqual(messages(try withCase(client: "butikken", puzzle: "grunnlag-quiz-010")), [])
        XCTAssertEqual(messages(try withCase(client: "kafeen", puzzle: "reskontro-sak-001")), [])
    }

    func testRejectsCaseWithBookingPuzzle() throws {
        assertOneProblem(try withCase(client: "butikken", puzzle: "grunnlag-001"), id: "kart:sentrum", contains: "ikke sak eller quiz")
    }

    func testRejectsCaseWithUnknownClientOrPuzzle() throws {
        assertOneProblem(try withCase(client: "ingen", puzzle: "grunnlag-quiz-010"), id: "kart:sentrum", contains: "ingen")
        assertOneProblem(try withCase(client: "butikken", puzzle: "finnes-ikke"), id: "kart:sentrum", contains: "finnes-ikke")
        assertOneProblem(try withCase(client: "butikken", puzzle: nil), id: "kart:sentrum", contains: "ingen oppgave")
    }

    func testRejectsVatCaseByItsType() throws {
        // A case is sak or quiz, so a VAT task is caught by the type rule alone.
        assertOneProblem(try withCase(client: "kafeen", puzzle: "mva-behandling-001"), id: "kart:sentrum", contains: "ikke sak eller quiz")
        XCTAssertEqual(messages(try withCase(client: "butikken", puzzle: "mva-quiz-004")), [])
    }

    func testRejectsCaseFromTheClientsPileOrTrial() throws {
        // A case shows its verdict; the same puzzle as a bilag or in the trial would give it away.
        assertOneProblem(try withCase(client: "butikken", puzzle: "mva-quiz-001"), id: "kart:sentrum", contains: "bilag eller prøvesak")
        assertOneProblem(try withCase(client: "butikken", puzzle: "mva-quiz-002"), id: "kart:sentrum", contains: "bilag eller prøvesak")
    }

    // Rule 7
    func testRejectsUnknownRuleCard() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("by-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: TownContentTests.fixtureTown, to: folder)
        let url = folder.appendingPathComponent("bransjer.json")
        var list = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        list[0]["regelkort"] = ["mva-satser", "regelkort-som-ikke-finnes"]
        try JSONSerialization.data(withJSONObject: list).write(to: url)
        assertOneProblem(try TownContent.load(folder: folder), id: "bransje:butikk", contains: "regelkort-som-ikke-finnes")
    }

    func testRejectsUnknownIndustryTheme() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("by-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: TownContentTests.fixtureTown, to: folder)
        let url = folder.appendingPathComponent("bransjer.json")
        var list = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        list[0]["temaer"] = ["mva", "tema-som-ikke-finnes"]
        try JSONSerialization.data(withJSONObject: list).write(to: url)
        assertOneProblem(try TownContent.load(folder: folder), id: "bransje:butikk", contains: "tema-som-ikke-finnes")
    }

    // Rule 8
    func testRejectsThemeInTwoOffices() throws {
        let a: [String: Any] = ["id": "a", "navn": "Kontor A", "temaer": ["mva"]]
        let b: [String: Any] = ["id": "b", "navn": "Kontor B", "temaer": ["mva", "grunnlag"]]
        let t = try town(editing: "kart/kontoret.json") {
            $0["folk"] = [self.person("sjef", x: 3, y: 2, rolle: "sjef"),
                          self.person("fa", x: 1, y: 1, rolle: "fagkontor", extra: ["fagkontor": a]),
                          self.person("fb", x: 2, y: 1, rolle: "fagkontor", extra: ["fagkontor": b])]
        }
        assertOneProblem(t, id: "kart:kontoret", contains: "mva")
    }

    // Rule 9
    func testRejectsWordLongerThanEighteen() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["folk"] = [self.person("sjef", x: 3, y: 2, rolle: "sjef", extra: ["tekst": ["Les skatteforvaltningsforskriften nå."]])] }
        assertOneProblem(t, id: "kart:kontoret", contains: "skatteforvaltningsforskriften")
    }

    func testRejectsLongWordInClientLines() throws {
        let t = try town(editing: "klienter/butikken.json") {
            var lines = $0["replikker"] as! [String: Any]
            lines["hilsen"] = ["Skatteforvaltningsforskriften!"]
            $0["replikker"] = lines
        }
        assertOneProblem(t, id: "klient:butikken", contains: "Skatteforvaltningsforskriften")
    }

    func testValidatorRequiresDiscoveredLine() throws {
        let t = try town(editing: "klienter/butikken.json") {
            var lines = $0["replikker"] as! [String: Any]
            lines["oppdagetFeil"] = [String]()
            $0["replikker"] = lines
        }
        assertOneProblem(t, id: "klient:butikken", contains: "oppdagetFeil")
        let long = try town(editing: "klienter/butikken.json") {
            var lines = $0["replikker"] as! [String: Any]
            lines["oppdagetFeil"] = ["Skatteforvaltningsforskriften!"]
            $0["replikker"] = lines
        }
        assertOneProblem(long, id: "klient:butikken", contains: "Skatteforvaltningsforskriften")
    }

    func testRejectsLongWordInClientName() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["navn"] = "Skatteforvaltningsforskriften AS" }
        assertOneProblem(t, id: "klient:butikken", contains: "Skatteforvaltningsforskriften")
    }

    func testRejectsLongFagkontorName() throws {
        let office: [String: Any] = ["id": "fk", "navn": "Avskrivningskontoret", "temaer": ["mva"]]
        let t = try town(editing: "kart/kontoret.json") { $0["folk"] = [self.person("f", x: 3, y: 2, rolle: "fagkontor", extra: ["fagkontor": office])] }
        assertOneProblem(t, id: "kart:kontoret", contains: "Avskrivningskontoret")
    }

    func testRejectsLongWordInMapName() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["navn"] = "Skatteforvaltningsforskriften" }
        assertOneProblem(t, id: "kart:kontoret", contains: "Skatteforvaltningsforskriften")
    }

    func testEighteenCharacterWordIsAllowed() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["navn"] = "Abcdefghijklmnopqr" }
        XCTAssertEqual(messages(t), [])
    }

    // Rule 10
    func testRejectsStaffWithoutPayDay() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["ansatte"] = 3 }
        assertOneProblem(t, id: "klient:butikken", contains: "lonnsdag")
    }

    func testRejectsPayDayWithoutStaff() throws {
        let t = try town(editing: "klienter/konsulenten.json") { $0["lonnsdag"] = 20 }
        assertOneProblem(t, id: "klient:konsulenten", contains: "lonnsdag")
    }

    func testRejectsPayDayAfterTwentyEighth() throws {
        let t = try town(editing: "klienter/butikken.json") { $0["ansatte"] = 3; $0["lonnsdag"] = 29 }
        assertOneProblem(t, id: "klient:butikken", contains: "lonnsdag")
    }

    // Rule 12
    func testRejectsMapWithoutBydel() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["bydel"] = nil }
        assertOneProblem(t, id: "kart:kontoret", contains: "bydel")
    }

    func testRejectsUnknownBydel() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["bydel"] = "finnes-ikke" }
        assertOneProblem(t, id: "kart:kontoret", contains: "finnes-ikke")
    }

    func testRejectsDistrictWithoutArrival() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["ankomst"] = nil }
        assertOneProblem(t, id: "kart:sentrum", contains: "ankomst")
    }

    func testRejectsArrivalOnWall() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["ankomst"] = ["x": 0, "y": 0] }
        assertOneProblem(t, id: "kart:sentrum", contains: "ankomst")
        let onPerson = try town(editing: "kart/sentrum.json") { $0["ankomst"] = ["x": 2, "y": 2] }
        assertOneProblem(onPerson, id: "kart:sentrum", contains: "ankomst")
    }

    func testRejectsFirstDistrictWithFullmakt() throws {
        let t = try town(editing: "kart/sentrum.json") { $0["fullmakt"] = "sentrum" }
        assertOneProblem(t, id: "kart:sentrum", contains: "fullmakt")
    }

    func testRejectsLaterDistrictWithoutFullmakt() throws {
        let t = try town(editing: "kart/havna.json") { $0["fullmakt"] = nil }
        assertOneProblem(t, id: "kart:havna", contains: "fullmakt")
        let wrong = try town(editing: "kart/havna.json") { $0["fullmakt"] = "sentrum" }
        assertOneProblem(wrong, id: "kart:havna", contains: "fullmakt")
    }

    func testRejectsGapInRekkefolge() throws {
        let t = try town(editing: "kart/havna.json") { $0["rekkefolge"] = 3 }
        assertOneProblem(t, id: "kart:havna", contains: "rekkefolge")
    }

    func testRejectsInteriorWithDistrictFields() throws {
        let t = try town(editing: "kart/kontoret.json") { $0["rekkefolge"] = 3 }
        assertOneProblem(t, id: "kart:kontoret", contains: "innendørskart")
    }

    func testRejectsOfficeOutsideFirstDistrict() throws {
        // The doors of the office then also cross a district border, so more than one message is right.
        let t = try town(editing: "kart/kontoret.json") { $0["bydel"] = "havna" }
        XCTAssertTrue(messages(t).contains { $0.hasPrefix("kart:kontoret") && $0.contains("bydel 1") }, messages(t).joined(separator: "\n"))
    }

    func testRejectsBackDoorBetweenDistricts() throws {
        // An interior of Sentrum with a door straight into Havna would pass the locked gate.
        let t = try town(editing: "kart/kontoret.json") { $0["dorer"] = [["x": 3, "y": 5, "til": "havna", "tilX": 4, "tilY": 6]] }
        assertOneProblem(t, id: "kart:kontoret", contains: "bakdør")
    }

    // Rule 13
    func testCoverageListsThemesWithoutOffice() throws {
        let problems = ContentValidator.validateTownCoverage(try town(), library: Self.library)
        XCTAssertEqual(problems.map(\.id), ["by:fagkontor"])
        let themeMessage = try XCTUnwrap(problems.first?.messages.first { $0.contains("uten fagkontor") })
        let withOffice: Set<String> = ["mva", "lonn"]
        for tema in Self.library.topics.map(\.id) {
            XCTAssertEqual(themeMessage.contains(tema), !withOffice.contains(tema), tema)
        }
    }

    func testCoverageNeedsTwoOfficesPerDistrict() throws {
        let problems = ContentValidator.validateTownCoverage(try town(), library: Self.library)
        let messages = problems.flatMap(\.messages)
        XCTAssertTrue(messages.contains { $0.contains("«havna»") && $0.contains("0 fagkontor") }, messages.joined(separator: "\n"))
        XCTAssertFalse(messages.contains { $0.contains("«sentrum»") }, messages.joined(separator: "\n"))
    }
}
