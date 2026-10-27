import Foundation
import Security

/// A published build of Regnskapsskolen on GitHub Releases.
public struct AppRelease: Sendable, Hashable {
    public let tag: String            // "v0.2.0"
    public let name: String
    public let notes: String
    public let publishedAt: Date?
    public let url: URL               // the release page
    public let assetName: String?
    public let assetURL: URL?

    public init(tag: String, name: String, notes: String, publishedAt: Date?, url: URL, assetName: String?, assetURL: URL?) {
        self.tag = tag; self.name = name; self.notes = notes; self.publishedAt = publishedAt; self.url = url; self.assetName = assetName; self.assetURL = assetURL
    }

    public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
}

public enum UpdateError: Error, LocalizedError, Hashable, Sendable {
    case http(Int), noAsset, badArchive, notWritable(String)

    public var errorDescription: String? {
        switch self {
        case .http(let status): "GitHub svarte \(status). Prøv igjen senere."
        case .noAsset: "Utgivelsen har ingen app vedlagt ennå. Byggingen kan fortsatt pågå."
        case .badArchive: "Den nedlastede appen lot seg ikke pakke ut eller kontrollere."
        case .notWritable(let path): "Kan ikke bytte ut appen i \(path): mappen er skrivebeskyttet. Last ned den nye versjonen fra GitHub og dra den inn selv, eller be IT."
        }
    }
}

/// Updates the app from the public GitHub releases of Moen01/regnskapskolen over plain HTTPS: the
/// repo is public, and an accountant has no `gh`. The transport is injected so the tests run offline.
public struct AppUpdater: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias Download = @Sendable (URL) async throws -> URL

    public static let repo = "Moen01/regnskapskolen"
    public static let assetPrefix = "Regnskapsskolen"
    public static let releasesPage = URL(string: "https://github.com/Moen01/regnskapskolen/releases")!

    public let repo: String
    public let fetch: Fetch
    public let download: Download

    public init(repo: String = AppUpdater.repo,
                fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) },
                download: @escaping Download = { try await URLSession.shared.download(from: $0).0 }) {
        self.repo = repo; self.fetch = fetch; self.download = download
    }

    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// A local build from scripts/bundle.sh without a release version never updates itself, or the
    /// released app would replace the build being tested.
    public static var isDevelopmentBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "RegnskapsskolenDevBuild") as? Bool ?? false
    }

    public func latestRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Regnskapsskolen/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Nil when the repo has no release yet (404); throws `UpdateError.http` for other failures.
    public func latest() async throws -> AppRelease? {
        let (data, response) = try await fetch(latestRequest())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw UpdateError.http(status) }
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let tag = json["tag_name"]?.string, let page = json["html_url"]?.string.flatMap(URL.init(string:)) else { return nil }
        let asset = (json["assets"]?.array ?? []).first { ($0["name"]?.string ?? "").hasPrefix(Self.assetPrefix) && ($0["name"]?.string ?? "").hasSuffix(".zip") }
        return AppRelease(tag: tag, name: json["name"]?.string ?? tag, notes: json["body"]?.string ?? "",
                          publishedAt: json["published_at"]?.string.flatMap { Self.iso8601.date(from: $0) }, url: page,
                          assetName: asset?["name"]?.string, assetURL: asset?["browser_download_url"]?.string.flatMap(URL.init(string:)))
    }

    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()

    /// Downloads the release's zip, verifies it and swaps it in for `appPath`. The caller relaunches.
    public func install(_ release: AppRelease, over appPath: String = Bundle.main.bundlePath) async throws {
        guard let assetURL = release.assetURL, let assetName = release.assetName else { throw UpdateError.noAsset }
        let parent = (appPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else { throw UpdateError.notWritable(parent) }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("regnskapsskolen-update-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let downloaded = try await download(assetURL)
        let zip = work.appendingPathComponent(assetName)
        try FileManager.default.moveItem(at: downloaded, to: zip)
        try await Self.installArchive(zip.path, over: appPath)
    }

    /// Unpacks a zipped .app, verifies it, and swaps it in for `appPath`, keeping the old bundle as
    /// `.previous` until the new one is in place and putting it back when the swap fails.
    public static func installArchive(_ zipPath: String, over appPath: String) async throws {
        let work = (zipPath as NSString).deletingLastPathComponent
        let unpacked = (work as NSString).appendingPathComponent("unpacked-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(atPath: unpacked) }
        _ = try await ProcessRunner.output("/usr/bin/ditto", ["-x", "-k", zipPath, unpacked], timeout: 120)
        guard let app = try FileManager.default.contentsOfDirectory(atPath: unpacked).first(where: { $0.hasSuffix(".app") }) else { throw UpdateError.badArchive }
        let newApp = (unpacked as NSString).appendingPathComponent(app)

        // The bundle must be intact and signed before it replaces a working app. A Developer ID build
        // only accepts builds from its own team, so an ad hoc or foreign bundle cannot replace it.
        var args = ["--verify", "--deep", "--strict"]
        if let team = teamIdentifier(of: appPath) {
            args += ["-R", "=anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""]
        }
        let verify = try await ProcessRunner.run("/usr/bin/codesign", args + [newApp], timeout: 60)
        guard verify.succeeded else { throw UpdateError.badArchive }
        _ = try? await ProcessRunner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp], timeout: 30)

        let backup = appPath + ".previous"
        try? FileManager.default.removeItem(atPath: backup)
        try FileManager.default.moveItem(atPath: appPath, toPath: backup)
        do {
            try FileManager.default.moveItem(atPath: newApp, toPath: appPath)
            try? FileManager.default.removeItem(atPath: backup)
        } catch {
            try? FileManager.default.moveItem(atPath: backup, toPath: appPath)
            throw error
        }
    }

    /// The signing team of a bundle, or nil when it is ad hoc or unsigned (a local `make install`).
    public static func teamIdentifier(of path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Opens the app again once this process has quit.
    public static func relaunch(_ appPath: String = Bundle.main.bundlePath) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", relaunchCommand(appPath)]
        try? p.run()
    }

    /// The command `relaunch` runs.
    public static func relaunchCommand(_ appPath: String) -> String {
        "sleep 1; /usr/bin/open \(shellQuote(appPath))"
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// "0.10.0" > "0.9.3", number by number; a "-dev" suffix counts as 0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
