import RegnskapKit
import SwiftUI

/// The handheld: a dark bezel around a 160 × 144 logical screen scaled by a whole number (3–5)
/// that fits the window. Keys arrive as `GameKey`; clicks anywhere give the screen focus again.
struct GBScreen<Content: View>: View {
    static var width: CGFloat { 160 }
    static var height: CGFloat { 144 }
    static var minScale: CGFloat { 3 }
    static var maxScale: CGFloat { 5 }
    static var margin: CGFloat { 48 }

    let onKey: (GameKey) -> Void
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool

    init(onKey: @escaping (GameKey) -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onKey = onKey
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let raw = floor(min((geometry.size.width - Self.margin) / Self.width, (geometry.size.height - Self.margin) / Self.height))
            if raw < Self.minScale {
                Text("Gjør vinduet større.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let scale = min(Self.maxScale, raw)
                ZStack(alignment: .topLeading) {
                    content()
                }
                .frame(width: Self.width * scale, height: Self.height * scale, alignment: .topLeading)
                .background(GBPalette.lightest)
                .clipped()
                .environment(\.gbScale, scale)
                .font(GBFont.font(scale: scale))
                .padding(6 * scale)
                .background(GBPalette.bezel, in: RoundedRectangle(cornerRadius: 3 * scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onAppear { focused = true }
                .onTapGesture { focused = true }
                .onKeyPress(phases: .down) { press in
                    guard let key = Self.key(for: press) else { return .ignored }
                    onKey(key)
                    return .handled
                }
            }
        }
    }

    private static func key(for press: KeyPress) -> GameKey? {
        switch press.key {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .return: return .a
        case .escape: return .b
        case .tab: return .tab
        case .delete: return .delete
        default: break
        }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
              let character = press.characters.first, press.characters.count == 1,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character == " " else { return nil }
        return .character(character)
    }
}
