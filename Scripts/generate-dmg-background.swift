#!/usr/bin/env swift

import AppKit
import Foundation

private enum Canvas {
    static let width: CGFloat = 720
    static let height: CGFloat = 440
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private func rectFromTop(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat
) -> CGRect {
    CGRect(
        x: x,
        y: Canvas.height - y - height,
        width: width,
        height: height
    )
}

private func pointFromTop(x: CGFloat, y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: Canvas.height - y)
}

private func drawText(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    font: NSFont,
    color: NSColor,
    tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking
    ]
    let attributedText = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributedText.size()
    attributedText.draw(
        at: CGPoint(
            x: x,
            y: Canvas.height - y - textSize.height
        )
    )
}

private struct StyledTextRun {
    let text: String
    let font: NSFont
    let color: NSColor
    let tracking: CGFloat

    init(
        _ text: String,
        font: NSFont,
        color: NSColor,
        tracking: CGFloat = 0
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.tracking = tracking
    }
}

private func drawText(
    _ runs: [StyledTextRun],
    x: CGFloat,
    y: CGFloat
) {
    let attributedText = NSMutableAttributedString()
    for run in runs {
        attributedText.append(
            NSAttributedString(
                string: run.text,
                attributes: [
                    .font: run.font,
                    .foregroundColor: run.color,
                    .kern: run.tracking
                ]
            )
        )
    }

    let textSize = attributedText.size()
    attributedText.draw(
        at: CGPoint(
            x: x,
            y: Canvas.height - y - textSize.height
        )
    )
}

private func strokeLine(
    from start: CGPoint,
    to end: CGPoint,
    color: NSColor,
    width: CGFloat
) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

private func drawGrid() {
    let gridColor = NSColor(hex: 0x11110F, alpha: 0.045)
    let gridPath = NSBezierPath()
    gridPath.lineWidth = 0.5

    var x: CGFloat = 0
    while x <= Canvas.width {
        gridPath.move(to: pointFromTop(x: x, y: 0))
        gridPath.line(to: pointFromTop(x: x, y: 344))
        x += 48
    }

    var y: CGFloat = 8
    while y <= 344 {
        gridPath.move(to: pointFromTop(x: 0, y: y))
        gridPath.line(to: pointFromTop(x: Canvas.width, y: y))
        y += 48
    }

    gridColor.setStroke()
    gridPath.stroke()
}

private func drawSignalTrack() {
    let baselineColor = NSColor(hex: 0x11110F, alpha: 0.20)
    let mutedNodeColor = NSColor(hex: 0x11110F, alpha: 0.34)
    let accentColor = NSColor(hex: 0xFF5633)
    let trackY: CGFloat = 235

    strokeLine(
        from: pointFromTop(x: 270, y: trackY),
        to: pointFromTop(x: 450, y: trackY),
        color: baselineColor,
        width: 1
    )

    for nodeX in [306, 414] as [CGFloat] {
        let node = NSBezierPath(
            ovalIn: rectFromTop(x: nodeX - 2, y: trackY - 2, width: 4, height: 4)
        )
        mutedNodeColor.setFill()
        node.fill()
    }

    let activeSegment = NSBezierPath(
        roundedRect: rectFromTop(x: 339, y: trackY - 2, width: 42, height: 4),
        xRadius: 2,
        yRadius: 2
    )
    accentColor.setFill()
    activeSegment.fill()

    let arrow = NSBezierPath()
    arrow.move(to: pointFromTop(x: 450, y: trackY))
    arrow.line(to: pointFromTop(x: 440, y: trackY - 7))
    arrow.move(to: pointFromTop(x: 450, y: trackY))
    arrow.line(to: pointFromTop(x: 440, y: trackY + 7))
    arrow.lineWidth = 1.5
    NSColor(hex: 0x11110F, alpha: 0.48).setStroke()
    arrow.stroke()
}

private func drawWaveformMark() {
    let waveformColor = NSColor(hex: 0x11110F, alpha: 0.055)
    let accentColor = NSColor(hex: 0xFF5633, alpha: 0.13)
    let bars: [(x: CGFloat, y: CGFloat, width: CGFloat, accent: Bool)] = [
        (530, 40, 104, false),
        (496, 56, 138, false),
        (472, 72, 162, false),
        (506, 88, 128, false),
        (454, 104, 180, true),
        (510, 120, 124, false)
    ]

    for bar in bars {
        let path = NSBezierPath(
            roundedRect: rectFromTop(x: bar.x, y: bar.y, width: bar.width, height: 5),
            xRadius: 2.5,
            yRadius: 2.5
        )
        (bar.accent ? accentColor : waveformColor).setFill()
        path.fill()
    }
}

private func renderBackground(scale: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(Canvas.width) * scale,
        pixelsHigh: Int(Canvas.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(
            domain: "ShuoDMGBackground",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not allocate the DMG background bitmap."]
        )
    }

    bitmap.size = NSSize(width: Canvas.width, height: Canvas.height)
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "ShuoDMGBackground",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not create the DMG background context."]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    NSColor(hex: 0xF4F1E8).setFill()
    CGRect(x: 0, y: 0, width: Canvas.width, height: Canvas.height).fill()

    drawGrid()
    drawWaveformMark()
    drawSignalTrack()

    drawText(
        "INSTALL PATH / 01—02",
        x: 44,
        y: 39,
        font: .monospacedSystemFont(ofSize: 10, weight: .medium),
        color: NSColor(hex: 0x11110F, alpha: 0.46),
        tracking: 1.25
    )
    drawText(
        [
            StyledTextRun(
                "Drag ",
                font: .systemFont(ofSize: 22, weight: .medium),
                color: NSColor(hex: 0x11110F)
            ),
            StyledTextRun(
                "Shuo",
                font: .systemFont(ofSize: 22, weight: .semibold),
                color: NSColor(hex: 0xFF5633)
            ),
            StyledTextRun(
                " to Applications",
                font: .systemFont(ofSize: 22, weight: .medium),
                color: NSColor(hex: 0x11110F)
            )
        ],
        x: 44,
        y: 65
    )
    drawText(
        [
            StyledTextRun(
                "把 ",
                font: .systemFont(ofSize: 11, weight: .regular),
                color: NSColor(hex: 0x11110F, alpha: 0.52)
            ),
            StyledTextRun(
                "Shuo",
                font: .systemFont(ofSize: 11, weight: .medium),
                color: NSColor(hex: 0xFF5633, alpha: 0.90)
            ),
            StyledTextRun(
                " 拖到「应用程序」",
                font: .systemFont(ofSize: 11, weight: .regular),
                color: NSColor(hex: 0x11110F, alpha: 0.52)
            )
        ],
        x: 44,
        y: 102
    )

    strokeLine(
        from: pointFromTop(x: 44, y: 390),
        to: pointFromTop(x: 676, y: 390),
        color: NSColor(hex: 0x11110F, alpha: 0.10),
        width: 0.5
    )

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

private func writePNG(_ bitmap: NSBitmapImageRep, to outputURL: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "ShuoDMGBackground",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode \(outputURL.lastPathComponent)."]
        )
    }
    try data.write(to: outputURL, options: .atomic)
}

let outputDirectory: URL
if CommandLine.arguments.count > 1 {
    outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
} else {
    outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Packaging/DMG", isDirectory: true)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)
try writePNG(
    try renderBackground(scale: 1),
    to: outputDirectory.appendingPathComponent("background.png")
)
try writePNG(
    try renderBackground(scale: 2),
    to: outputDirectory.appendingPathComponent("background@2x.png")
)

print("Generated Shuo DMG background assets in \(outputDirectory.path)")
