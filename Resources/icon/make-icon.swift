import AppKit
import Foundation

// Draws the app icon: the floating pill, as it looks on screen, sitting on a
// dark rounded tile, with a streak flame in the corner.
let size: CGFloat = 1024

func draw() -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    // Tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                            xRadius: size * 0.225, yRadius: size * 0.225)
    tile.addClip()
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
    ])!
    bg.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

    // The pill
    let pillRect = NSRect(x: size * 0.115, y: size * 0.355, width: size * 0.77, height: size * 0.29)
    let pill = NSBezierPath(roundedRect: pillRect,
                            xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                  color: NSColor.black.withAlphaComponent(0.55).cgColor)
    NSColor(calibratedRed: 0.235, green: 0.235, blue: 0.255, alpha: 1).setFill()
    pill.fill()
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.13).setStroke()
    pill.lineWidth = 3
    pill.stroke()

    // Timer ring on the left of the pill, as in the app
    let ringSize = pillRect.height * 0.60
    let ringRect = NSRect(x: pillRect.minX + pillRect.height * 0.30,
                          y: pillRect.midY - ringSize / 2,
                          width: ringSize, height: ringSize)
    let track = NSBezierPath(ovalIn: ringRect)
    track.lineWidth = ringSize * 0.11
    NSColor.white.withAlphaComponent(0.18).setStroke()
    track.stroke()

    let progress = NSBezierPath()
    progress.appendArc(withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
                       radius: ringSize / 2, startAngle: 90, endAngle: -40, clockwise: true)
    progress.lineWidth = ringSize * 0.11
    progress.lineCapStyle = .round
    NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).setStroke()
    progress.stroke()

    // Wordmark
    let text = "floater.ai" as NSString
    let fontSize = pillRect.height * 0.36
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(0.96),
        .kern: fontSize * 0.01,
    ]
    let textSize = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: ringRect.maxX + pillRect.height * 0.26,
                          y: pillRect.midY - textSize.height / 2),
              withAttributes: attrs)

    // Streak flame, top-right corner
    if let flame = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.14, weight: .bold)
            .applying(NSImage.SymbolConfiguration(
                paletteColors: [NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.13, alpha: 1)]
            ))
        if let sized = flame.withSymbolConfiguration(config) {
            sized.isTemplate = false
            let box = NSRect(x: size * 0.735, y: size * 0.715,
                             width: size * 0.155, height: size * 0.155)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 40,
                          color: NSColor(calibratedRed: 1, green: 0.45, blue: 0.1, alpha: 0.85).cgColor)
            sized.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        }
    }

    image.unlockFocus()
    return image
}

let image = draw()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render\n".data(using: .utf8)!)
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
