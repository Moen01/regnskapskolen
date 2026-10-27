import Foundation

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
