import AppKit
import Foundation

let iconsetDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func renderIcon(px: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(px)
    let inset = size * 0.08
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.88, alpha: 1.0),
        NSColor(calibratedRed: 0.11, green: 0.64, blue: 0.56, alpha: 1.0)
    ])!
    grad.draw(in: path, angle: -45)

    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { dst in
            sym.draw(in: dst)
            NSColor.white.set()
            dst.fill(using: .sourceAtop)
            return true
        }
        let sw = sym.size.width
        let sh = sym.size.height
        let targetRect = NSRect(
            x: (size - sw) / 2.0,
            y: (size - sh) / 2.0,
            width: sw,
            height: sh
        )
        tinted.draw(in: targetRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: url)
    }
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    try renderIcon(px: px, to: iconsetDir.appendingPathComponent(name))
}
