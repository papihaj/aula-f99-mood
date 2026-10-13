// Round 5: minimal keyboards. Only a few keys and a space bar.
// Near-black tile, Electric colours. swift Tools/icon_concepts5.swift Resources/concepts
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
func background(_ s: CGFloat) {
    hex(0x0d0d12).setFill(); tile(s).fill()
    NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
    glow(NSPoint(x: 512 * s, y: 512 * s), 360 * s, hex(0x7c4dff, 0.32))
    NSGraphicsContext.current!.restoreGraphicsState()
}
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
func strokeGradient(_ path: NSBezierPath, width: CGFloat) {
    let outline = NSBezierPath(cgPath: path.cgPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
    gradient.draw(in: outline, angle: 0)
}
/// Keys in a row across [x0, x0 + w], each `size` tall at `y`.
func row(_ count: Int, x0: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat, gap: CGFloat, _ s: CGFloat,
         draw: (NSRect, CGFloat) -> Void) {
    let kw = (w - gap * CGFloat(count - 1)) / CGFloat(count)
    for i in 0..<count {
        let rect = r(x0 + CGFloat(i) * (kw + gap), y, kw, size, s)
        draw(rect, (CGFloat(i) + 0.5) / CGFloat(count))
    }
}

let concepts: [(String, String, (CGFloat) -> Void)] = [
    ("26-two-rows", "Two rows", { s in
        background(s)
        // Four keys over a space bar, all lit along the gradient.
        row(4, x0: 262, y: 520, w: 500, size: 110, gap: 20, s) { k, t in along(t).setFill(); rounded(k, 26 * s).fill() }
        gradient.draw(in: rounded(r(352, 390, 320, 100, s), 26 * s), angle: 0)
    }),
    ("27-symbol", "Keyboard symbol", { s in
        background(s)
        // Like the macOS keyboard symbol: an outline, two rows of dots, a space bar.
        strokeGradient(rounded(r(222, 322, 580, 380, s), 70 * s), width: 30 * s)
        for (y, n) in [(CGFloat(560), 5), (CGFloat(470), 5)] {
            for i in 0..<n {
                let x = 322 + CGFloat(i) * 95
                let d = rounded(r(x, y, 50, 50, s), 14 * s)
                along(CGFloat(i) / CGFloat(n - 1)).setFill(); d.fill()
            }
        }
        gradient.draw(in: rounded(r(382, 382, 260, 46, s), 23 * s), angle: 0)
    }),
    ("28-three-keys", "Three keys", { s in
        background(s)
        // Three big keys and a space bar: bold enough for the Dock.
        row(3, x0: 252, y: 512, w: 520, size: 160, gap: 30, s) { k, t in along(t).setFill(); rounded(k, 36 * s).fill() }
        gradient.draw(in: rounded(r(252, 352, 520, 120, s), 36 * s), angle: 0)
    }),
    ("29-white-glow", "White keys, glow", { s in
        background(s)
        // White caps lit from underneath: the keys are visible, the colour is the light.
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        glow(NSPoint(x: 420 * s, y: 430 * s), 260 * s, hex(0x00e5ff, 0.55))
        glow(NSPoint(x: 620 * s, y: 450 * s), 260 * s, hex(0xd500f9, 0.55))
        NSGraphicsContext.current!.restoreGraphicsState()
        row(4, x0: 262, y: 520, w: 500, size: 110, gap: 20, s) { k, _ in hex(0xf3f3f8).setFill(); rounded(k, 26 * s).fill() }
        hex(0xf3f3f8).setFill(); rounded(r(352, 390, 320, 100, s), 26 * s).fill()
    }),
    ("30-outline-space", "Outline, lit space bar", { s in
        background(s)
        // Keys as faint outlines; only the space bar lights up.
        hex(0xffffff, 0.45).setStroke()
        row(4, x0: 262, y: 520, w: 500, size: 110, gap: 20, s) { k, _ in
            let p = rounded(k, 26 * s); p.lineWidth = 12 * s; p.stroke()
        }
        let space = rounded(r(352, 390, 320, 100, s), 26 * s)
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        glow(NSPoint(x: 512 * s, y: 440 * s), 260 * s, hex(0x7c4dff, 0.5))
        NSGraphicsContext.current!.restoreGraphicsState()
        gradient.draw(in: space, angle: 0)
    }),
    ("31-slab", "Slab", { s in
        background(s)
        // A slim keyboard slab with one row of keys and a space bar.
        hex(0x1b1b24).setFill(); rounded(r(212, 362, 600, 300, s), 56 * s).fill()
        row(5, x0: 262, y: 532, w: 500, size: 80, gap: 18, s) { k, t in along(t).setFill(); rounded(k, 20 * s).fill() }
        gradient.draw(in: rounded(r(342, 412, 340, 80, s), 20 * s), angle: 0)
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

let cols = 3, cell: CGFloat = 420
let width = 40 + CGFloat(cols) * cell, height: CGFloat = 1240
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
hex(0xe9e9ee).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
NSAttributedString(string: "F99 Mood: minimal keyboards", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: hex(0x1c1c22)])
    .draw(at: NSPoint(x: 40, y: height - 62))
for (i, (_, name, body)) in concepts.enumerated() {
    let x = 40 + CGFloat(i % cols) * cell
    let top = i < cols ? height - 100 : height - 680
    NSImage(size: NSSize(width: 360, height: 360), flipped: false) { _ in body(360.0 / 1024); return true }
        .draw(in: NSRect(x: x, y: top - 360, width: 360, height: 360))
    for (j, px) in [64.0, 32.0, 16.0].enumerated() {
        let offset = [0.0, 80.0, 128.0][j]
        NSImage(size: NSSize(width: px, height: px), flipped: false) { _ in body(CGFloat(px) / 1024); return true }
            .draw(in: NSRect(x: x + 80 + offset, y: top - 450 + (64 - px) / 2, width: px, height: px))
    }
    let label = NSAttributedString(string: "\(i + 26). \(name)", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: hex(0x1c1c22)])
    label.draw(at: NSPoint(x: x + 180 - label.size().width / 2, y: top - 510))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("concepts-sheet-5.png"))
print("Wrote \(out.path)")
