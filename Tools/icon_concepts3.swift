// Round 3: ten minimal concepts in the style of "The Strip": near-black tile,
// Electric colours, a soft glow. swift Tools/icon_concepts3.swift Resources/concepts
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/concepts")
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xff) / 255, green: CGFloat(h >> 8 & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: a)
}
let electric = [hex(0x00e5ff), hex(0x2962ff), hex(0x7c4dff), hex(0xd500f9)]
let gradient = NSGradient(colors: electric)!

func along(_ t: CGFloat) -> NSColor {
    let u = min(max(t, 0), 1) * CGFloat(electric.count - 1)
    let i = min(Int(u), electric.count - 2)
    return electric[i].blended(withFraction: u - CGFloat(i), of: electric[i + 1])!
}
func tile(_ s: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
}
func glow(_ c: NSPoint, _ r: CGFloat, _ color: NSColor) {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!.draw(fromCenter: c, radius: 0, toCenter: c, radius: r, options: [])
}
func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
func pill(_ r: NSRect) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: min(r.width, r.height) / 2, yRadius: min(r.width, r.height) / 2) }
/// Fill any path with the Electric gradient.
func fillGradient(_ path: NSBezierPath, angle: CGFloat = 90) { gradient.draw(in: path, angle: angle) }
/// Stroke a path with the gradient.
func strokeGradient(_ path: NSBezierPath, width: CGFloat, angle: CGFloat = 0) {
    let outline = NSBezierPath(cgPath: path.cgPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
    gradient.draw(in: outline, angle: angle)
}

/// The shared background: near-black tile with a faint violet glow.
func background(_ s: CGFloat, glowAt c: NSPoint? = nil, radius: CGFloat = 330) {
    hex(0x0d0d12).setFill(); tile(s).fill()
    NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
    glow(c ?? pt(512, 512, s), radius * s, hex(0x7c4dff, 0.35))
    NSGraphicsContext.current!.restoreGraphicsState()
}

let concepts: [(String, String, (CGFloat) -> Void)] = [
    ("10-strip-key", "Strip + key", { s in
        background(s)
        let key = NSBezierPath(roundedRect: rect(332, 412, 200, 200, s), xRadius: 40 * s, yRadius: 40 * s)
        hex(0xffffff, 0.92).setFill(); key.fill()
        fillGradient(pill(rect(592, 302, 64, 420, s)))
    }),
    ("11-light-bar", "Light bar", { s in
        background(s, glowAt: pt(512, 430, s))
        let key = NSBezierPath(roundedRect: rect(362, 482, 300, 220, s), xRadius: 50 * s, yRadius: 50 * s)
        hex(0xffffff, 0.12).setFill(); key.fill()
        hex(0xffffff, 0.5).setStroke(); key.lineWidth = 10 * s; key.stroke()
        fillGradient(pill(rect(312, 380, 400, 44, s)), angle: 0)
    }),
    ("12-three-bars", "Three bars", { s in
        background(s)
        for (i, h) in [CGFloat(220), 380, 520].enumerated() {
            let x = 332 + CGFloat(i) * 130
            fillGradient(pill(rect(x, 252, 100, h, s)))
        }
    }),
    ("13-glow-outline", "Glowing key", { s in
        background(s)
        let key = NSBezierPath(roundedRect: rect(292, 292, 440, 440, s), xRadius: 100 * s, yRadius: 100 * s)
        strokeGradient(key, width: 30 * s, angle: 45)
    }),
    ("14-ring", "Mood ring", { s in
        background(s)
        let ring = NSBezierPath(ovalIn: rect(282, 282, 460, 460, s))
        strokeGradient(ring, width: 54 * s, angle: 45)
    }),
    ("15-four-lights", "Four lights", { s in
        background(s)
        // The F99's strip as its four separate lights, dim to bright.
        for i in 0..<4 {
            let r = pill(rect(462, 262 + CGFloat(i) * 130, 100, 100, s))
            along(CGFloat(i) / 3).withAlphaComponent(0.45 + 0.55 * CGFloat(i) / 3).setFill(); r.fill()
        }
    }),
    ("16-orb", "Orb", { s in
        hex(0x0d0d12).setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        glow(pt(460, 560, s), 330 * s, hex(0x00e5ff, 0.75))
        glow(pt(580, 470, s), 330 * s, hex(0xd500f9, 0.7))
        glow(pt(512, 512, s), 170 * s, hex(0xffffff, 0.35))
        NSGraphicsContext.current!.restoreGraphicsState()
    }),
    ("17-solid-key", "Lit key", { s in
        background(s)
        let shadow = NSShadow()
        shadow.shadowColor = hex(0xd500f9, 0.6); shadow.shadowBlurRadius = 80 * s
        NSGraphicsContext.current!.saveGraphicsState(); shadow.set()
        hex(0x7c4dff).setFill()
        let key = NSBezierPath(roundedRect: rect(322, 322, 380, 380, s), xRadius: 80 * s, yRadius: 80 * s)
        key.fill()
        NSGraphicsContext.current!.restoreGraphicsState()
        fillGradient(key, angle: 45)
    }),
    ("18-f-mark", "F mark", { s in
        background(s)
        // A geometric F made of three rounded bars.
        fillGradient(pill(rect(362, 272, 90, 480, s)))
        fillGradient(pill(rect(362, 662, 300, 90, s)), angle: 0)
        fillGradient(pill(rect(362, 482, 230, 90, s)), angle: 0)
    }),
    ("19-wave", "Wave", { s in
        background(s)
        let wave = NSBezierPath()
        for i in 0...240 {
            let t = Double(i) / 240
            let x = 262 + CGFloat(t) * 500
            let y = 512 + CGFloat(sin(t * .pi * 3) * 140 * sin(t * .pi))
            i == 0 ? wave.move(to: pt(x, y, s)) : wave.line(to: pt(x, y, s))
        }
        strokeGradient(wave, width: 48 * s, angle: 0)
    }),
]

func render(_ size: CGFloat, _ body: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body(size / 1024)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
for (file, _, body) in concepts {
    try! render(1024, body).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(file).png"))
}

// Sheet: two rows of five, each large plus Dock / Finder sizes.
let cols = 5, cell: CGFloat = 340
let width = 40 + CGFloat(cols) * cell, height: CGFloat = 1120
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
hex(0xe9e9ee).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
NSAttributedString(string: "F99 Mood: ten more, in the style of \"The Strip\"", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: hex(0x1c1c22)])
    .draw(at: NSPoint(x: 40, y: height - 62))
for (i, (_, name, body)) in concepts.enumerated() {
    let x = 40 + CGFloat(i % cols) * cell
    let top = i < cols ? height - 110 : height - 610
    NSImage(size: NSSize(width: 280, height: 280), flipped: false) { _ in body(280.0 / 1024); return true }
        .draw(in: NSRect(x: x, y: top - 280, width: 280, height: 280))
    for (j, px) in [64.0, 32.0, 16.0].enumerated() {
        let offset = [0.0, 80.0, 128.0][j]
        NSImage(size: NSSize(width: px, height: px), flipped: false) { _ in body(CGFloat(px) / 1024); return true }
            .draw(in: NSRect(x: x + 40 + offset, y: top - 370 + (64 - px) / 2, width: px, height: px))
    }
    let label = NSAttributedString(string: "\(i + 10). \(name)", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: hex(0x1c1c22)])
    label.draw(at: NSPoint(x: x + 140 - label.size().width / 2, y: top - 440))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("concepts-sheet-3.png"))
print("Wrote \(out.path)")
