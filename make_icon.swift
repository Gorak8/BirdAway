#!/usr/bin/env swift
// Run from the repo root:  swift make_icon.swift
//
// Renders a sky-blue gradient background with a white bird.fill SF Symbol and
// writes all required AppIcon sizes into the asset catalog.

import AppKit

let outputDir = "BirdAway/Assets.xcassets/AppIcon.appiconset"

// Verify we're in the right directory
guard FileManager.default.fileExists(atPath: outputDir) else {
    print("ERROR: '\(outputDir)' not found.")
    print("Run this script from the repo root: cd /path/to/BirdAway && swift make_icon.swift")
    exit(1)
}

// (logicalPoints, scale, filename)
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

func renderIcon(pixelSize: Int) -> NSImage? {
    let px = CGFloat(pixelSize)

    // Off-screen bitmap — no lockFocus needed
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let gc = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    let rect = CGRect(origin: .zero, size: CGSize(width: px, height: px))

    // --- Rounded-rect clip (macOS icon corner radius ≈ 22.5%) ---
    let radius = px * 0.225
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // --- Sky-blue gradient background ---
    let top    = CGColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)   // #59C7FA
    let bottom = CGColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)   // #007AFF
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top, bottom] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: px / 2, y: px),
                               end:   CGPoint(x: px / 2, y: 0),
                               options: [])
    }

    // --- White bird.fill SF Symbol ---
    // SymbolConfiguration(paletteColors:) is the correct way to tint an SF Symbol.
    let ptSize = px * 0.55
    let symConfig = NSImage.SymbolConfiguration(pointSize: ptSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

    if let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(symConfig) {
        let sw = symbol.size.width
        let sh = symbol.size.height
        let sx = (px - sw) / 2
        let sy = (px - sh) / 2 - px * 0.02    // slight optical drop
        symbol.draw(in: NSRect(x: sx, y: sy, width: sw, height: sh))
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: px, height: px))
    image.addRepresentation(rep)
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff   = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:]) else {
        print("  ERROR: could not encode PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("  ✓ \(path)")
    } catch {
        print("  ERROR writing \(path): \(error)")
    }
}

print("Generating BirdAway app icons…")
for (points, scale, filename) in sizes {
    let pixels = points * scale
    if let image = renderIcon(pixelSize: pixels) {
        savePNG(image, to: "\(outputDir)/\(filename)")
    } else {
        print("  ERROR: render failed for \(filename)")
    }
}
print("Done. Rebuild in Xcode to apply the icon.")
