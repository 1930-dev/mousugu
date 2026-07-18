#!/usr/bin/env swift
//
// generate_hero_shot.swift — composites the menu-bar chip and the open popover
// onto an on-brand gradient for the website hero (CleanShot/OpenScreen "menu
// opened" look). Same charcoal backdrop, dot-grid and #DF4B3B red as the icon.
//
// The input is the raw full-screen capture. Crop rects isolate the popover and
// (optionally) the menu-bar chip; each is clipped to its own rounded corners so
// the wallpaper doesn't leak, then floated with a soft drop shadow. With a chip,
// it sits above the popover to show the click that opened it.
//
// Run:
//   swift scripts/generate_hero_shot.swift <in.png> <out.png> \
//         <popX> <popY> <popW> <popH> <popRadius> \
//         [<chipX> <chipY> <chipW> <chipH> <chipRadius>]
//   (crop values in the INPUT image's pixel space.)

import AppKit

let A = CommandLine.arguments
guard A.count >= 8 else {
    fatalError("Usage: <in> <out> <popX popY popW popH popRadius> [chipX chipY chipW chipH chipRadius]")
}
let inputPath = A[1], outputPath = A[2]
func d(_ i: Int) -> CGFloat { CGFloat(Double(A[i])!) }
let popRect = CGRect(x: d(3), y: d(4), width: d(5), height: d(6))
let popRadius = d(7)
let hasChip = A.count >= 13
let chipRect = hasChip ? CGRect(x: d(8), y: d(9), width: d(10), height: d(11)) : .zero
let chipRadius = hasChip ? d(12) : 0

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
let backdropNear = rgb(53, 52, 44), backdropMid = rgb(36, 35, 29), backdropFar = rgb(28, 27, 22)
let dotColour = rgb(255, 255, 255, 0.05)

guard let src = NSImage(contentsOfFile: inputPath),
      let rep = NSBitmapImageRep(data: src.tiffRepresentation!),
      let srcCG = rep.cgImage else { fatalError("Could not load \(inputPath)") }
func crop(_ r: CGRect) -> CGImage {
    guard let c = srcCG.cropping(to: r) else { fatalError("Crop \(r) outside \(srcCG.width)x\(srcCG.height)") }
    return c
}
let popCG = crop(popRect)
let popW = CGFloat(popCG.width), popH = CGFloat(popCG.height)
let chipCG = hasChip ? crop(chipRect) : nil
let chipW = hasChip ? CGFloat(chipCG!.width) : 0
let chipH = hasChip ? CGFloat(chipCG!.height) : 0

// Layout: vertical block of chip + gap + popover, ~72% of canvas height.
let gap: CGFloat = hasChip ? 34 : 0
let blockH = popH + (hasChip ? chipH + gap : 0)
let canvasH = blockH / 0.72
let canvasW = canvasH * 1.5

func img(_ cg: CGImage, _ w: CGFloat, _ h: CGFloat) -> NSImage {
    NSImage(cgImage: cg, size: NSSize(width: w, height: h))
}

func makeCanvas(_ draw: (CGContext) -> Void) -> CGImage {
    let pw = Int(canvasW), ph = Int(canvasH)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("no sRGB context") }
    ctx.translateBy(x: 0, y: CGFloat(ph)); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func floatSurface(_ ctx: CGContext, image: NSImage, frame: NSRect, radius: CGFloat) {
    let clip = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 55
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.set()
    NSColor.black.setFill(); clip.fill()   // solid base so the shadow casts a shape
    ctx.restoreGState()

    ctx.saveGState(); clip.addClip(); image.draw(in: frame); ctx.restoreGState()

    rgb(255, 255, 255, 0.08).setStroke()
    let ring = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    ring.lineWidth = 1; ring.stroke()
}

let hero = makeCanvas { ctx in
    // Charcoal radial lift, brightest towards the top-left (the icon's move).
    let centre = NSPoint(x: canvasW * 0.30, y: canvasH * 0.26)
    NSGradient(colors: [backdropNear, backdropMid, backdropFar], atLocations: [0, 0.6, 1],
               colorSpace: .sRGB)?
        .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: canvasW * 0.9,
              options: [.drawsAfterEndingLocation])

    // Dot-grid watermark echoing the app icon.
    let step: CGFloat = 40, dotR: CGFloat = 4
    var y = step
    while y < canvasH { var x = step; while x < canvasW {
        dotColour.setFill()
        NSBezierPath(ovalIn: NSRect(x: x-dotR/2, y: y-dotR/2, width: dotR, height: dotR)).fill()
        x += step }; y += step }

    let blockTop = (canvasH - blockH) / 2
    let popOriginX = (canvasW - popW) / 2
    let popCentreX = popOriginX + popW/2

    if hasChip, let chipCG = chipCG {
        let chipFrame = NSRect(x: popCentreX - chipW/2, y: blockTop, width: chipW, height: chipH)
        floatSurface(ctx, image: img(chipCG, chipW, chipH), frame: chipFrame, radius: chipRadius)
        let popFrame = NSRect(x: popOriginX, y: blockTop + chipH + gap, width: popW, height: popH)
        floatSurface(ctx, image: img(popCG, popW, popH), frame: popFrame, radius: popRadius)
    } else {
        let popFrame = NSRect(x: popOriginX, y: blockTop, width: popW, height: popH)
        floatSurface(ctx, image: img(popCG, popW, popH), frame: popFrame, radius: popRadius)
    }
}

try NSBitmapImageRep(cgImage: hero).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outputPath))
print("Saved: \(outputPath) (\(Int(canvasW))x\(Int(canvasH)))")
