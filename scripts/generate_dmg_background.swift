#!/usr/bin/env swift
//
// generate_dmg_background.swift — renders the DMG install-window background.
//
// On-brand with the app icon (scripts/generate_icon.swift): the same charcoal
// backdrop and #DF4B3B red, a faint 5-column-style dot grid echoing the icon's
// day grid, two seated wells for the app and the Applications alias, a red
// arrow between them, and one line of instruction.
//
// Rendered at 2× (1280×800) for a 640×400 logical Finder window. release.sh
// feeds this to create-dmg's --background and positions the two icons over the
// wells. Coordinates below are in LOGICAL points (top-left origin); the context
// is flipped and scaled so drawing reads top-down like the Finder layout.
//
// Run:
//   swift scripts/generate_dmg_background.swift <output.png>

import AppKit

guard CommandLine.arguments.count >= 2 else {
    fatalError("Usage: generate_dmg_background.swift <output.png>")
}
let outputPath = CommandLine.arguments[1]

// Logical Finder window, and the 2× bitmap behind it.
let width: CGFloat = 640
let height: CGFloat = 400
let scale: CGFloat = 2

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
}

// Shared with the icon so the DMG and the app read as one product.
let backdropNear = rgb(53, 52, 44) // #35342C
let backdropMid = rgb(36, 35, 29)  // #24231D
let backdropFar = rgb(28, 27, 22)  // #1C1B16
let todayColour = rgb(223, 75, 59) // #DF4B3B
let dotColour = rgb(255, 255, 255, 0.05)
let wellFill = rgb(0, 0, 0, 0.18)
let wellStroke = rgb(255, 255, 255, 0.06)
let textColour = rgb(255, 255, 255, 0.62)
// A mid-tone plate behind each Finder icon label. Finder draws those labels
// itself in a colour that follows the viewer's Light/Dark appearance (near-black
// in Light, near-white in Dark) with no way to override it — so a medium
// backing is the only thing that keeps them legible in *both* modes on this
// dark backdrop.
let namePlateFill = rgb(150, 146, 132, 0.30)

// Icon slots — kept in sync with the --icon positions in release.sh.
let appCenter = NSPoint(x: 170, y: 168)
let appsCenter = NSPoint(x: 470, y: 168)
let iconSlot: CGFloat = 150 // well edge; a touch larger than the 128 icons
// Where Finder lays the icon label: one line, centred under each icon.
let labelCenterY: CGFloat = 247
let labelPlateSize = NSSize(width: 118, height: 22)

/// Rasterises into an explicitly sRGB context, flipped to a top-left origin and
/// scaled to 2×, matching generate_icon.swift so colours are stable across
/// machines.
func makeCanvas(_ draw: (CGContext) -> Void) -> CGImage {
    let pixelWidth = Int(width * scale)
    let pixelHeight = Int(height * scale)
    guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil,
                                  width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colourSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("Could not create an sRGB bitmap context") }

    context.translateBy(x: 0, y: CGFloat(pixelHeight))
    context.scaleBy(x: scale, y: -scale)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else { fatalError("Rasterisation failed") }
    return image
}

func well(around centre: NSPoint) -> NSBezierPath {
    let rect = NSRect(x: centre.x - iconSlot / 2, y: centre.y - iconSlot / 2,
                      width: iconSlot, height: iconSlot)
    return NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
}

let background = makeCanvas { context in
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // Charcoal backdrop — a radial lift brightest towards the top-left, the
    // same move the icon makes.
    let centre = NSPoint(x: width * 0.28, y: height * 0.30)
    NSGradient(colors: [backdropNear, backdropMid, backdropFar],
               atLocations: [0, 0.6, 1], colorSpace: .sRGB)?
        .draw(fromCenter: centre, radius: 0,
              toCenter: centre, radius: width * 0.85,
              options: [.drawsAfterEndingLocation])

    // Dot-grid watermark echoing the icon's day grid — quiet enough to read as
    // texture, not content.
    let step: CGFloat = 28
    let dot: CGFloat = 3
    var y = step
    while y < height {
        var x = step
        while x < width {
            dotColour.setFill()
            NSBezierPath(ovalIn: NSRect(x: x - dot / 2, y: y - dot / 2,
                                        width: dot, height: dot)).fill()
            x += step
        }
        y += step
    }

    // Seated wells for the two icons.
    for centre in [appCenter, appsCenter] {
        let path = well(around: centre)
        wellFill.setFill()
        path.fill()
        wellStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // Legibility plates behind the Finder-drawn icon labels.
    for centre in [appCenter, appsCenter] {
        let rect = NSRect(x: centre.x - labelPlateSize.width / 2,
                          y: labelCenterY - labelPlateSize.height / 2,
                          width: labelPlateSize.width, height: labelPlateSize.height)
        namePlateFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
    }

    // Red arrow from the app well to the Applications well.
    let arrowStart = NSPoint(x: appCenter.x + iconSlot / 2 + 20, y: appCenter.y)
    let arrowEnd = NSPoint(x: appsCenter.x - iconSlot / 2 - 20, y: appsCenter.y)
    let head: CGFloat = 13
    context.saveGState()
    let glow = NSShadow()
    glow.shadowOffset = .zero
    glow.shadowBlurRadius = 8
    glow.shadowColor = todayColour.withAlphaComponent(0.5)
    glow.set()
    todayColour.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: arrowStart)
    shaft.line(to: NSPoint(x: arrowEnd.x - head, y: arrowEnd.y))
    shaft.lineWidth = 4
    shaft.lineCapStyle = .round
    shaft.stroke()
    todayColour.setFill()
    let arrowhead = NSBezierPath()
    arrowhead.move(to: arrowEnd)
    arrowhead.line(to: NSPoint(x: arrowEnd.x - head, y: arrowEnd.y - head * 0.72))
    arrowhead.line(to: NSPoint(x: arrowEnd.x - head, y: arrowEnd.y + head * 0.72))
    arrowhead.close()
    arrowhead.fill()
    context.restoreGState()

    // Instruction line, centred below the wells.
    let text = "Drag Mou Sugu to Applications"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: textColour,
        .paragraphStyle: paragraph,
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
        at: NSPoint(x: (width - size.width) / 2, y: 300),
        withAttributes: attributes)

    _ = bounds
}

guard let pngData = NSBitmapImageRep(cgImage: background).representation(using: .png, properties: [:])
else { fatalError("PNG encoding failed") }

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Saved: \(outputPath)")
