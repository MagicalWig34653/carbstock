#!/usr/bin/env swift
// Erzeugt das App-Icon (1024x1024, ohne Alpha) als einfache Platzhalter-Grafik.
// Aufruf: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("context") }

// Hintergrund: Verlauf Orange (passt zur AccentColor 0.95/0.45/0.10).
let colors = [
    CGColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1),
    CGColor(red: 0.90, green: 0.36, blue: 0.06, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// Weißer Ring (offen wie ein „C“) = Vorrat; darin drei Balken = Chargen.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(110)
ctx.setLineCap(.round)
let center = CGPoint(x: 512, y: 512)
ctx.addArc(center: center, radius: 330, startAngle: .pi * 0.25, endAngle: .pi * 1.75, clockwise: false)
ctx.strokePath()

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
let bars: [(CGFloat, CGFloat)] = [(380, 200), (470, 280), (560, 360)]
for (i, bar) in bars.enumerated() {
    let rect = CGRect(x: bar.0 + CGFloat(i) * 0, y: 300 + CGFloat(i) * 130, width: bar.1, height: 90)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 45, cornerHeight: 45, transform: nil))
    ctx.fillPath()
}

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("image") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("geschrieben: \(out)")
