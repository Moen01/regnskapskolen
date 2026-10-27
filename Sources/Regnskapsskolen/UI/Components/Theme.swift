import SwiftUI

extension Color {
    static let debet = Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xa8 / 255)
    static let kredit = Color(red: 0xb4 / 255, green: 0x53 / 255, blue: 0x09 / 255)
    static let skole = Color(red: 0x2f / 255, green: 0x5d / 255, blue: 0x50 / 255)
    static let ok = Color(red: 0x2f / 255, green: 0x7d / 255, blue: 0x4f / 255)
    static let bad = Color(red: 0xb4 / 255, green: 0x23 / 255, blue: 0x18 / 255)
    static let warn = Color(red: 0x8a / 255, green: 0x5a / 255, blue: 0x00 / 255)
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule()).foregroundStyle(color)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
        }
    }
}
