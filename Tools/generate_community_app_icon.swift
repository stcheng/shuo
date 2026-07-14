import AppKit

struct CommunityIconSlot {
    let filename: String
    let pixelSize: Int
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let slots = [
    CommunityIconSlot(filename: "Icon-16.png", pixelSize: 16),
    CommunityIconSlot(filename: "Icon-16@2x.png", pixelSize: 32),
    CommunityIconSlot(filename: "Icon-32.png", pixelSize: 32),
    CommunityIconSlot(filename: "Icon-32@2x.png", pixelSize: 64),
    CommunityIconSlot(filename: "Icon-128.png", pixelSize: 128),
    CommunityIconSlot(filename: "Icon-128@2x.png", pixelSize: 256),
    CommunityIconSlot(filename: "Icon-256.png", pixelSize: 256),
    CommunityIconSlot(filename: "Icon-256@2x.png", pixelSize: 512),
    CommunityIconSlot(filename: "Icon-512.png", pixelSize: 512),
    CommunityIconSlot(filename: "Icon-512@2x.png", pixelSize: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawCommunityIcon(size: Int) -> NSBitmapImageRep {
    let dimension = CGFloat(size)
    let canvas = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    let bitmap = NSBitmapImageRep(
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
    )!
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.setShouldAntialias(true)

    NSColor.clear.setFill()
    canvas.fill()

    let inset = dimension * 0.055
    let tile = canvas.insetBy(dx: inset, dy: inset)
    let tilePath = NSBezierPath(
        roundedRect: tile,
        xRadius: dimension * 0.22,
        yRadius: dimension * 0.22
    )
    tilePath.addClip()
    NSGradient(colors: [
        color(42, 50, 59),
        color(68, 78, 86)
    ])!.draw(in: tile, angle: 300)

    color(255, 255, 255, 0.12).setStroke()
    tilePath.lineWidth = max(1, dimension * 0.012)
    tilePath.stroke()

    let center = CGPoint(x: dimension * 0.50, y: dimension * 0.50)
    let nodes = [
        CGPoint(x: dimension * 0.50, y: dimension * 0.73),
        CGPoint(x: dimension * 0.30, y: dimension * 0.38),
        CGPoint(x: dimension * 0.70, y: dimension * 0.38)
    ]
    let connector = NSBezierPath()
    for node in nodes {
        connector.move(to: center)
        connector.line(to: node)
    }
    connector.lineCapStyle = .round
    connector.lineWidth = max(1.5, dimension * 0.055)
    color(177, 214, 205, 0.72).setStroke()
    connector.stroke()

    let outerRadius = dimension * 0.105
    let innerRadius = dimension * 0.058
    for node in nodes {
        let outerCircle = NSBezierPath(ovalIn: CGRect(
            x: node.x - outerRadius,
            y: node.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        color(226, 235, 231).setFill()
        outerCircle.fill()

        let innerCircle = NSBezierPath(ovalIn: CGRect(
            x: node.x - innerRadius,
            y: node.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
        color(72, 95, 96).setFill()
        innerCircle.fill()
    }

    let centerRadius = dimension * 0.12
    let centerCircle = NSBezierPath(ovalIn: CGRect(
        x: center.x - centerRadius,
        y: center.y - centerRadius,
        width: centerRadius * 2,
        height: centerRadius * 2
    ))
    color(225, 171, 104).setFill()
    centerCircle.fill()

    let centerHighlightRadius = dimension * 0.048
    let centerHighlight = NSBezierPath(ovalIn: CGRect(
        x: center.x - centerHighlightRadius,
        y: center.y - centerHighlightRadius,
        width: centerHighlightRadius * 2,
        height: centerHighlightRadius * 2
    ))
    color(255, 242, 218, 0.9).setFill()
    centerHighlight.fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    let bitmap = drawCommunityIcon(size: slot.pixelSize)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(slot.filename))
}
