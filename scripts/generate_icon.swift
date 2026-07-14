#!/usr/bin/env swift
//
// generate_icon.swift — renders the 1024x1024 "Day grid" app icon as PNG.
//
// Ported from the Claude Design source "Calendar Icon.dc.html" (Turn 2, the refined
// 1b direction): a charcoal rounded square holding a 5x5 grid of dots, the centre
// one marked as today.
//
// The icon follows the macOS Big Sur+ grid rather than filling the canvas: the
// body is inset and casts a baked-in drop shadow. Those numbers are not
// invented — they were measured off the system's own icons (Calculator, Notes
// and Reminders are pixel-identical in geometry): on a 1024 canvas the solid
// body spans 820x820 centred, and its shadow reaches 17px to either side, 5px
// above and 29px below, i.e. a ~17px blur pushed ~12px down.
//
// macOS does not add a shadow of its own to a .icns — that the system icons
// bake theirs in is the proof. A full-bleed icon renders larger than, and a
// different shape from, every neighbour in the Dock.
//
// Run:
//   swift scripts/generate_icon.swift <output.png>

import AppKit

guard CommandLine.arguments.count >= 2 else {
    fatalError("Usage: generate_icon.swift <output.png>")
}
let outputPath = CommandLine.arguments[1]

// The bitmap Apple asks for.
let canvas: CGFloat = 1024
// The icon shape inside it — Apple's template body for a 1024 canvas.
let bodyEdge: CGFloat = 824
let body = NSRect(x: (canvas - bodyEdge) / 2, y: (canvas - bodyEdge) / 2,
                  width: bodyEdge, height: bodyEdge)

// The source sizes every feature as a fraction of the icon's edge, so this does
// too — the edge being the body, not the canvas, so the artwork keeps its
// proportions now that the body no longer fills the bitmap.
func s(_ fraction: CGFloat) -> CGFloat { fraction * bodyEdge }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
}

let backdropNear = rgb(53, 52, 44) // #35342C
let backdropMid = rgb(36, 35, 29)  // #24231D
let backdropFar = rgb(28, 27, 22)  // #1C1B16
let todayColour = rgb(223, 75, 59) // #DF4B3B
let dotColour = rgb(255, 255, 255, 0.24)
let ringColour = rgb(255, 255, 255, 0.04)

// 185.4 on an 824 body — Apple's corner radius for the macOS icon grid. The
// source's own 0.2237 rounds to the same shape, so this keeps the design intact.
let cornerRadius = s(0.2249)
// Drop shadow. NSShadow's blur radius is not a pixel extent — these were tuned
// against the system icons' measured reach (L17 T5 R17 B29) and land within a
// pixel of it. The offset is negative because the context below is flipped, so
// negative y draws downwards.
let shadowBlur = s(0.0388)      // 32, reaching ~18px
let shadowOffsetY = s(-0.0146)  // -12, i.e. downwards
let shadowColour = NSColor.black.withAlphaComponent(0.28)
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

let squircle = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

let icon = makeIcon { context in
    // The shadow the Dock expects to find already in the asset. Cast off an
    // opaque fill of the body, which the backdrop then paints over.
    context.saveGState()
    let dropShadow = NSShadow()
    dropShadow.shadowOffset = NSSize(width: 0, height: shadowOffsetY)
    dropShadow.shadowBlurRadius = shadowBlur
    dropShadow.shadowColor = shadowColour
    dropShadow.set()
    NSColor.black.setFill()
    squircle.fill()
    context.restoreGState()

    context.saveGState()
    squircle.setClip()

    // Backdrop — a charcoal radial lift, brightest towards the top-left.
    let backdropCentre = NSPoint(x: body.minX + s(0.30), y: body.minY + s(0.20))
    gradient([backdropNear, backdropMid, backdropFar], at: [0, 0.6, 1])
        .draw(fromCenter: backdropCentre, radius: 0,
              toCenter: backdropCentre, radius: s(1.20),
              options: [.drawsAfterEndingLocation])

    // The source's `inset 0 0 0 1px` hairline, which sits above the backdrop but
    // below the grid.
    let ringWidth: CGFloat = 1
    let ring = NSBezierPath(roundedRect: body.insetBy(dx: ringWidth / 2, dy: ringWidth / 2),
                            xRadius: cornerRadius - ringWidth / 2,
                            yRadius: cornerRadius - ringWidth / 2)
    ring.lineWidth = ringWidth
    ringColour.setStroke()
    ring.stroke()

    // Day grid — 5x5, centred, with today marked at the middle cell.
    let step = dotSize + dotGap
    let gridEdge = dotSize * 5 + dotGap * 4
    let gridOriginX = body.midX - gridEdge / 2
    let gridOriginY = body.midY - gridEdge / 2
    for row in 0..<5 {
        for column in 0..<5 {
            let cell = NSRect(x: gridOriginX + CGFloat(column) * step,
                              y: gridOriginY + CGFloat(row) * step,
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
