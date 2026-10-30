import AppKit
import RegnskapKit
import SwiftUI

/// The pixel font «Press Start 2P» (OFL), 8 px per glyph (4 px in the dialog), or the system's
/// bold monospace when the file is missing. The app bundle registers it through
/// `ATSApplicationFontsPath`; a build run from the repo registers it here.
enum GBFont {
    static let name = "Press Start 2P"
    static let file = "PressStart2P-Regular.ttf"

    static func register() {
        guard !isAvailable else { return }
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts/\(file)"),
            ContentLocator.repoContent.deletingLastPathComponent().appendingPathComponent("Resources/Fonts/\(file)"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if isAvailable { return }
        }
    }

    static var isAvailable: Bool { NSFont(name: name, size: 8) != nil }

    static func font(scale: CGFloat) -> Font {
        isAvailable ? .custom(name, size: 8 * scale) : .system(size: 7 * scale, weight: .bold, design: .monospaced)
    }
}

/// Logical pixels per point: every Game Boy widget multiplies its sizes by this.
struct GBScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 4
}

extension EnvironmentValues {
    var gbScale: CGFloat {
        get { self[GBScaleKey.self] }
        set { self[GBScaleKey.self] = newValue }
    }
}
