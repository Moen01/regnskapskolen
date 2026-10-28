import AppKit
import RegnskapKit
import SwiftUI

/// The four greens of the original Game Boy screen.
enum GBPalette {
    static let darkest = Color(red: 0x0f / 255, green: 0x38 / 255, blue: 0x0f / 255)
    static let dark = Color(red: 0x30 / 255, green: 0x62 / 255, blue: 0x30 / 255)
    static let light = Color(red: 0x8b / 255, green: 0xac / 255, blue: 0x0f / 255)
    static let lightest = Color(red: 0x9b / 255, green: 0xbc / 255, blue: 0x0f / 255)
    static let bezel = Color(white: 0.23)

    /// A sprite's palette slot: 0 transparent, 1 outline, 2 body, 3 eye.
    static func sprite(_ slot: UInt8) -> Color? {
        switch slot {
        case 1: darkest
        case 2: dark
        case 3: lightest
        default: nil
        }
    }
}

/// The pixel font «Press Start 2P» (OFL), 8 px per glyph, or the system's bold monospace when
/// the file is missing. The app bundle registers it through `ATSApplicationFontsPath`; a build
/// run from the repo registers it here.
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
