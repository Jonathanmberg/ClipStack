// Renders the 1024px app icon: a stack of three clipboard cards on a blue tile.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)

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

let top = NSColor(calibratedRed: 0.40, green: 0.36, blue: 0.98, alpha: 1)
let bottom = NSColor(calibratedRed: 0.12, green: 0.52, blue: 0.98, alpha: 1)
NSGradient(starting: bottom, ending: top)!.draw(in: shape, angle: 90)

// Three cards, back to front; the back ones peek out above.
let cards: [(width: CGFloat, y: CGFloat, alpha: CGFloat)] = [(420, 520, 0.35), (500, 425, 0.6), (580, 300, 1)]
for card in cards {
    let rect = NSRect(x: 512 - card.width / 2, y: card.y, width: card.width, height: 340)
    let path = NSBezierPath(roundedRect: rect, xRadius: 52, yRadius: 52)
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.18)
    s.shadowBlurRadius = 24
    s.shadowOffset = NSSize(width: 0, height: -10)
    s.set()
    NSColor.white.withAlphaComponent(card.alpha).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

// "Text" lines on the front card.
let ink = NSColor(calibratedRed: 0.25, green: 0.40, blue: 0.98, alpha: 0.55)
ink.setFill()
for (y, w) in [(CGFloat(520), CGFloat(360)), (450, 280), (380, 200)] {
    NSBezierPath(roundedRect: NSRect(x: 512 - 290 + 70, y: y, width: w, height: 34), xRadius: 17, yRadius: 17).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
