#!/usr/bin/env swift
// Draws the app icon at 1024x1024 and writes it as a PNG.
// Usage: swift scripts/generate-icon.swift <output.png>
// scripts/update-icon.sh runs this and fills the asset catalog with every size.

import AppKit
import CoreImage

let size = 1024
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
// macOS icons leave a transparent margin around the rounded square.
let tile = canvas.insetBy(dx: 100, dy: 100)
let center = CGPoint(x: canvas.midX, y: canvas.midY)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Couldn't create the drawing context")
}

// Dark rounded square.
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
context.saveGState()
context.addPath(tilePath)
context.clip()
let background = CGGradient(
    colorsSpace: nil,
    colors: [color(0.13, 0.14, 0.19), color(0.02, 0.02, 0.04)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: canvas.midX, y: tile.maxY),
    end: CGPoint(x: canvas.midX, y: tile.minY),
    options: []
)

// The halo: a ring of light, blurred at two radii for the glow, then drawn sharp on top.
let ringRadius: CGFloat = 228
let ringWidth: CGFloat = 26
let ringStops: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = [
    (0.45, 0.80, 1.00), (0.62, 0.55, 1.00), (1.00, 0.62, 0.86), (1.00, 0.84, 0.66), (0.45, 0.80, 1.00),
]

/// Color at a position around the ring, from 0 to 1.
func ringColor(at position: CGFloat) -> CGColor {
    let scaled = position * CGFloat(ringStops.count - 1)
    let index = min(Int(scaled), ringStops.count - 2)
    let (from, to) = (ringStops[index], ringStops[index + 1])
    let mix = scaled - CGFloat(index)
    return color(
        from.red + (to.red - from.red) * mix,
        from.green + (to.green - from.green) * mix,
        from.blue + (to.blue - from.blue) * mix
    )
}

/// CGContext has no conic gradient, so the ring is made of short arcs.
func makeRing() -> CGImage {
    let ring = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ring.setLineWidth(ringWidth)
    let segments = 720
    for segment in 0..<segments {
        let position = CGFloat(segment) / CGFloat(segments)
        let start = .pi / 2 + position * 2 * .pi
        ring.setStrokeColor(ringColor(at: position))
        ring.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: start + 2 * .pi / CGFloat(segments) * 1.5, clockwise: false)
        ring.strokePath()
    }
    return ring.makeImage()!
}

func blurred(_ image: CGImage, radius: Double) -> CGImage {
    let input = CIImage(cgImage: image)
    let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input, kCIInputRadiusKey: radius])!
    return CIContext().createCGImage(filter.outputImage!, from: canvas)!
}

let ring = makeRing()
for (radius, alpha) in [(70.0, 0.75), (24.0, 0.65)] {
    context.saveGState()
    context.setAlpha(alpha)
    context.draw(blurred(ring, radius: radius), in: canvas)
    context.restoreGState()
}
context.draw(ring, in: canvas)

// A white core makes the ring read as a light source.
context.setStrokeColor(color(1, 1, 1, 0.75))
context.setLineWidth(7)
context.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
context.strokePath()

// The island, floating in the middle of the halo.
let island = CGRect(x: center.x - 138, y: center.y - 46, width: 276, height: 92)
let islandPath = CGPath(roundedRect: island, cornerWidth: 46, cornerHeight: 46, transform: nil)
context.setShadow(offset: .zero, blur: 40, color: color(0.62, 0.55, 1.00, 0.6))
context.setFillColor(color(0, 0, 0))
context.addPath(islandPath)
context.fillPath()
context.restoreGState()

// Thin light edge around the rounded square.
context.setStrokeColor(color(1, 1, 1, 0.10))
context.setLineWidth(3)
context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
context.strokePath()

guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else {
    fatalError("Couldn't encode the icon")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
