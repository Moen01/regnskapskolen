import SwiftUI

/// The playful theme's figure: a flat geometric accountant in a suit with a briefcase (mockup A1).
/// Drawn in a 120×120 space and scaled, so it needs no image assets. The suit follows the theme accent.
struct AccountantFigure: View {
    enum Pose { case standing, celebrating }

    @Environment(\.appTheme) private var theme
    var pose: Pose = .standing
    var size: CGFloat = 96

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 120
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }

            let suit = theme.isPlayful ? theme.accent : Color(hex: 0x4A5E9E)
            let skin = Color(hex: 0xE8B48B)
            let hair = Color(hex: 0x2C2A26)
            let tie = Color(hex: 0xF5B04D)
            let bag = Color(hex: 0x8A7F6F)
            let dark = Color(hex: 0x2C2A26)

            context.fill(Path(ellipseIn: CGRect(x: 26 * s, y: 105 * s, width: 68 * s, height: 10 * s)), with: .color(.black.opacity(0.07)))
            context.fill(rrect(50, 86, 7, 20, 3), with: .color(dark))
            context.fill(rrect(63, 86, 7, 20, 3), with: .color(dark))

            var leftArm = Path(), rightArm = Path()
            if pose == .celebrating {
                leftArm.move(to: pt(44, 58)); leftArm.addLine(to: pt(32, 40))
                rightArm.move(to: pt(76, 58)); rightArm.addLine(to: pt(88, 40))
            } else {
                leftArm.move(to: pt(44, 58)); leftArm.addLine(to: pt(38, 76))
                rightArm.move(to: pt(76, 58)); rightArm.addLine(to: pt(82, 76))
            }
            let armStroke = StrokeStyle(lineWidth: 7 * s, lineCap: .round)
            context.stroke(leftArm, with: .color(suit), style: armStroke)
            context.stroke(rightArm, with: .color(suit), style: armStroke)
            if pose == .celebrating {
                context.fill(dot(32, 40, 4.5), with: .color(skin))
                context.fill(dot(88, 40, 4.5), with: .color(skin))
            }

            context.fill(rrect(42, 48, 36, 42, 13), with: .color(suit))
            var tiePath = Path()
            tiePath.move(to: pt(60, 52)); tiePath.addLine(to: pt(56, 57))
            tiePath.addLine(to: pt(60, 72)); tiePath.addLine(to: pt(64, 57)); tiePath.closeSubpath()
            context.fill(tiePath, with: .color(tie))

            context.fill(dot(60, 29, 15), with: .color(hair))
            context.fill(dot(60, 33, 14), with: .color(skin))
            context.fill(dot(54.5, 32, 1.8), with: .color(dark))
            context.fill(dot(65.5, 32, 1.8), with: .color(dark))
            var smile = Path()
            smile.move(to: pt(55, 38))
            smile.addQuadCurve(to: pt(65, 38), control: pt(60, pose == .celebrating ? 44 : 42))
            context.stroke(smile, with: .color(dark), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))

            if pose == .standing {
                context.fill(rrect(72, 76, 24, 17, 3), with: .color(bag))
                var handle = Path()
                handle.move(to: pt(80, 76)); handle.addQuadCurve(to: pt(88, 76), control: pt(84, 69))
                context.stroke(handle, with: .color(bag), style: StrokeStyle(lineWidth: 3 * s))
                var seam = Path()
                seam.move(to: pt(72, 84)); seam.addLine(to: pt(96, 84))
                context.stroke(seam, with: .color(Color(hex: 0x6B6055)), style: StrokeStyle(lineWidth: 2 * s))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
