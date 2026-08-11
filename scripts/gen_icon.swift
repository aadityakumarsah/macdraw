import AppKit

// Generates the 1024x1024 master icon for macdraw.

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// Background: rounded rect with a purple → dark gradient.
let bg = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: 185,
    yRadius: 185
)
let gradient = NSGradient(colors: [
    NSColor(red: 0.42, green: 0.40, blue: 0.86, alpha: 1),
    NSColor(red: 0.13, green: 0.12, blue: 0.30, alpha: 1),
])!
gradient.draw(in: bg, angle: -90)

// Hand-drawn white squiggle with a soft glow.
let pts: [CGPoint] = (0...240).map { i in
    let t = CGFloat(i) / 240
    let x = 180 + t * 664
    let y = 430 + 150 * sin(t * 6.4 + 1.2) + 70 * sin(t * 15.1)
    return CGPoint(x: x, y: y)
}

let path = NSBezierPath()
path.move(to: pts[0])
for p in pts.dropFirst() { path.line(to: p) }
path.lineCapStyle = .round
path.lineJoinStyle = .round
path.lineWidth = 62

let glow = NSShadow()
glow.shadowColor = NSColor.white.withAlphaComponent(0.35)
glow.shadowBlurRadius = 40
glow.shadowOffset = .zero
glow.set()

NSColor.white.setStroke()
path.stroke()

// Laser tip: glowing red dot at the end of the line.
let tip = pts.last!
let tipGlow = NSShadow()
tipGlow.shadowColor = NSColor(red: 1, green: 0.24, blue: 0.18, alpha: 0.9)
tipGlow.shadowBlurRadius = 60
tipGlow.shadowOffset = .zero
tipGlow.set()

let dot = NSBezierPath(ovalIn: NSRect(x: tip.x - 56, y: tip.y - 56, width: 112, height: 112))
NSColor(red: 1, green: 0.24, blue: 0.18, alpha: 1).setFill()
dot.fill()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
