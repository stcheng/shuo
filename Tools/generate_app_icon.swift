import AppKit

struct IconSlot {
    let filename: String
    let pixelSize: Int
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let slots = [
    IconSlot(filename: "Icon-16.png", pixelSize: 16),
    IconSlot(filename: "Icon-16@2x.png", pixelSize: 32),
    IconSlot(filename: "Icon-32.png", pixelSize: 32),
    IconSlot(filename: "Icon-32@2x.png", pixelSize: 64),
    IconSlot(filename: "Icon-128.png", pixelSize: 128),
    IconSlot(filename: "Icon-128@2x.png", pixelSize: 256),
    IconSlot(filename: "Icon-256.png", pixelSize: 256),
    IconSlot(filename: "Icon-256@2x.png", pixelSize: 512),
    IconSlot(filename: "Icon-512.png", pixelSize: 512),
    IconSlot(filename: "Icon-512@2x.png", pixelSize: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    let width = size
    let height = size
    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.setAllowsAntialiasing(true)

    NSColor.clear.setFill()
    rect.fill()

    let scale = CGFloat(size)
    let outerInset = scale * 0.045
    let outerRect = rect.insetBy(dx: outerInset, dy: outerInset)
    let outerRadius = scale * 0.225
    let outerPath = roundedRect(outerRect, radius: outerRadius)

    outerPath.addClip()
    let gradient = NSGradient(colors: [
        color(12, 18, 30),
        color(18, 63, 76),
        color(32, 91, 105)
    ])!
    gradient.draw(in: outerRect, angle: 315)

    color(255, 255, 255, 0.10).setStroke()
    outerPath.lineWidth = max(1, scale * 0.016)
    outerPath.stroke()

    let glowRect = CGRect(
        x: scale * 0.13,
        y: scale * 0.17,
        width: scale * 0.74,
        height: scale * 0.66
    )
    let glowPath = roundedRect(glowRect, radius: scale * 0.28)
    color(94, 234, 212, 0.13).setFill()
    glowPath.fill()

    let glyphRect = CGRect(
        x: scale * 0.16,
        y: scale * 0.16,
        width: scale * 0.68,
        height: scale * 0.68
    )
    let fullRows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.82, 0.44, 0.34, color(84, 232, 220)),
        (0.74, 0.54, 0.50, color(243, 250, 252)),
        (0.66, 0.62, 0.48, color(226, 247, 247)),
        (0.58, 0.56, 0.36, color(243, 250, 252)),
        (0.50, 0.50, 0.70, color(247, 126, 85)),
        (0.42, 0.44, 0.36, color(243, 250, 252)),
        (0.34, 0.38, 0.48, color(226, 247, 247)),
        (0.26, 0.46, 0.50, color(243, 250, 252)),
        (0.18, 0.56, 0.34, color(84, 232, 220))
    ]
    let compactRows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.78, 0.45, 0.40, color(84, 232, 220)),
        (0.64, 0.60, 0.52, color(243, 250, 252)),
        (0.50, 0.50, 0.70, color(247, 126, 85)),
        (0.36, 0.40, 0.52, color(243, 250, 252)),
        (0.22, 0.55, 0.40, color(84, 232, 220))
    ]
    let rows = size <= 32 ? compactRows : fullRows
    let barHeight = max(1, scale * (size <= 32 ? 0.058 : 0.046))

    context.cgContext.saveGState()
    context.cgContext.setShadow(
        offset: CGSize(width: 0, height: -scale * 0.015),
        blur: scale * 0.04,
        color: color(0, 0, 0, 0.36).cgColor
    )

    for (centerYRatio, centerXRatio, widthRatio, fill) in rows {
        let barWidth = glyphRect.width * widthRatio
        let barRect = CGRect(
            x: glyphRect.minX + glyphRect.width * centerXRatio - barWidth / 2,
            y: glyphRect.minY + glyphRect.height * centerYRatio - barHeight / 2,
            width: barWidth,
            height: barHeight
        )
        let barPath = roundedRect(barRect, radius: barHeight / 2)
        fill.setFill()
        barPath.fill()
    }
    context.cgContext.restoreGState()

    color(255, 255, 255, 0.16).setStroke()
    for (centerYRatio, centerXRatio, widthRatio, _) in rows {
        let barWidth = glyphRect.width * widthRatio
        let barRect = CGRect(
            x: glyphRect.minX + glyphRect.width * centerXRatio - barWidth / 2,
            y: glyphRect.minY + glyphRect.height * centerYRatio - barHeight / 2,
            width: barWidth,
            height: barHeight
        )
        let barPath = roundedRect(barRect, radius: barHeight / 2)
        barPath.lineWidth = max(0.5, scale * 0.004)
        barPath.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    let rep = drawIcon(size: slot.pixelSize)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(slot.filename))
}
