import RegnskapKit
import SwiftUI

/// Sizes in logical pixels; `gbScale` turns them into points.
private extension View {
    func gbOffset(x: CGFloat, y: CGFloat, scale: CGFloat) -> some View {
        offset(x: x * scale, y: y * scale)
    }
}

/// A box with the double border of the Game Boy dialogs, placed at logical px on the screen.
struct GBBox<Content: View>: View {
    @Environment(\.gbScale) private var scale
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    var padding: CGFloat = 4
    @ViewBuilder let content: () -> Content

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, padding: CGFloat = 4, @ViewBuilder content: @escaping () -> Content) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.padding = padding; self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(GBPalette.darkest)
            Rectangle().fill(GBPalette.lightest).padding(1 * scale)
            Rectangle().strokeBorder(GBPalette.darkest, lineWidth: 1 * scale).padding(2 * scale)
            content().padding(padding * scale)
        }
        .frame(width: width * scale, height: height * scale)
        .clipped()
        .gbOffset(x: x, y: y, scale: scale)
    }
}

/// One line of text in the pixel font.
struct GBText: View {
    @Environment(\.gbScale) private var scale
    let text: String
    var color: Color = GBPalette.darkest

    init(_ text: String, color: Color = GBPalette.darkest) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(height: 8 * scale)
    }
}

/// An HP-style bar: an outlined box that drains from the right. `width` in logical px.
struct GBBar: View {
    @Environment(\.gbScale) private var scale
    let value: Double
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().strokeBorder(GBPalette.darkest, lineWidth: 1 * scale)
            Rectangle().fill(GBPalette.darkest)
                .frame(width: max(0, (width - 4) * scale * min(1, max(0, value))))
                .padding(2 * scale)
        }
        .frame(width: width * scale, height: 6 * scale)
        .animation(.linear(duration: 0.6), value: value)
    }
}

/// Rows with a cursor. Each row is 12 px high and clickable; only `visible` rows are drawn.
struct GBList: View {
    @Environment(\.gbScale) private var scale
    let rows: [PanelRow]
    let cursor: Int
    let visible: Range<Int>
    let onClick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible), id: \.self) { index in
                Button { onClick(index) } label: {
                    HStack(spacing: 0) {
                        GBText(index == cursor ? "▶" : " ").frame(width: 8 * scale)
                        GBText(rows[index].text)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 12 * scale)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rows[index].full ?? rows[index].text)
            }
        }
    }
}

/// `SVAR: 2 500_` with a caret that blinks.
struct GBEntry: View {
    @Environment(\.gbScale) private var scale
    let label: String
    let text: String
    @State private var caretOn = true

    var body: some View {
        HStack(spacing: 0) {
            GBText(label)
            GBText(" " + text + (caretOn ? "_" : " "))
        }
        .frame(height: 12 * scale)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                caretOn.toggle()
            }
        }
    }
}

/// A `PixelSprite` drawn with `pixel` logical px per sprite pixel, nearest-neighbour by construction.
struct GBSprite: View {
    @Environment(\.gbScale) private var scale
    let sprite: PixelSprite
    var pixel: CGFloat = 3

    init(_ sprite: PixelSprite, pixel: CGFloat = 3) {
        self.sprite = sprite
        self.pixel = pixel
    }

    var body: some View {
        Canvas { context, _ in
            let size = pixel * scale
            for (y, row) in sprite.pixels.enumerated() {
                for (x, slot) in row.enumerated() {
                    guard let color = GBPalette.sprite(slot) else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * size, y: CGFloat(y) * size, width: size, height: size)), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(sprite.width) * pixel * scale, height: CGFloat(sprite.height) * pixel * scale)
    }
}

/// Places a view at logical px on the screen.
struct GBAt<Content: View>: View {
    @Environment(\.gbScale) private var scale
    let x: CGFloat
    let y: CGFloat
    @ViewBuilder let content: () -> Content

    init(x: CGFloat, y: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.x = x; self.y = y; self.content = content
    }

    var body: some View {
        content().gbOffset(x: x, y: y, scale: scale)
    }
}
