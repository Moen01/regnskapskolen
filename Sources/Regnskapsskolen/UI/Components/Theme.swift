import AppKit
import SwiftUI

extension Color {
    static let debet = Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xa8 / 255)
    static let kredit = Color(red: 0xb4 / 255, green: 0x53 / 255, blue: 0x09 / 255)
    static let skole = Color(red: 0x2f / 255, green: 0x5d / 255, blue: 0x50 / 255)
    static let ok = Color(red: 0x2f / 255, green: 0x7d / 255, blue: 0x4f / 255)
    static let bad = Color(red: 0xb4 / 255, green: 0x23 / 255, blue: 0x18 / 255)
    static let warn = Color(red: 0x8a / 255, green: 0x5a / 255, blue: 0x00 / 255)
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct Pill: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var color: Color = .secondary
    var body: some View {
        // The brand-green default follows the theme's accent; explicit status colors stay as passed.
        let shown = theme.isPlayful && color == .skole ? theme.accent : color
        Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(shown.opacity(0.12), in: Capsule()).foregroundStyle(shown)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold)).themedHeading()
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
        }
    }
}
