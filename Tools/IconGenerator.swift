import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.14, green: 0.38, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.42, green: 0.18, blue: 0.86, alpha: 1)
])!
gradient.draw(in: outer, angle: -45)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.white.setFill()
let card = NSBezierPath(roundedRect: NSRect(x: 205, y: 250, width: 614, height: 510), xRadius: 95, yRadius: 95)
card.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.90, alpha: 1).setFill()
let wallet = NSBezierPath(roundedRect: NSRect(x: 255, y: 365, width: 514, height: 285), xRadius: 58, yRadius: 58)
wallet.fill()

NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.90, alpha: 1).setFill()
let clasp = NSBezierPath(roundedRect: NSRect(x: 575, y: 438, width: 225, height: 135), xRadius: 48, yRadius: 48)
clasp.fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 632, y: 480, width: 50, height: 50)).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 150, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.92, alpha: 1)
]
let mark = NSAttributedString(string: "✓", attributes: attributes)
mark.draw(at: NSPoint(x: 438, y: 625))

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not create app icon")
}
try png.write(to: URL(fileURLWithPath: output))
