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
    var fill: Color = GBTheme.boxFill
    @ViewBuilder let content: () -> Content

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, padding: CGFloat = 4, fill: Color = GBTheme.boxFill,
         @ViewBuilder content: @escaping () -> Content) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.padding = padding; self.fill = fill; self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(GBTheme.boxBorder)
            Rectangle().fill(fill).padding(1 * scale)
            Rectangle().strokeBorder(GBTheme.boxBorder, lineWidth: 1 * scale).padding(2 * scale)
            content().padding(padding * scale)
        }
        .frame(width: width * scale, height: height * scale)
        .clipped()
        .gbOffset(x: x, y: y, scale: scale)
    }
}

/// The two letter sizes: 8 px for titles and name boxes, 4 px for the dialog box and list rows.
enum GBTextSize {
    case normal, small

    /// Logical px per glyph, both ways.
    var pixels: CGFloat {
        switch self {
        case .normal: 8
        case .small: CGFloat(DialogBox.glyph)
        }
    }
}

/// One line of text in the pixel font.
struct GBText: View {
    @Environment(\.gbScale) private var scale
    let text: String
    var size: GBTextSize = .normal
    var color: Color = GBTheme.text

    init(_ text: String, size: GBTextSize = .normal, color: Color = GBTheme.text) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(String(text.map { CapitalAccent.letters[$0]?.base ?? $0 }))
            .font(GBFont.font(scale: scale * size.pixels / 8))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(height: size.pixels * scale)
            .overlay(alignment: .topLeading) { accents }
            .accessibilityLabel(text)
    }

    /// The accents of the capitals in `CapitalAccent`, in font pixels (an eighth of a glyph) over
    /// the base letter. The font is monospaced, so the nth character sits at n cells.
    private var accents: some View {
        Canvas { context, _ in
            let pixel = size.pixels / 8 * scale
            for (index, character) in text.enumerated() {
                guard let accent = CapitalAccent.letters[character] else { continue }
                for (row, line) in accent.rows.enumerated() {
                    for (column, mark) in line.enumerated() where mark == "#" {
                        let x = CGFloat(index * 8 + column) * pixel
                        let y = CGFloat(CapitalAccent.headroom - CapitalAccent.lift + row) * pixel
                        context.fill(Path(CGRect(x: x, y: y, width: pixel, height: pixel)), with: .color(color))
                    }
                }
            }
        }
        // A canvas draws only inside its own frame, so it reaches `headroom` font pixels above the text.
        .frame(width: CGFloat(text.count) * size.pixels * scale, height: size.pixels * scale * CGFloat(8 + CapitalAccent.headroom) / 8)
        .offset(y: -size.pixels * scale * CGFloat(CapitalAccent.headroom) / 8)
        .allowsHitTesting(false)
    }
}

/// Press Start 2P squeezes an accented capital into the cap height: the accent takes the top rows
/// and the letter shrinks to the height of a small letter, so at 4 px É reads as é, Ö as ö and Å
/// loses its ring. These are drawn as the full base letter with the accent in pixels above it.
/// Ø and Æ have no accent and keep the font's glyph.
private enum CapitalAccent {
    /// Font pixels the canvas reaches above the text.
    static let headroom = 4
    /// The accent's top row, in font pixels above the letter: two rows, then one row of air.
    static let lift = 3

    static let letters: [Character: (base: Character, rows: [String])] = [
        "Å": ("A", ["..###..", "..#.#.."]),
        "Á": ("A", ["....#..", "...#..."]),
        "Ä": ("A", ["", ".##.##."]),
        "É": ("E", ["....#..", "...#..."]),
        "È": ("E", ["..#....", "...#..."]),
        "Ê": ("E", ["...#...", "..#.#.."]),
        "Ö": ("O", ["", ".##.##."]),
        "Ü": ("U", ["", ".##.##."]),
    ]
}

/// An HP-style bar: an outlined box that drains from the right. `width` in logical px. Without a
/// `tint` the bar is the client's money: green, amber under half, red under a fifth.
struct GBBar: View {
    @Environment(\.gbScale) private var scale
    let value: Double
    let width: CGFloat
    var tint: Color? = nil

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().strokeBorder(GBTheme.boxBorder, lineWidth: 1 * scale)
            Rectangle().fill(tint ?? GBTheme.hp(value))
                .frame(width: max(0, (width - 4) * scale * min(1, max(0, value))))
                .padding(2 * scale)
        }
        .frame(width: width * scale, height: 6 * scale)
        .animation(.linear(duration: 0.6), value: value)
    }
}

/// Rows with a cursor, in 4 px letters (`ListBox`). Each row is `ListBox.rowHeight` px high and
/// clickable across its whole width; only `visible` rows are drawn.
struct GBList: View {
    @Environment(\.gbScale) private var scale
    let rows: [PanelRow]
    let cursor: Int
    let visible: Range<Int>
    /// A row drawn inverted: the line that just hit.
    var highlight: Int? = nil
    let onClick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible), id: \.self) { index in
                let hit = index == highlight
                // A marked row is dimmed: locked, done, or otherwise not the thing to pick next.
                let color = hit ? GBTheme.highlightText : (rows[index].marked ? GBTheme.textDim : GBTheme.text)
                Button { onClick(index) } label: {
                    HStack(spacing: 0) {
                        GBText(index == cursor ? "▶" : " ", size: .small, color: hit ? color : GBTheme.cursor)
                            .frame(width: CGFloat(ListBox.glyph) * scale)
                        GBText(rows[index].text, size: .small, color: color)
                        Spacer(minLength: 0)
                    }
                    .frame(height: CGFloat(ListBox.rowHeight) * scale)
                    .background(hit ? GBTheme.highlight : .clear)
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

/// A `PixelSprite` in its palette, `pixel` logical px per sprite pixel, nearest-neighbour by construction.
struct GBSprite: View {
    @Environment(\.gbScale) private var scale
    let sprite: PixelSprite
    let palette: SpritePalette
    var pixel: CGFloat = 3

    init(_ sprite: PixelSprite, palette: SpritePalette, pixel: CGFloat = 3) {
        self.sprite = sprite
        self.palette = palette
        self.pixel = pixel
    }

    var body: some View {
        Canvas { context, _ in
            let size = pixel * scale
            for (y, row) in sprite.pixels.enumerated() {
                for (x, slot) in row.enumerated() {
                    guard let color = palette.color(slot) else { continue }
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
