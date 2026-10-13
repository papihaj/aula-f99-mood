// Round 2: minimal key grids where every key is lit, ramping from dim to bright.
// swift Tools/icon_concepts2.swift Resources/concepts
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/concepts")
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

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

/// One lit key: colour along the palette, brightness `level` (0.3 dim ... 1 full).
/// Dim keys are still clearly visible; brighter ones glow.
func key(_ rect: NSRect, _ s: CGFloat, hue t: CGFloat, level: CGFloat, dark: Bool) {
    let c = along(t)
    if level > 0.55 { glow(NSPoint(x: rect.midX, y: rect.midY), rect.width * 1.1, c.withAlphaComponent(0.35 * (level - 0.45))) }
    let shape = NSBezierPath(roundedRect: rect, xRadius: 18 * s, yRadius: 18 * s)
    let base = dark ? NSColor.black : NSColor.white
    base.blended(withFraction: 0.25 + 0.75 * level, of: c)!.setFill()
    shape.fill()
}

/// A grid of keys; `widths` per row in key units. `ramp` gives each key's 0...1 position for brightness.
func grid(_ s: CGFloat, rows: [[CGFloat]], dark: Bool, ramp: (CGFloat, CGFloat) -> CGFloat) {
    let unit: CGFloat = 132 * s, gap: CGFloat = 22 * s
    let n = CGFloat(rows.count)
    let width = rows.map { $0.reduce(0, +) * unit + CGFloat($0.count - 1) * gap }.max()!
    let height = n * unit + (n - 1) * gap
    var y = 512 * s + height / 2
    for (r, row) in rows.enumerated() {
        let rowWidth = row.reduce(0, +) * unit + CGFloat(row.count - 1) * gap
        let stretch = (width - CGFloat(row.count - 1) * gap) / (rowWidth - CGFloat(row.count - 1) * gap)
        var x = 512 * s - width / 2
        for w in row {
            let kw = w * unit * stretch
            let rect = NSRect(x: x, y: y - unit, width: kw, height: unit)
            let fx = (rect.midX - (512 * s - width / 2)) / width          // 0 left ... 1 right
            let fy = CGFloat(rows.count - 1 - r) / max(n - 1, 1)          // 0 bottom ... 1 top
            let p = ramp(fx, fy)
            key(rect, s, hue: p, level: 0.3 + 0.7 * p, dark: dark)
            x += kw + gap
        }
        y -= unit + gap
    }
}

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

let square: [[CGFloat]] = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
let board: [[CGFloat]] = [[1, 1, 1, 1], [1, 1, 1, 1], [1.5, 2, 1]]

let concepts: [(String, String, (CGFloat) -> Void)] = [
    ("6-ramp-dark", "Ramp, dark", { s in
        hex(0x0d0d12).setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        grid(s, rows: square, dark: true) { x, y in (x + y) / 2 }   // dim bottom-left → bright top-right
        NSGraphicsContext.current!.restoreGraphicsState()
    }),
    ("7-ramp-light", "Ramp, light", { s in
        NSColor.white.setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        grid(s, rows: square, dark: false) { x, y in (x + y) / 2 }
        NSGraphicsContext.current!.restoreGraphicsState()
    }),
    ("8-level-meter", "Level meter", { s in
        hex(0x0d0d12).setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        grid(s, rows: square, dark: true) { _, y in y }              // dim bottom row → bright top row
        NSGraphicsContext.current!.restoreGraphicsState()
    }),
    ("9-mini-board", "Mini keyboard", { s in
        hex(0x0d0d12).setFill(); tile(s).fill()
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        grid(s, rows: board, dark: true) { x, _ in x }               // dim left → bright right, with a space bar
        NSGraphicsContext.current!.restoreGraphicsState()
    }),
]

for (file, _, body) in concepts {
    try! render(1024, body).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(file).png"))
}

let width: CGFloat = 1460, height: CGFloat = 620
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
hex(0xe9e9ee).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
NSAttributedString(string: "F99 Mood: every key lit, dim to bright", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: hex(0x1c1c22)])
    .draw(at: NSPoint(x: 40, y: height - 62))
for (i, (_, name, body)) in concepts.enumerated() {
    let x = 40 + CGFloat(i) * 350
    NSImage(size: NSSize(width: 300, height: 300), flipped: false) { _ in body(300.0 / 1024); return true }
        .draw(in: NSRect(x: x, y: 190, width: 300, height: 300))
    for (j, px) in [64.0, 32.0, 16.0].enumerated() {
        let offset = [0.0, 80.0, 128.0][j]
        NSImage(size: NSSize(width: px, height: px), flipped: false) { _ in body(CGFloat(px) / 1024); return true }
            .draw(in: NSRect(x: x + 40 + offset, y: 110 + (64 - px) / 2, width: px, height: px))
    }
    let label = NSAttributedString(string: "\(i + 6). \(name)", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: hex(0x1c1c22)])
    label.draw(at: NSPoint(x: x + 150 - label.size().width / 2, y: 50))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("concepts-sheet-2.png"))
print("Wrote \(out.path)")
