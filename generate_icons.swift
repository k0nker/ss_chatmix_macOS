#!/usr/bin/env swift

import Foundation
import AppKit

// Create app icon with headphones + play symbol at specified size
func createAppIcon(size: CGFloat) -> NSImage {
    let iconSize = NSSize(width: size, height: size)
    let image = NSImage(size: iconSize)
    
    image.lockFocus()
    
    // Draw rounded rectangle background (macOS icon style)
    let backgroundRect = NSRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)
    let cornerRadius: CGFloat = iconSize.width * 0.225 // Standard macOS icon corner radius
    let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Use gradient background
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.8, alpha: 1.0),
        NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
    ])
    gradient?.draw(in: backgroundPath, angle: -45)
    
    // Draw headphones symbol (background layer)
    if let headphonesSymbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Audio") {
        let symbolSize = NSSize(width: iconSize.width * 0.74, height: iconSize.height * 0.74)
        let symbolRect = NSRect(
            x: (iconSize.width - symbolSize.width) / 2,
            y: (iconSize.height - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        NSColor.white.withAlphaComponent(0.9).setFill()
        headphonesSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    // Draw play icon on top (centered, slightly smaller)
    if let playSymbol = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play") {
        let playSize = NSSize(width: iconSize.width * 0.35, height: iconSize.height * 0.35)
        let playRect = NSRect(
            x: (iconSize.width - playSize.width) / 2 + playSize.width * 0.05,
            y: (iconSize.height - playSize.height) / 2,
            width: playSize.width,
            height: playSize.height
        )
        NSColor.white.setFill()
        playSymbol.draw(in: playRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    image.unlockFocus()
    
    return image
}

// Save PNG image
func savePNG(image: NSImage, path: String) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Failed to create CGImage")
        return
    }
    
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }
    
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

// Generate all icon sizes
let basePath = "SSChatMixApp/Assets.xcassets/AppIcon.appiconset"
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

print("Generating app icons...")
for (filename, size) in sizes {
    let icon = createAppIcon(size: size)
    savePNG(image: icon, path: "\(basePath)/\(filename)")
}
print("Done!")
