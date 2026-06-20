#!/usr/bin/env swift
//
// generate_icon.swift — renders a 1024x1024 calendar app icon as PNG.
//
// Run:
//   swift scripts/generate_icon.swift <output.png>

import AppKit

guard CommandLine.arguments.count >= 2 else {
    fatalError("Usage: generate_icon.swift <output.png>")
}
let outputPath = CommandLine.arguments[1]

let canvas = CGSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

// Background — rounded square in system blue with a soft gradient.
let bgRect = NSRect(origin: .zero, size: canvas)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 224, yRadius: 224)
let gradient = NSGradient(starting: NSColor(red: 0.30, green: 0.55, blue: 1.00, alpha: 1.0),
                          ending:   NSColor(red: 0.10, green: 0.35, blue: 0.95, alpha: 1.0))!
bgPath.addClip()
gradient.draw(in: bgRect, angle: -90)

// Calendar page — white rounded card sitting on the background.
let pad: CGFloat = 188
let paperRect = NSRect(x: pad, y: pad, width: canvas.width - pad * 2, height: canvas.height - pad * 2)
let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: 56, yRadius: 56)
NSColor.white.setFill()
paperPath.fill()

// Red header strip with rounded top corners (matching the paper's top radius).
let headerHeight: CGFloat = 156
let headerRect = NSRect(
    x: paperRect.origin.x,
    y: paperRect.origin.y + paperRect.height - headerHeight,
    width: paperRect.width,
    height: headerHeight
)
let header = NSBezierPath()
let r: CGFloat = 56
header.move(to: NSPoint(x: headerRect.minX, y: headerRect.minY))
header.line(to: NSPoint(x: headerRect.minX, y: headerRect.maxY - r))
header.appendArc(withCenter: NSPoint(x: headerRect.minX + r, y: headerRect.maxY - r),
                 radius: r, startAngle: 180, endAngle: 90, clockwise: true)
header.line(to: NSPoint(x: headerRect.maxX - r, y: headerRect.maxY))
header.appendArc(withCenter: NSPoint(x: headerRect.maxX - r, y: headerRect.maxY - r),
                 radius: r, startAngle: 90, endAngle: 0, clockwise: true)
header.line(to: NSPoint(x: headerRect.maxX, y: headerRect.minY))
header.close()
NSColor(red: 0.95, green: 0.25, blue: 0.30, alpha: 1.0).setFill()
header.fill()

// Two small "ring" tabs at the top, like a wall calendar.
NSColor(white: 0.85, alpha: 1.0).setFill()
for x: CGFloat in [paperRect.minX + 180, paperRect.maxX - 180 - 50] {
    let tab = NSRect(x: x, y: paperRect.maxY - 30, width: 50, height: 80)
    NSBezierPath(roundedRect: tab, xRadius: 25, yRadius: 25).fill()
}

// Day number — bold, centered on the white area.
let textArea = NSRect(
    x: paperRect.origin.x,
    y: paperRect.origin.y,
    width: paperRect.width,
    height: paperRect.height - headerHeight
)
let day = NSAttributedString(string: "20", attributes: [
    .font: NSFont.systemFont(ofSize: 360, weight: .bold),
    .foregroundColor: NSColor.black,
])
let daySize = day.size()
day.draw(at: NSPoint(
    x: textArea.minX + (textArea.width - daySize.width) / 2,
    y: textArea.minY + (textArea.height - daySize.height) / 2 - 20
))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:])
else { fatalError("PNG encoding failed") }

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Saved: \(outputPath)")
