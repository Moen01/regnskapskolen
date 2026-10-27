#!/usr/bin/env swift
// Draws the app icon: a green squircle with a white "D | K" ledger mark, and writes
// Resources/AppIcon.icns through iconutil. Run from the repo root: swift scripts/make-icon.swift
import AppKit

let green = NSColor(red: 0x2f / 255, green: 0x5d / 255, blue: 0x50 / 255, alpha: 1)

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    // Apple's icon grid: the shape fills about 80 % of the canvas.
    let inset = s * 0.1
    let shape = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    green.setFill()
    NSBezierPath(roundedRect: shape, xRadius: shape.width * 0.22, yRadius: shape.width * 0.22).fill()

    NSColor.white.setFill()
    // The vertical rule between debet and kredit, and the ledger line under them.
    let rule = s * 0.028
    NSBezierPath(roundedRect: NSRect(x: s / 2 - rule / 2, y: s * 0.30, width: rule, height: s * 0.40), xRadius: rule / 2, yRadius: rule / 2).fill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.26, y: s * 0.30 - rule * 1.6, width: s * 0.48, height: rule), xRadius: rule / 2, yRadius: rule / 2).fill()

    let font = NSFont.systemFont(ofSize: s * 0.30, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    for (letter, center) in [("D", s * 0.38), ("K", s * 0.62)] {
        let text = NSAttributedString(string: letter, attributes: attributes)
        let bounds = text.size()
        text.draw(at: NSPoint(x: center - bounds.width / 2, y: s * 0.33))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { print("iconutil feilet"); exit(1) }
print("Skrev \(out.path)")
