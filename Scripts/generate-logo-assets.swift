import AppKit
import Foundation

struct IconSize {
    let filename: String
    let pixels: Int
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDirectory = root
    .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let webIconURL = root.appendingPathComponent("web/assets/shuo-icon.png")

let iconSizes = [
    IconSize(filename: "Icon-16.png", pixels: 16),
    IconSize(filename: "Icon-16@2x.png", pixels: 32),
    IconSize(filename: "Icon-32.png", pixels: 32),
    IconSize(filename: "Icon-32@2x.png", pixels: 64),
    IconSize(filename: "Icon-128.png", pixels: 128),
    IconSize(filename: "Icon-128@2x.png", pixels: 256),
    IconSize(filename: "Icon-256.png", pixels: 256),
    IconSize(filename: "Icon-256@2x.png", pixels: 512),
    IconSize(filename: "Icon-512.png", pixels: 512),
    IconSize(filename: "Icon-512@2x.png", pixels: 1024)
]

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func capsule(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSBezierPath {
    roundedRect(CGRect(x: x, y: y, width: width, height: height), radius: height / 2)
}

func drawIcon(size: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(
            domain: "ShuoLogoGeneration",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not allocate bitmap for \(size)x\(size) icon"]
        )
    }

    bitmap.size = NSSize(width: size, height: size)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "ShuoLogoGeneration",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not create graphics context for \(size)x\(size) icon"]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    guard let context = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    let scale = CGFloat(size) / 1024
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    NSColor.clear.setFill()
    CGRect(x: 0, y: 0, width: size, height: size).fill()

    let outerRect = CGRect(x: s(46), y: s(46), width: s(932), height: s(932))
    let outer = roundedRect(outerRect, radius: s(210))
    NSColor(hex: 0x090A09).setFill()
    outer.fill()

    NSColor(hex: 0x242420).withAlphaComponent(0.9).setStroke()
    outer.lineWidth = max(1, s(8))
    outer.stroke()

    let innerRect = CGRect(x: s(132), y: s(172), width: s(760), height: s(680))
    let inner = roundedRect(innerRect, radius: s(245))
    NSColor(hex: 0x171714).setFill()
    inner.fill()

    NSColor(hex: 0x26251F).withAlphaComponent(0.55).setStroke()
    inner.lineWidth = max(1, s(2))
    inner.stroke()

    let glow = roundedRect(
        CGRect(x: s(218), y: s(250), width: s(594), height: s(548)),
        radius: s(210)
    )
    NSColor(hex: 0x24231E).withAlphaComponent(0.34).setFill()
    glow.fill()

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s(6))
    shadow.shadowBlurRadius = s(14)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)

    let bars: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
        (352, 266, 238, 0xF6F1E7),
        (366, 322, 348, 0xF6F1E7),
        (428, 378, 336, 0xF6F1E7),
        (428, 434, 252, 0xF6F1E7),
        (268, 490, 488, 0xFF5A36),
        (344, 546, 252, 0xF6F1E7),
        (260, 602, 336, 0xF6F1E7),
        (310, 658, 348, 0xF6F1E7),
        (436, 714, 238, 0xF6F1E7)
    ]

    for (x, y, width, color) in bars {
        context.saveGState()
        shadow.set()
        let path = capsule(x: s(x), y: s(y), width: s(width), height: s(48))
        NSColor(hex: color).setFill()
        path.fill()
        context.restoreGState()

        NSColor(hex: color == 0xFF5A36 ? 0xFF8A68 : 0xFFFFFF).withAlphaComponent(0.45).setStroke()
        path.lineWidth = max(1, s(2))
        path.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "ShuoLogoGeneration",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not render PNG for \(url.path)"]
        )
    }

    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pngData.write(to: url, options: .atomic)
}

for iconSize in iconSizes {
    try writePNG(
        try drawIcon(size: iconSize.pixels),
        to: appIconDirectory.appendingPathComponent(iconSize.filename)
    )
}

try writePNG(try drawIcon(size: 512), to: webIconURL)

print("Generated black Shuo logo assets.")
