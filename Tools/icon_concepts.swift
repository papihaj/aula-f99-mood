// Five minimal app icon concepts for F99 Mood, plus a comparison sheet.
// swift Tools/icon_concepts.swift Resources/concepts
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/concepts")
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xff) / 255, green: CGFloat(h >> 8 & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: a)
}
let electric = [hex(0x00e5ff), hex(0x2962ff), hex(0x7c4dff), hex(0xd500f9)]

/// The macOS icon shape: a rounded square inset in the 1024 canvas.
func tile(_ s: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
}

func glow(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func render(_ size: CGFloat, _ body: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    body(size / 1024)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let concepts: [(String, String, (CGFloat) -> Void)] = [
    ("1-keycap", "One Key", { s in
        // Off-white tile, a single keycap seen from above, lit from underneath.
        hex(0xe6e6ee).setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        glow(NSPoint(x: 560 * s, y: 450 * s), 340 * s, hex(0xd500f9, 0.55))
        glow(NSPoint(x: 450 * s, y: 500 * s), 300 * s, hex(0x00b8ff, 0.6))
        NSGraphicsContext.current!.restoreGraphicsState()
        // Soft shadow so the key lifts off the tile.
        let shadow = NSShadow()
        shadow.shadowColor = hex(0x2a1a6e, 0.35); shadow.shadowBlurRadius = 40 * s
        shadow.shadowOffset = NSSize(width: 0, height: -14 * s)
        NSGraphicsContext.current!.saveGraphicsState(); shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 322 * s, y: 342 * s, width: 380 * s, height: 380 * s), xRadius: 70 * s, yRadius: 70 * s).fill()
        NSGraphicsContext.current!.restoreGraphicsState()
        let cap = NSBezierPath(roundedRect: NSRect(x: 322 * s, y: 342 * s, width: 380 * s, height: 380 * s), xRadius: 70 * s, yRadius: 70 * s)
        NSColor.white.setFill(); cap.fill()
        let top = NSBezierPath(roundedRect: NSRect(x: 372 * s, y: 412 * s, width: 280 * s, height: 270 * s), xRadius: 50 * s, yRadius: 50 * s)
        hex(0xf7f7fb).setFill(); top.fill()
        hex(0x000000, 0.06).setStroke(); cap.lineWidth = 3 * s; cap.stroke()
    }),
    ("2-strip", "The Strip", { s in
        // Near-black tile with one glowing vertical bar: the F99's light strip.
        hex(0x0d0d12).setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        glow(NSPoint(x: 512 * s, y: 512 * s), 330 * s, hex(0x7c4dff, 0.35))
        NSGraphicsContext.current!.restoreGraphicsState()
        let bar = NSBezierPath(roundedRect: NSRect(x: 472 * s, y: 262 * s, width: 80 * s, height: 500 * s), xRadius: 40 * s, yRadius: 40 * s)
        NSGradient(colors: electric)!.draw(in: bar, angle: 90)
    }),
    ("3-dots", "Mood Dots", { s in
        // A 3 × 3 grid of key dots; one glows.
        NSColor.white.setFill(); tile(s).fill()
        for row in 0..<3 { for col in 0..<3 {
            let c = NSPoint(x: (362 + CGFloat(col) * 150) * s, y: (362 + CGFloat(row) * 150) * s)
            let lit = row == 1 && col == 2
            if lit { glow(c, 150 * s, hex(0xd500f9, 0.35)) }
            let r: CGFloat = 42 * s
            let dot = NSBezierPath(roundedRect: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), xRadius: 16 * s, yRadius: 16 * s)
            if lit { NSGradient(colors: [hex(0x7c4dff), hex(0xd500f9)])!.draw(in: dot, angle: 45) }
            else { hex(0x1c1c22, 0.12).setFill(); dot.fill() }
        } }
    }),
    ("4-monogram", "F99 Monogram", { s in
        // Black tile, thin white F99 wordmark, one hairline of colour.
        NSColor.black.setFill(); tile(s).fill()
        let text = NSAttributedString(string: "F99", attributes: [
            .font: NSFont.systemFont(ofSize: 250 * s, weight: .light), .foregroundColor: NSColor.white, .kern: 10 * s])
        let size = text.size()
        text.draw(at: NSPoint(x: 512 * s - size.width / 2, y: 470 * s))
        let line = NSBezierPath(roundedRect: NSRect(x: 352 * s, y: 410 * s, width: 320 * s, height: 14 * s), xRadius: 7 * s, yRadius: 7 * s)
        NSGradient(colors: electric)!.draw(in: line, angle: 0)
    }),
    ("5-wave", "Sound Key", { s in
        // A keycap outline with a single sound wave through it.
        hex(0x111118).setFill(); tile(s).fill()
        let cap = NSBezierPath(roundedRect: NSRect(x: 272 * s, y: 302 * s, width: 480 * s, height: 420 * s), xRadius: 90 * s, yRadius: 90 * s)
        hex(0xffffff, 0.9).setStroke(); cap.lineWidth = 22 * s; cap.stroke()
        let wave = NSBezierPath()
        for i in 0...200 {
            let x = 332 + CGFloat(i) / 200 * 360
            let t = Double(i) / 200
            let y = 512 + CGFloat(sin(t * .pi * 4) * 90 * sin(t * .pi)) // fades in and out at the edges
            i == 0 ? wave.move(to: NSPoint(x: x * s, y: y * s)) : wave.line(to: NSPoint(x: x * s, y: y * s))
        }
        wave.lineWidth = 22 * s; wave.lineCapStyle = .round
        NSGraphicsContext.current!.saveGraphicsState()
        let stroke = wave.cgPath.copy(strokingWithWidth: 22 * s, lineCap: .round, lineJoin: .round, miterLimit: 10)
        NSBezierPath(cgPath: stroke).addClip()
        NSGradient(colors: electric)!.draw(in: NSRect(x: 320 * s, y: 380 * s, width: 384 * s, height: 270 * s), angle: 0)
        NSGraphicsContext.current!.restoreGraphicsState()
    }),
]

// Each concept at full size.
for (file, _, body) in concepts {
    try! render(1024, body).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(file).png"))
}

// The comparison sheet: each concept large, plus how it looks small in the Dock / Finder.
let width: CGFloat = 1800, height: CGFloat = 620
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
hex(0xe9e9ee).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
let title = NSAttributedString(string: "F99 Mood: minimal icon concepts", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: hex(0x1c1c22)])
title.draw(at: NSPoint(x: 40, y: height - 62))
for (i, (_, name, body)) in concepts.enumerated() {
    let x = 40 + CGFloat(i) * 350
    NSImage(size: NSSize(width: 300, height: 300), flipped: false) { _ in body(300.0 / 1024); return true }
        .draw(in: NSRect(x: x, y: 190, width: 300, height: 300))
    // Small sizes, as in the Dock and Finder lists.
    for (j, px) in [64.0, 32.0, 16.0].enumerated() {
        let offset = [0.0, 80.0, 128.0][j]
        NSImage(size: NSSize(width: px, height: px), flipped: false) { _ in body(CGFloat(px) / 1024); return true }
            .draw(in: NSRect(x: x + 40 + offset, y: 110 + (64 - px) / 2, width: px, height: px))
    }
    let label = NSAttributedString(string: "\(i + 1). \(name)", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: hex(0x1c1c22)])
    label.draw(at: NSPoint(x: x + 150 - label.size().width / 2, y: 50))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("concepts-sheet.png"))
print("Wrote \(out.path)")
