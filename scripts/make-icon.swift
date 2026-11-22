// Draws the app icon: a dark grid with glowing warm-white pads.
import AppKit
let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(path); ctx.clip()
let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 0.24, alpha: 1).cgColor, NSColor(white: 0.10, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
ctx.restoreGState()
let lit: Set<Int> = [0, 5, 6, 9, 10, 15, 3, 12]
let n = 4, gap: CGFloat = 34, inset: CGFloat = 170
let cell = (824 - 2 * (inset - 100) - gap * CGFloat(n - 1)) / CGFloat(n)
for r in 0..<n { for c in 0..<n {
  let rect = CGRect(x: inset + CGFloat(c) * (cell + gap), y: inset + CGFloat(r) * (cell + gap), width: cell, height: cell)
  let p = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)
  let on = lit.contains(r * n + c)
  ctx.saveGState()
  if on { ctx.setShadow(offset: .zero, blur: 44, color: NSColor(red: 1, green: 0.88, blue: 0.66, alpha: 0.9).cgColor) }
  ctx.addPath(p)
  ctx.setFillColor(on ? NSColor(red: 1, green: 0.94, blue: 0.82, alpha: 1).cgColor : NSColor(white: 0.07, alpha: 1).cgColor)
  ctx.fillPath(); ctx.restoreGState()
}}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
