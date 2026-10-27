// Génère l'icône (1024 px) : carré arrondi sombre Socle, fanion de héraut ambre marqué « H » et ondes d'annonce bleues.
import Cocoa
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: size - 200, height: size - 200), xRadius: 185, yRadius: 185).fill()
let accent = NSColor(srgbRed: 0x0e/255, green: 0xa5/255, blue: 0xe9/255, alpha: 1)
let amber = NSColor(srgbRed: 0xf5/255, green: 0x9e/255, blue: 0x0b/255, alpha: 1)
// Hampe
NSColor(white: 0.85, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 220, width: 34, height: 600), xRadius: 17, yRadius: 17).fill()
// Fanion à queue fendue
let flag = NSBezierPath()
flag.move(to: NSPoint(x: 296, y: 800))
flag.line(to: NSPoint(x: 640, y: 800))
flag.line(to: NSPoint(x: 560, y: 650))
flag.line(to: NSPoint(x: 640, y: 500))
flag.line(to: NSPoint(x: 296, y: 500))
flag.close()
amber.setFill(); flag.fill()
let font = NSFont.systemFont(ofSize: 210, weight: .heavy)
let s = NSAttributedString(string: "H", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1)])
let b = s.size()
s.draw(at: NSPoint(x: 420 - b.width / 2, y: 650 - b.height / 2 + 6))
// Ondes d'annonce
for (i, r) in [120.0, 200.0, 280.0].enumerated() {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 600, y: 360), radius: CGFloat(r), startAngle: -40, endAngle: 40)
    arc.lineWidth = 40 - CGFloat(i) * 6; arc.lineCapStyle = .round
    accent.withAlphaComponent(1 - CGFloat(i) * 0.25).setStroke(); arc.stroke()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
