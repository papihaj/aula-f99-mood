// Round 6: number 24 ("Wave across keys"), simplified. Every key lit, with a
// lighting wave running through, fewer keys. swift Tools/icon_concepts6.swift Resources/concepts
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/concepts")

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xff) / 255, green: CGFloat(h >> 8 & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: a)
}
let electric = [hex(0x00e5ff), hex(0x2962ff), hex(0x7c4dff), hex(0xd500f9)]
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
func background(_ s: CGFloat) {
    hex(0x0d0d12).setFill(); tile(s).fill()
    NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
    glow(NSPoint(x: 512 * s, y: 512 * s), 360 * s, hex(0x7c4dff, 0.32))
    NSGraphicsContext.current!.restoreGraphicsState()
}

/// Rows of keys (widths in key units) filling `frame`, each lit along the
/// gradient with a wave of brightness passing through, as in number 24.
func waveKeys(_ rows: [[CGFloat]], frame: NSRect, gap: CGFloat, radius: CGFloat, waves: CGFloat = 1.1) {
    let n = CGFloat(rows.count)
    let keyH = (frame.height - gap * (n - 1)) / n
    for (r, row) in rows.enumerated() {
        let unitW = (frame.width - gap * CGFloat(row.count - 1)) / row.reduce(0, +)
        var x = frame.minX
        let y = frame.maxY - CGFloat(r + 1) * keyH - CGFloat(r) * gap
        for w in row {
            let k = NSRect(x: x, y: y, width: w * unitW, height: keyH)
            let t = (k.midX - frame.minX) / frame.width
            let wave = 0.5 + 0.5 * sin(t * .pi * 2 * waves - CGFloat(r) * 1.2)
            hex(0x0d0d12).blended(withFraction: 0.35 + 0.65 * wave, of: along(t))!.setFill()
            NSBezierPath(roundedRect: k, xRadius: radius, yRadius: radius).fill()
            x += k.width + gap
        }
    }
}
func slab(_ frame: NSRect, _ s: CGFloat) {
    hex(0x1b1b24).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -34 * s, dy: -34 * s), xRadius: 50 * s, yRadius: 50 * s).fill()
}

let concepts: [(String, String, (CGFloat) -> Void)] = [
    ("24-wave-board", "24 (for comparison)", { s in
        background(s)
        let f = NSRect(x: 190 * s, y: 372 * s, width: 644 * s, height: 280 * s)
        slab(f, s)
        waveKeys([[1, 1, 1, 1, 1, 1, 1], [1.5, 1, 1, 1, 1, 1, 1.5], [1.25, 1.25, 4.5, 1.25, 1.25]], frame: f, gap: 18 * s, radius: 16 * s)
    }),
    ("32-wave-five", "24, fewer keys", { s in
        background(s)
        let f = NSRect(x: 232 * s, y: 382 * s, width: 560 * s, height: 260 * s)
        slab(f, s)
        waveKeys([[1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 3, 1]], frame: f, gap: 22 * s, radius: 20 * s)
    }),
    ("33-wave-no-case", "24, no case", { s in
        background(s)
        let f = NSRect(x: 232 * s, y: 382 * s, width: 560 * s, height: 260 * s)
        waveKeys([[1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 3, 1]], frame: f, gap: 22 * s, radius: 22 * s)
    }),
    ("34-wave-two-rows", "24, two rows", { s in
        background(s)
        let f = NSRect(x: 252 * s, y: 412 * s, width: 520 * s, height: 200 * s)
        slab(f, s)
        waveKeys([[1, 1, 1, 1], [1, 2, 1]], frame: f, gap: 24 * s, radius: 24 * s, waves: 0.9)
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

let cols = 4, cell: CGFloat = 400
let width = 40 + CGFloat(cols) * cell, height: CGFloat = 660
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
hex(0xe9e9ee).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
NSAttributedString(string: "F99 Mood: number 24, simplified", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: hex(0x1c1c22)])
    .draw(at: NSPoint(x: 40, y: height - 62))
for (i, (_, name, body)) in concepts.enumerated() {
    let x = 40 + CGFloat(i) * cell
    let top = height - 100
    NSImage(size: NSSize(width: 340, height: 340), flipped: false) { _ in body(340.0 / 1024); return true }
        .draw(in: NSRect(x: x, y: top - 340, width: 340, height: 340))
    for (j, px) in [64.0, 32.0, 16.0].enumerated() {
        let offset = [0.0, 80.0, 128.0][j]
        NSImage(size: NSSize(width: px, height: px), flipped: false) { _ in body(CGFloat(px) / 1024); return true }
            .draw(in: NSRect(x: x + 70 + offset, y: top - 430 + (64 - px) / 2, width: px, height: px))
    }
    let label = NSAttributedString(string: i == 0 ? name : "\(i + 31). \(name)", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: hex(0x1c1c22)])
    label.draw(at: NSPoint(x: x + 170 - label.size().width / 2, y: top - 490))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("concepts-sheet-6.png"))
print("Wrote \(out.path)")
