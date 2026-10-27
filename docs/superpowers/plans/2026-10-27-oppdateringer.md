# Oppdateringer fra GitHub Releases: implementasjonsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Appen finner nyeste release på GitHub selv, viser en knapp når en nyere versjon finnes, laster ned, kontrollerer signaturen, bytter ut seg selv og starter på nytt; release-workflowen signerer og notariserer når hemmelighetene finnes.

**Architecture:** Mekanismen er Catacloud Dev sin (`AppUpdater` i Kit, `AppStore+Updates` i appen, Release-workflow på tag), med to avvik: HTTP mot det offentlige GitHub-API-et med `URLSession` i stedet for `gh`, og ingen automatisk installering. `AppUpdater` tar `fetch`/`download`-closures så alt unntatt selve prosesskallene (`ditto`, `codesign`, `xattr`, `open`) kan testes uten nett.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, XCTest, GitHub Actions (macos-latest), `codesign`/`notarytool`. Ingen nye avhengigheter.

**Spec:** `docs/superpowers/specs/2026-10-27-oppdateringer-design.md`

## Global Constraints

- `RegnskapKit` importerer aldri SwiftUI/AppKit (`Security` og `Foundation` er greit).
- Norsk bokmål i alt brukeren leser, med spesens tekster ordrett; kode, kommentarer og commit-meldinger på engelsk.
- Repo: `Moen01/regnskapskolen`. API: `https://api.github.com/repos/Moen01/regnskapskolen/releases/latest`, header `Accept: application/vnd.github+json`, `User-Agent: Regnskapsskolen/<versjon>`. Vedlegg: første `assets[].name` som begynner på `Regnskapsskolen` og slutter på `.zip`.
- Sjekk 30 s etter start, så hver 6. time; aldri i skjermbildemodus (`REGNSKAP_SCREENSHOTS`) og aldri i et utviklingsbygg (`RegnskapsskolenDevBuild` i Info.plist).
- Installering: `ditto -x -k`, `codesign --verify --deep --strict` (pluss `-R "=anchor apple generic and certificate leaf[subject.OU] = \"<team>\""` når den kjørende appen har et team), `xattr -dr com.apple.quarantine`, bytt med `.previous`, sett tilbake ved feil. Absolutte stier `/usr/bin/ditto`, `/usr/bin/codesign`, `/usr/bin/xattr`, `/usr/bin/open`.
- Ingen automatisk installering; bare knapp. Én macOS-varsling per ny versjon.
- Versjonssammenligning tall for tall; `-dev` teller som 0.
- Workflowen virker både med og uten hemmelighetene (`DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`); uten dem ad hoc som i dag. Utgivelsesnotater fra annotert tag (`--notes-from-tag`).
- Commit etter hver oppgave, melding på engelsk med trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Kjør `swift test` etter hver oppgave.

## Review Focus

1. Nettverksfeil eller GitHub-svar 403/5xx under en bakgrunnssjekk: ingen krasj, ingen tekst til brukeren; ved «Sjekk nå» vises feilen i én linje. Testes i oppgave 1 (`latest()` kaster `UpdateError.http(status)` / kaster videre).
2. Release uten zip (bygget pågår): knappen slått av, teksten «Utgivelsen har ingen app vedlagt ennå …». Testes i oppgave 1 og 2.
3. Appen ligger i en skrivebeskyttet mappe: `.notWritable` med spesens tekst, og den gamle appen står urørt. Testes i oppgave 2.
4. En zip som ikke er en signert app (manipulert eller ødelagt nedlasting): avvist, den gamle appen står urørt, `.previous` finnes ikke etterpå. Testes i oppgave 2.
5. Et utviklingsbygg eller en skjermbildekjøring må aldri bytte ut seg selv med en release. Oppgave 3 tester plist-flagget; oppgave 4 sperrer løkka på flagget og miljøvariabelen (bygg-verifisert).

---

### Task 1: `AppUpdater`: release-oppslag og versjonssammenligning

**Files:**
- Create: `Sources/RegnskapKit/Shell/AppUpdater.swift`
- Create: `Tests/RegnskapKitTests/Fixtures/github-release.json`
- Test: `Tests/RegnskapKitTests/AppUpdaterTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct AppRelease: Sendable, Hashable {
      public let tag: String            // "v0.2.0"
      public let name: String
      public let notes: String
      public let publishedAt: Date?
      public let url: URL               // html_url
      public let assetName: String?
      public let assetURL: URL?         // browser_download_url
      public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
  }
  public enum UpdateError: Error, LocalizedError, Hashable, Sendable {
      case http(Int), noAsset, badArchive, notWritable(String)
      public var errorDescription: String?
      // .http(s): "GitHub svarte \(s). Prøv igjen senere."
      // .noAsset: "Utgivelsen har ingen app vedlagt ennå. Byggingen kan fortsatt pågå."
      // .badArchive: "Den nedlastede appen lot seg ikke pakke ut eller kontrollere."
      // .notWritable(p): "Kan ikke bytte ut appen i \(p): mappen er skrivebeskyttet. Last ned den nye versjonen fra GitHub og dra den inn selv, eller be IT."
  }
  public struct AppUpdater: Sendable {
      public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
      public typealias Download = @Sendable (URL) async throws -> URL   // local file URL of the download
      public static let repo = "Moen01/regnskapskolen"
      public static let assetPrefix = "Regnskapsskolen"
      public static let releasesPage = URL(string: "https://github.com/Moen01/regnskapskolen/releases")!
      public let repo: String
      public let fetch: Fetch
      public let download: Download
      public init(repo: String = AppUpdater.repo, fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) },
                  download: @escaping Download = { try await URLSession.shared.download(from: $0).0 })
      public static var currentVersion: String      // CFBundleShortVersionString, "0.0.0" when missing
      public static var isDevelopmentBuild: Bool     // Info.plist RegnskapsskolenDevBuild == true
      public func latestRequest() -> URLRequest      // GET …/releases/latest with the two headers
      /// Nil when the repo has no release (404). Throws UpdateError.http for other non-2xx statuses.
      public func latest() async throws -> AppRelease?
      public static func isNewer(_ candidate: String, than current: String) -> Bool
  }
  ```
  JSON-feltene: `tag_name`, `name`, `body`, `published_at` (ISO 8601, parses med `ISO8601DateFormatter`, `nonisolated(unsafe) static let`), `html_url`, `assets[].name`, `assets[].browser_download_url`. Dekod med `JSONValue` som Catacloud Dev gjør, eller med en privat `Decodable`-struct; begge er greit.

- [ ] **Steg 1: Lag fiksturen `Tests/RegnskapKitTests/Fixtures/github-release.json`** (formen GitHub bruker, bare feltene over trenger innhold):

```json
{
  "tag_name": "v0.2.0",
  "name": "Regnskapsskolen 0.2.0",
  "body": "Bankavstemming i sandkassen.\n\n- Ny fane «Bank»\n- Casen bank-001",
  "published_at": "2026-10-27T18:00:00Z",
  "html_url": "https://github.com/Moen01/regnskapskolen/releases/tag/v0.2.0",
  "assets": [
    { "name": "Regnskapsskolen-0.2.0.zip", "browser_download_url": "https://github.com/Moen01/regnskapskolen/releases/download/v0.2.0/Regnskapsskolen-0.2.0.zip" }
  ]
}
```

- [ ] **Steg 2: Skriv testene**

```swift
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
        let release = try await XCTUnwrap(updater().latest())
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
        let release = try await XCTUnwrap(updater(body: body).latest())
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
```

- [ ] **Steg 3: Kjør testene, de skal feile**

Kjør: `swift test --filter AppUpdaterTests`
Forventet: kompileringsfeil, `AppUpdater` finnes ikke.

- [ ] **Steg 4: Implementer `AppUpdater.swift` (modellen, `latestRequest`, `latest`, `isNewer`, feiltekstene; `install`-delen kommer i oppgave 2)**

- [ ] **Steg 5: Kjør testene, de skal passere**

Kjør: `swift test --filter AppUpdaterTests`
Forventet: 6 tester, 0 feil.

- [ ] **Steg 6: Commit**

```bash
git add Sources/RegnskapKit/Shell/AppUpdater.swift Tests/RegnskapKitTests/Fixtures/github-release.json Tests/RegnskapKitTests/AppUpdaterTests.swift
git commit -m "feat(updates): look up the latest GitHub release and compare versions"
```

---

### Task 2: `AppUpdater`: nedlasting, kontroll, bytte og omstart

**Files:**
- Modify: `Sources/RegnskapKit/Shell/AppUpdater.swift`
- Test: `Tests/RegnskapKitTests/AppUpdaterTests.swift`

**Interfaces:**
- Consumes: oppgave 1.
- Produces (på `AppUpdater`):
  ```swift
  /// Downloads the release's zip, verifies it and swaps it in for `appPath`. The caller relaunches.
  public func install(_ release: AppRelease, over appPath: String = Bundle.main.bundlePath) async throws
  /// Unpacks a zipped .app, verifies its signature (same team as `appPath` when that app has one), removes quarantine, swaps it in with a `.previous` backup, restores on failure.
  public static func installArchive(_ zipPath: String, over appPath: String) async throws
  /// The signing team of a bundle; nil for ad hoc or unsigned.
  public static func teamIdentifier(of path: String) -> String?
  /// The command `relaunch` runs after this process exits.
  public static func relaunchCommand(_ appPath: String) -> String        // "sleep 1; /usr/bin/open '<quoted path>'"
  public static func relaunch(_ appPath: String = Bundle.main.bundlePath) // /bin/sh -c relaunchCommand, detached
  static func shellQuote(_ s: String) -> String                          // single-quoted, ' → '\''
  ```
  `install` kaster `.noAsset` uten `assetURL`, `.notWritable(parent)` når mappen appen ligger i ikke er skrivbar (`FileManager.isWritableFile`), ellers laster ned til en midlertidig mappe (`download(assetURL)` flyttes inn dit som `<assetName>`) og kaller `installArchive`. Prosessene kjøres gjennom `ProcessRunner.run`/`output` med absolutte stier.

- [ ] **Steg 1: Skriv testene** (legg til i `AppUpdaterTests`)

```swift
    /// A minimal, launchable app bundle: /bin/ls as the executable and a marker file to tell versions apart.
    func makeApp(at url: URL, marker: String, signed: Bool) throws {
        let macos = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/bin/ls", toPath: macos.appendingPathComponent("Dummy").path)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleExecutable</key><string>Dummy</string><key>CFBundleIdentifier</key><string>no.test.dummy</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
        """
        try plist.write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try marker.write(to: url.appendingPathComponent("Contents/Resources/marker.txt").path.withDirectoriesCreated(), atomically: true, encoding: .utf8)
        if signed {
            let result = try await ProcessRunner.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path], timeout: 60)
            XCTAssertTrue(result.succeeded, result.stderrString)
        }
    }

    func zip(_ app: URL) async throws -> String {
        let zip = app.deletingLastPathComponent().appendingPathComponent("Dummy.zip").path
        _ = try await ProcessRunner.output("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip], timeout: 60)
        return zip
    }

    func marker(_ app: URL) -> String { (try? String(contentsOf: app.appendingPathComponent("Contents/Resources/marker.txt"), encoding: .utf8)) ?? "" }

    func testInstallArchiveSwapsInASignedApp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)", isDirectory: true)
        let installed = dir.appendingPathComponent("Installed/Dummy.app"), fresh = dir.appendingPathComponent("New/Dummy.app")
        try await makeApp(at: installed, marker: "old", signed: true)
        try await makeApp(at: fresh, marker: "new", signed: true)
        try await AppUpdater.installArchive(try await zip(fresh), over: installed.path)
        XCTAssertEqual(marker(installed), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".previous"), "the backup is removed after a successful swap")
    }

    func testInstallArchiveRejectsAnUnsignedAppAndKeepsTheOld() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)", isDirectory: true)
        let installed = dir.appendingPathComponent("Installed/Dummy.app"), fresh = dir.appendingPathComponent("New/Dummy.app")
        try await makeApp(at: installed, marker: "old", signed: true)
        try await makeApp(at: fresh, marker: "new", signed: false)
        do { try await AppUpdater.installArchive(try await zip(fresh), over: installed.path); XCTFail("expected badArchive") }
        catch UpdateError.badArchive { }
        XCTAssertEqual(marker(installed), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".previous"))
    }

    func testInstallArchiveRejectsAZipWithoutAnApp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)", isDirectory: true)
        let installed = dir.appendingPathComponent("Installed/Dummy.app")
        try await makeApp(at: installed, marker: "old", signed: true)
        let folder = dir.appendingPathComponent("Junk"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        do { try await AppUpdater.installArchive(try await zip(folder), over: installed.path); XCTFail("expected badArchive") }
        catch UpdateError.badArchive { }
        XCTAssertEqual(marker(installed), "old")
    }

    func testInstallRefusesAReadOnlyFolderAndAMissingAsset() async throws {
        let release = AppRelease(tag: "v9.9.9", name: "x", notes: "", publishedAt: nil, url: URL(string: "https://example.com")!, assetName: nil, assetURL: nil)
        do { try await updater().install(release, over: "/tmp/whatever.app"); XCTFail("expected noAsset") } catch UpdateError.noAsset { }
        let withAsset = AppRelease(tag: "v9.9.9", name: "x", notes: "", publishedAt: nil, url: URL(string: "https://example.com")!, assetName: "Regnskapsskolen-9.9.9.zip", assetURL: URL(string: "https://example.com/a.zip")!)
        do { try await updater().install(withAsset, over: "/System/Library/CoreServices/Finder.app"); XCTFail("expected notWritable") }
        catch UpdateError.notWritable(let path) { XCTAssertEqual(path, "/System/Library/CoreServices") }
    }

    func testTeamIdentifierIsNilForAdHoc() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)", isDirectory: true)
        let app = dir.appendingPathComponent("Dummy.app")
        try await makeApp(at: app, marker: "x", signed: true)
        XCTAssertNil(AppUpdater.teamIdentifier(of: app.path))
    }

    func testRelaunchCommandQuotesThePath() {
        XCTAssertEqual(AppUpdater.relaunchCommand("/Applications/Regnskaps skolen.app"), "sleep 1; /usr/bin/open '/Applications/Regnskaps skolen.app'")
        XCTAssertEqual(AppUpdater.shellQuote("it's"), "'it'\\''s'")
    }
```

`makeApp` kaller `ProcessRunner.run` og må være `async throws`; `withDirectoriesCreated()` finnes ikke: lag mappen `Contents/Resources` med `createDirectory` før markøren skrives (den som bygger rydder i hjelperen).

- [ ] **Steg 2: Kjør testene, de skal feile**

Kjør: `swift test --filter AppUpdaterTests`
Forventet: kompileringsfeil, `installArchive` finnes ikke.

- [ ] **Steg 3: Implementer `install`, `installArchive`, `teamIdentifier`, `relaunchCommand`, `relaunch`, `shellQuote` etter Catacloud Dev sin `AppUpdater.swift` (`/Users/moen/Documents/catacloud-dev/Sources/CatacloudDevKit/Shell/AppUpdater.swift`), med absolutte stier og `UpdateError`**

- [ ] **Steg 4: Kjør testene, de skal passere**

Kjør: `swift test --filter AppUpdaterTests`
Forventet: 12 tester, 0 feil. Kjør også hele suiten: `swift test`.

- [ ] **Steg 5: Commit**

```bash
git add Sources/RegnskapKit/Shell/AppUpdater.swift Tests/RegnskapKitTests/AppUpdaterTests.swift
git commit -m "feat(updates): download, verify and swap in a release; relaunch"
```

---

### Task 3: Utviklingsbygg-flagget i `bundle.sh` og `notarize.sh`

**Files:**
- Modify: `scripts/bundle.sh`
- Create: `scripts/notarize.sh`

**Interfaces:** Produces: et bygg uten `APP_VERSION` har `RegnskapsskolenDevBuild = true` og versjon `<siste tag>-dev`; med `APP_VERSION` som i dag (ingen flagg). `notarize.sh <zip-navn>` notariserer `build/Regnskapsskolen.app`, stapler og zipper.

- [ ] **Steg 1: Endre `bundle.sh`**: etter `VERSION=…`-linjen: når `APP_VERSION` er tom, `/usr/libexec/PlistBuddy -c "Add :RegnskapsskolenDevBuild bool true"` og `VERSION="${VERSION}-dev"` før `Set :CFBundleShortVersionString`. Oppdater hodekommentaren (norsk, som i dag).

- [ ] **Steg 2: Skriv `scripts/notarize.sh`** som en kopi av `/Users/moen/Documents/catacloud-dev/scripts/notarize.sh` med `APP="build/Regnskapsskolen.app"`, usage `scripts/notarize.sh Regnskapsskolen-0.2.0.zip`, og norsk hodekommentar. `chmod +x`.

- [ ] **Steg 3: Verifiser**

Kjør:
```sh
./scripts/bundle.sh release && /usr/libexec/PlistBuddy -c "Print :RegnskapsskolenDevBuild" -c "Print :CFBundleShortVersionString" build/Regnskapsskolen.app/Contents/Info.plist
APP_VERSION=9.9.9 ./scripts/bundle.sh release && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Regnskapsskolen.app/Contents/Info.plist; /usr/libexec/PlistBuddy -c "Print :RegnskapsskolenDevBuild" build/Regnskapsskolen.app/Contents/Info.plist || echo "no dev flag, as expected"
zsh -n scripts/notarize.sh
```
Forventet: første kjøring skriver `true` og `0.1.0-dev`; andre skriver `9.9.9` og «no dev flag, as expected»; `zsh -n` er stille.

- [ ] **Steg 4: Commit**

```bash
git add scripts/bundle.sh scripts/notarize.sh
git commit -m "build: mark local builds as development builds; add the notarize script"
```

---

### Task 4: Oppdateringer i appen: innstilling, tilstand, løkke, omstart, varsel

**Files:**
- Modify: `Sources/Regnskapsskolen/App/AppSettings.swift` (`checkForUpdates`, `lastNotifiedUpdate`)
- Modify: `Sources/Regnskapsskolen/App/AppStore.swift` (lagrede egenskaper)
- Create: `Sources/Regnskapsskolen/App/AppStore+Updates.swift`
- Modify: `Sources/Regnskapsskolen/App/AppDelegate.swift` (`relaunch(into:)`, start løkka, åpne Innstillinger fra varselet)
- Modify: `Sources/Regnskapsskolen/App/Reminder.swift` (`notifyUpdate(version:)`, `onOpenUpdate`)

**Interfaces:**
- Consumes: oppgave 1–2.
- Produces:
  ```swift
  // AppSettings
  var checkForUpdates: Bool          // key "oppdateringer.sjekk", default true
  var lastNotifiedUpdate: String     // key "oppdateringer.varslet", the tag last announced
  // AppStore
  var availableUpdate: AppRelease?
  var updateState: String?
  var isUpdating = false
  var lastUpdateCheck = Date.distantPast
  @ObservationIgnored var updateLoop: Task<Void, Never>?
  // AppStore+Updates
  func checkForAppUpdate(userInitiated: Bool = false) async
  func installUpdate() async
  func startUpdateLoop()             // no-op in screenshot mode or a development build
  // Reminder
  var onOpenUpdate: (() -> Void)?
  func notifyUpdate(version: String) // title "Regnskapsskolen", body "Versjon \(version) er klar", identifier "oppdatering-\(version)"
  // AppDelegate
  func relaunch()                    // AppUpdater.relaunch(Bundle.main.bundlePath)
  ```
  `checkForAppUpdate`: dev-bygg → `updateState = "Dette er et utviklingsbygg og oppdaterer ikke seg selv."` og retur; `latest()` nil → ved `userInitiated` «Ingen utgivelser ennå.»; nyere → `availableUpdate`, og når taggen ≠ `settings.lastNotifiedUpdate` og ikke `userInitiated`: `Reminder.shared.notifyUpdate` og lagre taggen; ikke nyere → `availableUpdate = nil` og ved `userInitiated` «Du har nyeste versjon (\(currentVersion)).»; feil → ved `userInitiated` `error.localizedDescription`, ellers stille. `installUpdate`: guard `availableUpdate`, `!isUpdating`, ikke dev-bygg; «Laster ned \(version)…»; `AppUpdater().install`; «Installert. Starter på nytt…»; `AppDelegate.shared?.relaunch()`; lukk popover; `NSApp.terminate(nil)`; feil → `updateState = error.localizedDescription`, `isUpdating = false`. `startUpdateLoop`: `Task` som sover 30 s, så i løkke: når `settings.checkForUpdates` og `Date().timeIntervalSince(lastUpdateCheck) > 6 * 3600` → `checkForAppUpdate()`; sov 30 min. Kalles fra `applicationDidFinishLaunching` etter `store.start()`. `Reminder.didReceive`: identifier med prefiks `oppdatering-` → `onOpenUpdate` (delegaten setter den til `showMainWindow(section: .settings)`), ellers `onOpen` som før.

- [ ] **Steg 1: Implementer**

- [ ] **Steg 2: Bygg og test**

Kjør: `swift build && swift test`
Forventet: bygger uten advarsler; alle tester grønne.

- [ ] **Steg 3: Commit**

```bash
git add Sources/Regnskapsskolen/App
git commit -m "feat(app): check GitHub releases, install on request, notify once per version"
```

---

### Task 5: Innstillinger og popover

**Files:**
- Modify: `Sources/Regnskapsskolen/UI/Settings/SettingsView.swift`
- Modify: `Sources/Regnskapsskolen/UI/MenuBar/PopoverView.swift`

**Interfaces:** Consumes oppgave 4.

`SettingsView`: ny `Section("Oppdateringer")` rett før «Om»: `LabeledContent("Versjon") { Text(AppUpdater.currentVersion).monospacedDigit() }`; når `store.availableUpdate` finnes: `Label("Versjon \(update.version) er klar", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.skole)` med knappen **Oppdater og start på nytt** (`.borderedProminent`, `.tint(.skole)`, tittel «Oppdaterer…» mens `isUpdating`, slått av når `isUpdating` eller `assetURL == nil`), og notatene som `MarkdownText(update.notes).frame(maxHeight: 160)` når de ikke er tomme; `Text(updateState)` i `.caption .secondary`; rad med **Sjekk nå** (`checkForAppUpdate(userInitiated: true)`) og **Utgivelser på GitHub** (`NSWorkspace.shared.open(AppUpdater.releasesPage)`, `.borderless`); `Toggle("Se etter oppdateringer", isOn: $settings.checkForUpdates)`; i dev-bygg bare versjonen og teksten «Dette er et utviklingsbygg og oppdaterer ikke seg selv.». «Om»-seksjonen mister versjonslinjen.

`PopoverView`: mellom oppgavelisten og knapperaden, når `store.availableUpdate` finnes og det ikke er dev-bygg: `Button { Task { await store.installUpdate() } } label: { Label(store.isUpdating ? "Oppdaterer…" : "Oppdater til \(update.version)", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.skole).disabled(store.isUpdating || update.assetURL == nil)`.

- [ ] **Steg 1: Implementer**

- [ ] **Steg 2: Bygg og tegn**

Kjør: `make app && REGNSKAP_SCREENSHOTS=/tmp/shots build/Regnskapsskolen.app/Contents/MacOS/Regnskapsskolen`
Forventet: `/tmp/shots/settings.png` viser seksjonen «Oppdateringer» med versjon, «Sjekk nå», «Utgivelser på GitHub» og bryteren (et lokalt bygg er et dev-bygg: teksten om utviklingsbygg vises). `/tmp/shots/popover.png` er uendret (ingen oppdatering tilgjengelig).

- [ ] **Steg 3: Commit**

```bash
git add Sources/Regnskapsskolen/UI/Settings/SettingsView.swift Sources/Regnskapsskolen/UI/MenuBar/PopoverView.swift
git commit -m "feat(app): update button in Settings and the popover"
```

---

### Task 6: Release-workflow og dokumentasjon

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `README.md` («Installer fra zip» punkt 6; ny seksjon «Oppdateringer» etter «Bygg selv»)
- Create: `docs/releasing.md`
- Modify: `CLAUDE.md` (kommandotabellen)
- Modify: `docs/engineering-notes.md` hvis noe kostet tid

Andreas har sagt ja til at workflowen endres.

`release.yml` etter `swift test`:

```yaml
      - name: Decide whether to sign
        env:
          CERT_P12: ${{ secrets.DEVELOPER_ID_CERT_P12 }}
        run: echo "SIGNING=$([[ -n "$CERT_P12" ]] && echo yes || echo no)" >> "$GITHUB_ENV"

      - name: Import the signing certificate
        if: env.SIGNING == 'yes'
        env:
          CERT_P12: ${{ secrets.DEVELOPER_ID_CERT_P12 }}
          CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
        run: |   # as in catacloud-dev's release.yml: throwaway keychain, import, SIGN_IDENTITY → GITHUB_ENV

      - name: Build the app bundle
        run: APP_VERSION="${GITHUB_REF_NAME#v}" ./scripts/bundle.sh release    # SIGN_IDENTITY from env when signing

      - name: Notarise
        if: env.SIGNING == 'yes'
        env:
          NOTARY_KEY_P8: ${{ secrets.NOTARY_KEY_P8 }}
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
        run: |
          export NOTARY_KEY="$RUNNER_TEMP/notary.p8"
          echo "$NOTARY_KEY_P8" > "$NOTARY_KEY"
          ./scripts/notarize.sh "Regnskapsskolen-${GITHUB_REF_NAME#v}.zip"

      - name: Zip it
        if: env.SIGNING != 'yes'
        run: ditto -c -k --keepParent build/Regnskapsskolen.app "Regnskapsskolen-${GITHUB_REF_NAME#v}.zip"

      - name: Remove the signing keychain
        if: always() && env.SIGNING == 'yes'
        run: |
          security delete-keychain "$RUNNER_TEMP/signing.keychain-db" 2>/dev/null || true
          rm -f "$RUNNER_TEMP/notary.p8"

      - name: Publish the release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          ZIP="Regnskapsskolen-${GITHUB_REF_NAME#v}.zip"
          gh release create "$GITHUB_REF_NAME" "$ZIP" --title "Regnskapsskolen ${GITHUB_REF_NAME#v}" --notes-from-tag \
            || gh release upload "$GITHUB_REF_NAME" "$ZIP" --clobber
```

README «Oppdateringer» (bokmål): appen sjekker nyeste release 30 s etter start og hver 6. time; knappen i menylinjen og i Innstillinger; hva som lastes ned og kontrolleres; at en ad hoc-signert utgivelse bare kontrolleres for at bundelen er hel, og at Developer ID anbefales; hvordan man publiserer (`git tag -a vX.Y.Z -m "Regnskapsskolen X.Y.Z: <hva som er nytt>" && git push origin vX.Y.Z`, notatet blir utgivelsesnotatet i appen); tabellen over de fem hemmelighetene (som i Catacloud Dev sin README, oversatt). «Installer fra zip» får punkt 6: «Appen sier fra i menylinjen når en ny versjon finnes; du trykker, den bytter seg selv ut og starter på nytt.»

`docs/releasing.md`: tag → workflow → zip på releasen → appene finner den innen 6 timer; sjekkliste (`swift test`, skjermbilder, commit, annotert tag, `gh run watch`, `gh release view vX.Y.Z --json assets`); når CI feiler (aldri flytt en tag, neste patch); versjonstabell som starter med 0.1.0 (første zip) og den versjonen som får oppdateringsfunksjonen.

`CLAUDE.md` kommandotabellen: `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z   # release: CI bygger, signerer når hemmelighetene finnes, legger zip på releasen`.

- [ ] **Steg 1: Skriv workflowen og dokumentene**

- [ ] **Steg 2: Verifiser**

Kjør: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"` (eller `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'`), og `swift test`.
Forventet: «yaml ok»; grønt.

- [ ] **Steg 3: Commit**

```bash
git add .github/workflows/release.yml README.md docs/releasing.md CLAUDE.md docs/engineering-notes.md
git commit -m "ci+docs: sign and notarise releases when the secrets exist; document updates and releasing"
```
