import Foundation

/// Where the content folder (`Innhold/`) is. Checked in order: the `REGNSKAP_INNHOLD` variable, the
/// folder from Settings, the copy inside the app bundle, and finally the repo this source sits in
/// (for `swift run` and the tests). A folder counts when it holds `temaer.json`.
public enum ContentLocator {
    public static let marker = "temaer.json"

    public static func find(settingsPath: String?, environment: [String: String] = ProcessInfo.processInfo.environment,
                            bundleResources: URL? = Bundle.main.resourceURL) -> URL? {
        var candidates: [URL] = []
        if let env = environment["REGNSKAP_INNHOLD"], !env.isEmpty { candidates.append(URL(fileURLWithPath: env, isDirectory: true)) }
        if let settingsPath, !settingsPath.isEmpty { candidates.append(URL(fileURLWithPath: settingsPath, isDirectory: true)) }
        if let bundleResources { candidates.append(bundleResources.appendingPathComponent("Innhold", isDirectory: true)) }
        candidates.append(repoContent)
        return candidates.first(where: isContentFolder)
    }

    public static func isContentFolder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(marker).path)
    }

    /// `Innhold/` next to `Package.swift`, found by walking up from this file.
    public static let repoContent: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Innhold", isDirectory: true)
            if isContentFolder(candidate) { return candidate.standardizedFileURL }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "Innhold", isDirectory: true)
    }()

    /// `~/Library/Application Support/Regnskapsskolen`, created on first use.
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Regnskapsskolen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// JSON numbers decoded through `Double` lose precision (14.1 becomes 14.100000000000001); going
/// through the number's shortest text keeps the value an accountant wrote.
extension Decimal {
    public init(lossless double: Double) {
        self = Decimal(string: String(double), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(double)
    }
}

/// A `Decimal` field that decodes losslessly from a JSON number or a Norwegian amount string.
@propertyWrapper
public struct Amount: Codable, Hashable, Sendable {
    public var wrappedValue: Decimal
    public init(wrappedValue: Decimal) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { wrappedValue = Decimal(lossless: d); return }
        let s = try c.decode(String.self)
        guard let value = NorwegianFormat.parseAmount(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Ikke et tall: \(s)")
        }
        wrappedValue = value
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(NSDecimalNumber(decimal: wrappedValue).doubleValue)
    }
}
