// Renders the 1024px app icon.
// Usage: swift scripts/make-icon.swift out.png [artwork.png]
//   With artwork: the image is placed on Apple's macOS icon grid (rounded square + shadow).
//   Without: a built-in placeholder (stack of cards on a blue tile).
import AppKit

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSGraphicsContext.current?.imageInterpolation = .high

// Apple's macOS icon grid: 824px rounded square centered on a 1024px canvas, with a soft shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 20
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()

if CommandLine.arguments.count > 2, let art = NSImage(contentsOfFile: CommandLine.arguments[2]) {
    // Fill the tile, cropping to a centered square if the artwork isn't square.
    let s = min(art.size.width, art.size.height)
    let from = NSRect(x: (art.size.width - s) / 2, y: (art.size.height - s) / 2, width: s, height: s)
    art.draw(in: tile, from: from, operation: .sourceOver, fraction: 1)
} else {
    let top = NSColor(calibratedRed: 0.40, green: 0.36, blue: 0.98, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.12, green: 0.52, blue: 0.98, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: shape, angle: 90)
    let cards: [(width: CGFloat, y: CGFloat, alpha: CGFloat)] = [(420, 520, 0.35), (500, 425, 0.6), (580, 300, 1)]
    for card in cards {
        let rect = NSRect(x: 512 - card.width / 2, y: card.y, width: card.width, height: 340)
        NSColor.white.withAlphaComponent(card.alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 52, yRadius: 52).fill()
    }
}

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
