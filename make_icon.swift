#!/usr/bin/env swift
// Run from the repo root:  swift make_icon.swift
//
// Renders a sky-blue gradient background with a white bird.fill SF Symbol and
// writes all required AppIcon sizes into the asset catalog.

import AppKit
import CoreGraphics

let outputDir = "BirdAway/Assets.xcassets/AppIcon.appiconset"

// (pointSize, scale, filename)
let sizes: [(Int, Int, String)] = [
    (16,  1, "icon_16x16.png"),
    (16,  2, "icon_16x16@2x.png"),
    (32,  1, "icon_32x32.png"),
    (32,  2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

func renderIcon(pixelSize: Int) -> NSImage {
    let size = CGFloat(pixelSize)
    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))

    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // --- Background: sky blue gradient, macOS-style rounded rect ---
    let radius = size * 0.225          // matches macOS icon corner radius
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let topColor    = CGColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)  // #59C7FA sky blue
    let bottomColor = CGColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)  // #007AFF system blue
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [topColor, bottomColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: size / 2, y: size),
                           end:   CGPoint(x: size / 2, y: 0),
                           options: [])

    // --- Bird SF Symbol, white, centered ---
    // Symbol point size: ~55% of the canvas, nudged down slightly for visual balance
    let symbolPt = size * 0.55
    let config   = NSImage.SymbolConfiguration(pointSize: symbolPt, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(config) {
        // Tint white
        symbol.lockFocus()
        NSColor.white.set()
        symbol.unlockFocus()

        // Re-render tinted: draw into a new image using sourceAtop blending
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
        NSColor.white.withAlphaComponent(1).setFill()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        // Center in canvas
        let symW = tinted.size.width
        let symH = tinted.size.height
        let x = (size - symW) / 2
        let y = (size - symH) / 2 - size * 0.02   // 2% optical drop
        tinted.draw(in: NSRect(x: x, y: y, width: symW, height: symH))
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("  ERROR: could not encode PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("  wrote \(path)")
    } catch {
        print("  ERROR: \(error)")
    }
}

print("Generating BirdAway app icons…")
for (points, scale, filename) in sizes {
    let pixels = points * scale
    let image  = renderIcon(pixelSize: pixels)
    savePNG(image, to: "\(outputDir)/\(filename)")
}
print("Done. Build the project in Xcode to apply the icon.")
