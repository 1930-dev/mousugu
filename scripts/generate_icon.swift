#!/usr/bin/env swift
//
// generate_icon.swift — renders the 1024x1024 "Day grid" app icon as PNG.
//
// Ported from the Claude Design source "Calendar Icon.dc.html" (Turn 2, the refined
// 1b direction): a charcoal rounded square holding a 5x5 grid of dots, the centre
// one marked as today.
//
// The source's outer drop shadow is deliberately not baked in — it is page
// presentation, and macOS draws its own shadow around the icon.
//
// Run:
//   swift scripts/generate_icon.swift <output.png>

import AppKit

guard CommandLine.arguments.count >= 2 else {
    fatalError("Usage: generate_icon.swift <output.png>")
}
let outputPath = CommandLine.arguments[1]

// The source sizes every feature as a fraction of the icon's edge, so this does too.
let canvas: CGFloat = 1024
func s(_ fraction: CGFloat) -> CGFloat { fraction * canvas }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
}

let backdropNear = rgb(53, 52, 44) // #35342C
let backdropMid = rgb(36, 35, 29)  // #24231D
let backdropFar = rgb(28, 27, 22)  // #1C1B16
let todayColour = rgb(223, 75, 59) // #DF4B3B
let dotColour = rgb(255, 255, 255, 0.24)
let ringColour = rgb(255, 255, 255, 0.04)

let cornerRadius = s(0.2237)
let dotSize = s(0.078)
let dotGap = s(0.078)
let todayRadius = s(0.03)
// The source's grid cell is one dot wide and `flex-shrink` pulls the marker's width
// back to it, so the design renders an upright rectangle. Both its code and its
// prose ("a rounded-square today marker") call for a square, so the declared size
// wins here over that CSS accident.
let todaySize = s(0.104)

func gradient(_ colours: [NSColor], at locations: [CGFloat]) -> NSGradient {
    guard let gradient = NSGradient(colors: colours, atLocations: locations, colorSpace: .sRGB) else {
        fatalError("Gradient construction failed")
    }
    return gradient
}

/// Rasterises into an explicitly sRGB context, flipped to the source's top-left
/// origin. `NSImage.lockFocus` would instead rasterise in whatever colour space the
/// current display uses and tag the PNG with that profile, which shifts the icon's
/// colours on every other machine.
func makeIcon(_ draw: (CGContext) -> Void) -> CGImage {
    guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil,
                                  width: Int(canvas), height: Int(canvas),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colourSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("Could not create an sRGB bitmap context") }

    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else { fatalError("Rasterisation failed") }
    return image
}

let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let squircle = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

let icon = makeIcon { context in
    context.saveGState()
    squircle.setClip()

    // Backdrop — a charcoal radial lift, brightest towards the top-left.
    let backdropCentre = NSPoint(x: s(0.30), y: s(0.20))
    gradient([backdropNear, backdropMid, backdropFar], at: [0, 0.6, 1])
        .draw(fromCenter: backdropCentre, radius: 0,
              toCenter: backdropCentre, radius: s(1.20),
              options: [.drawsAfterEndingLocation])

    // The source's `inset 0 0 0 1px` hairline, which sits above the backdrop but
    // below the grid.
    let ringWidth: CGFloat = 1
    let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: ringWidth / 2, dy: ringWidth / 2),
                            xRadius: cornerRadius - ringWidth / 2,
                            yRadius: cornerRadius - ringWidth / 2)
    ring.lineWidth = ringWidth
    ringColour.setStroke()
    ring.stroke()

    // Day grid — 5x5, centred, with today marked at the middle cell.
    let step = dotSize + dotGap
    let gridEdge = dotSize * 5 + dotGap * 4
    let gridOrigin = (canvas - gridEdge) / 2
    for row in 0..<5 {
        for column in 0..<5 {
            let cell = NSRect(x: gridOrigin + CGFloat(column) * step,
                              y: gridOrigin + CGFloat(row) * step,
                              width: dotSize, height: dotSize)
            guard row == 2 && column == 2 else {
                dotColour.setFill()
                NSBezierPath(ovalIn: cell).fill()
                continue
            }
            let marker = NSRect(x: cell.midX - todaySize / 2,
                                y: cell.midY - todaySize / 2,
                                width: todaySize, height: todaySize)
            context.saveGState()
            let glow = NSShadow()
            glow.shadowOffset = NSSize(width: 0, height: s(0.012))
            glow.shadowBlurRadius = s(0.04)
            glow.shadowColor = todayColour.withAlphaComponent(0.55)
            glow.set()
            todayColour.setFill()
            NSBezierPath(roundedRect: marker, xRadius: todayRadius, yRadius: todayRadius).fill()
            context.restoreGState()
        }
    }
    context.restoreGState()
}

guard let pngData = NSBitmapImageRep(cgImage: icon).representation(using: .png, properties: [:])
else { fatalError("PNG encoding failed") }

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Saved: \(outputPath)")
