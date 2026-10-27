import XCTest
@testable import RegnskapKit

final class RatesTests: XCTestCase {
    func testLoadsRates() throws {
        let rates = try Rates(url: ContentLocator.repoContent.appendingPathComponent("satser.json"))
        XCTAssertEqual(rates.mva(kode: "25")?.prosent, 25)
        XCTAssertEqual(rates.mva(kode: "15")?.prosent, 15)
        XCTAssertEqual(rates.mva(kode: "12")?.prosent, 12)
        XCTAssertEqual(rates.mva(kode: "0")?.prosent, 0)
        XCTAssertEqual(rates.mva(kode: "0")?.fradrag, true)
        XCTAssertNil(rates.mva(kode: "unntatt")?.prosent)
        XCTAssertEqual(rates.mva(kode: "unntatt")?.fradrag, false)
        XCTAssertEqual(rates.mva(kode: "omvendt")?.prosent, 25)
        XCTAssertEqual(rates.mvaRegistreringsgrense, 50000)
        XCTAssertEqual(rates.mvaTerminer.count, 6)
        XCTAssertEqual(rates.mvaTerminer[2].frist.dag, 31)
        XCTAssertEqual(rates.mvaTerminer[2].frist.maaned, 8)
        XCTAssertEqual(rates.saldogruppe("d")?.prosent, 20)
        XCTAssertEqual(rates.saldogruppe("a")?.prosent, 30)
        XCTAssertEqual(rates.driftsmiddel.grense, 30000)
        XCTAssertEqual(rates.driftsmiddel.levetidAar, 3)
        XCTAssertEqual(rates.aga(sone: "1")?.prosent, Decimal(string: "14.1"))
        XCTAssertEqual(rates.feriepenger.lovfestet, Decimal(string: "10.2"))
        XCTAssertEqual(rates.feriepenger.tariff, 12)
        XCTAssertEqual(rates.oppbevaring.primaerAar, 5)
        XCTAssertEqual(rates.oppbevaring.sekundaerAar, Decimal(string: "3.5"))
        XCTAssertEqual(rates.forskuddstrekk.gjelderFra, DayKey(string: "2026-01-01"))
        XCTAssertEqual(rates.forsinkelsesrente(on: DayKey(string: "2026-03-01")!), 12)
        XCTAssertEqual(rates.forsinkelsesrente(on: DayKey(string: "2026-09-01")!), Decimal(string: "12.25"))
        XCTAssertEqual(rates.representasjon.bevertningPerPerson, 592)
        XCTAssertFalse(rates.kilder.isEmpty)
    }

    func testTopics() throws {
        let topics = try Topics(url: ContentLocator.repoContent.appendingPathComponent("temaer.json"))
        XCTAssertEqual(topics.all.count, 12)
        XCTAssertEqual(topics.all.first?.id, "grunnlag")
        XCTAssertEqual(topics.all.map(\.rekkefolge), Array(1...12))
        XCTAssertNotNil(topics.topic("mva"))
        XCTAssertNil(topics.topic("nope"))
    }

    func testRepoContentLocatorFindsTemaer() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ContentLocator.repoContent.appendingPathComponent("temaer.json").path))
        XCTAssertEqual(ContentLocator.find(settingsPath: nil, environment: [:], bundleResources: nil), ContentLocator.repoContent)
        XCTAssertEqual(ContentLocator.find(settingsPath: "/nonexistent/x", environment: ["REGNSKAP_INNHOLD": "/also/nonexistent"], bundleResources: nil), ContentLocator.repoContent)
        XCTAssertEqual(ContentLocator.find(settingsPath: ContentLocator.repoContent.path, environment: [:], bundleResources: nil), ContentLocator.repoContent)
    }
}
