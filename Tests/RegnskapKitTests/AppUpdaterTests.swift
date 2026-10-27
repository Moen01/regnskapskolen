import XCTest
@testable import RegnskapKit

final class AppUpdaterTests: XCTestCase {
    static let fixture = try! Data(contentsOf: Bundle.module.resourceURL!.appendingPathComponent("Fixtures/github-release.json"))

    func updater(status: Int = 200, body: Data = AppUpdaterTests.fixture, record: (@Sendable (URLRequest) -> Void)? = nil) -> AppUpdater {
        AppUpdater(fetch: { request in
            record?(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }, download: { _ in throw UpdateError.noAsset })
    }

    func testLatestParsesTheRelease() async throws {
        let found = try await updater().latest()
        let release = try XCTUnwrap(found)
        XCTAssertEqual(release.tag, "v0.2.0")
        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.name, "Regnskapsskolen 0.2.0")
        XCTAssertTrue(release.notes.contains("Bankavstemming"))
        XCTAssertEqual(release.publishedAt, ISO8601DateFormatter().date(from: "2026-10-27T18:00:00Z"))
        XCTAssertEqual(release.url.absoluteString, "https://github.com/Moen01/regnskapskolen/releases/tag/v0.2.0")
        XCTAssertEqual(release.assetName, "Regnskapsskolen-0.2.0.zip")
        XCTAssertEqual(release.assetURL?.lastPathComponent, "Regnskapsskolen-0.2.0.zip")
    }

    func testLatestSendsTheGitHubRequest() async throws {
        let seen = Recorder()
        _ = try await updater(record: { seen.set($0) }).latest()
        let request = try XCTUnwrap(seen.request)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/Moen01/regnskapskolen/releases/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Regnskapsskolen/\(AppUpdater.currentVersion)")
    }

    func testNoReleaseIsNilAndOtherErrorsThrow() async throws {
        let none = try await updater(status: 404, body: Data("{}".utf8)).latest()
        XCTAssertNil(none)
        do { _ = try await updater(status: 403, body: Data("{}".utf8)).latest(); XCTFail("expected http error") }
        catch UpdateError.http(let status) { XCTAssertEqual(status, 403) }
        let offline = AppUpdater(fetch: { _ in throw URLError(.notConnectedToInternet) }, download: { _ in throw UpdateError.noAsset })
        do { _ = try await offline.latest(); XCTFail("expected the transport error") } catch is URLError { }
    }

    func testAReleaseWithoutAZipHasNoAsset() async throws {
        let body = Data(#"{"tag_name":"v0.3.0","name":"x","body":"","html_url":"https://example.com","assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"}]}"#.utf8)
        let found = try await updater(body: body).latest()
        let release = try XCTUnwrap(found)
        XCTAssertNil(release.assetName)
        XCTAssertNil(release.assetURL)
        XCTAssertNil(release.publishedAt)
    }

    func testIsNewerComparesNumberByNumber() {
        XCTAssertTrue(AppUpdater.isNewer("0.10.0", than: "0.9.3"))
        XCTAssertTrue(AppUpdater.isNewer("0.2.0", than: "0.1.0-dev"))
        XCTAssertFalse(AppUpdater.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(AppUpdater.isNewer("1.0.0-dev", than: "1.0.0"))
        XCTAssertFalse(AppUpdater.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertTrue(AppUpdater.isNewer("1.0.0.1", than: "1.0.0"))
    }

    func testErrorTextsAreNorwegian() {
        XCTAssertEqual(UpdateError.noAsset.errorDescription, "Utgivelsen har ingen app vedlagt ennå. Byggingen kan fortsatt pågå.")
        XCTAssertEqual(UpdateError.badArchive.errorDescription, "Den nedlastede appen lot seg ikke pakke ut eller kontrollere.")
        XCTAssertEqual(UpdateError.notWritable("/Applications").errorDescription, "Kan ikke bytte ut appen i /Applications: mappen er skrivebeskyttet. Last ned den nye versjonen fra GitHub og dra den inn selv, eller be IT.")
        XCTAssertEqual(UpdateError.http(503).errorDescription, "GitHub svarte 503. Prøv igjen senere.")
    }
}

/// A tiny lock box so the @Sendable fetch closure can hand the request back to the test.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var request: URLRequest? { lock.withLock { stored } }
    func set(_ r: URLRequest) { lock.withLock { stored = r } }
}
