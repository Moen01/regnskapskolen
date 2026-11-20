import SwiftUI

/// A one-shot confetti burst in the Catacloud palette, ~2.2 s, drawn in a Canvas. Decorative only.
struct ConfettiView: View {
    private struct Piece {
        let x: Double
        let color: Color
        let size: Double
        let drift: Double
        let speed: Double
        let spin: Double
        let delay: Double
    }

    private static let palette = [0xF85C5C, 0xF5B04D, 0x3CBF9C, 0x4A5E9E, 0xED4A7B].map { Color(hex: UInt32($0)) }

    @State private var pieces: [Piece] = []
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let life = now - piece.delay
                    guard life > 0 else { continue }
                    let fall = life * piece.speed
                    guard fall < 1.3 else { continue }
                    let y = fall * (size.height + 40) - 20
                    let x = piece.x * size.width + sin(life * 3 + piece.x * 6) * piece.drift
                    let fade = fall > 1 ? max(0, 1 - (fall - 1) / 0.3) : 1
                    var layer = context
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(life * piece.spin))
                    layer.opacity = fade
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    layer.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if pieces.isEmpty { pieces = Self.make() }
            start = Date()
        }
    }

    private static func make() -> [Piece] {
        (0..<90).map { i in
            Piece(
                x: Double.random(in: 0...1),
                color: palette[i % palette.count],
                size: Double.random(in: 6...11),
                drift: Double.random(in: 8...26),
                speed: Double.random(in: 0.5...0.85),
                spin: Double.random(in: -6...6),
                delay: Double.random(in: 0...0.5)
            )
        }
    }
}
