// Round 4: minimal icons that clearly show a keyboard. Near-black tile,
// Electric colours. swift Tools/icon_concepts4.swift Resources/concepts
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
func background(_ s: CGFloat, glowY: CGFloat = 512) {
    hex(0x0d0d12).setFill(); tile(s).fill()
    NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
    glow(NSPoint(x: 512 * s, y: glowY * s), 360 * s, hex(0x7c4dff, 0.32))
    NSGraphicsContext.current!.restoreGraphicsState()
}

/// Key rows in key units, top row first. 0 means a gap of that many units' width... use negative for gaps.
typealias Rows = [[CGFloat]]
/// Main block, number pad and the light strip, F99-style (simplified).
let mainRows: Rows = [[1, 1, 1, 1, 1, 1], [1.5, 1, 1, 1, 1, 1.5], [1.75, 1, 1, 1, 2.25], [1.25, 1.25, 4, 1.25]]
let padRows: Rows = [[1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1], [2, 1, 1]]
let simpleRows: Rows = [[1, 1, 1, 1, 1, 1, 1], [1.5, 1, 1, 1, 1, 1, 1.5], [1.25, 1.25, 4.5, 1.25, 1.25]]

/// Draw `rows` of keys filling `frame`. `style(position x 0...1, row 0...1 top→bottom)` returns
/// (fill colour or nil, outline colour or nil).
func keys(_ rows: Rows, in frame: NSRect, gap: CGFloat, radius: CGFloat,
          style: (CGFloat, CGFloat) -> (NSColor?, NSColor?), lineWidth: CGFloat = 0) {
    let n = CGFloat(rows.count)
    let keyH = (frame.height - gap * (n - 1)) / n
    for (r, row) in rows.enumerated() {
        let units = row.reduce(0, +)
        let unitW = (frame.width - gap * CGFloat(row.count - 1)) / units
        var x = frame.minX
        let y = frame.maxY - CGFloat(r + 1) * keyH - CGFloat(r) * gap
        for w in row {
            let k = NSRect(x: x, y: y, width: w * unitW, height: keyH)
            let (fill, line) = style((k.midX - frame.minX) / frame.width, n > 1 ? CGFloat(r) / (n - 1) : 0)
            let p = NSBezierPath(roundedRect: k, xRadius: radius, yRadius: radius)
            if let fill { fill.setFill(); p.fill() }
            if let line { line.setStroke(); p.lineWidth = lineWidth; p.stroke() }
            x += k.width + gap
        }
    }
}

/// A simplified F99: main block, light strip, number pad, on a dark case.
func f99(_ s: CGFloat, case caseRect: NSRect, style: (CGFloat, CGFloat) -> (NSColor?, NSColor?),
         strip: NSColor?, lineWidth: CGFloat = 0, caseColor: NSColor? = hex(0x1b1b24)) {
    let pad = caseRect.height * 0.12
    if let caseColor {
        caseColor.setFill()
        NSBezierPath(roundedRect: caseRect, xRadius: 40 * s, yRadius: 40 * s).fill()
    }
    let inner = caseRect.insetBy(dx: pad, dy: pad)
    let gap = inner.height * 0.07
    // Split the width so main-block and number-pad keys come out the same size
    // (6 key units across the main block, 4 across the pad).
    let stripW = inner.width * 0.03
    let room = inner.width - stripW - gap * 4
    let unit = (room - gap * 8) / 10
    let mainW = unit * 6 + gap * 5
    let padW = room - mainW
    let main = NSRect(x: inner.minX, y: inner.minY, width: mainW, height: inner.height)
    let stripRect = NSRect(x: main.maxX + gap * 2, y: inner.minY + inner.height * 0.32, width: stripW, height: inner.height * 0.68)
    let padRect = NSRect(x: stripRect.maxX + gap * 2, y: inner.minY, width: padW, height: inner.height)
    keys(mainRows, in: main, gap: gap, radius: gap * 0.8, style: { x, r in style(x * mainW / inner.width, r) }, lineWidth: lineWidth)
    keys(padRows, in: padRect, gap: gap, radius: gap * 0.8,
         style: { x, r in style((padRect.minX - inner.minX + x * padW) / inner.width, r) }, lineWidth: lineWidth)
    if let strip {
        glow(NSPoint(x: stripRect.midX, y: stripRect.midY), stripRect.height * 0.7, strip.withAlphaComponent(0.45))
        NSGradient(colors: electric)!.draw(in: NSBezierPath(roundedRect: stripRect, xRadius: stripW / 2, yRadius: stripW / 2), angle: 90)
    }
}

let concepts: [(String, String, (CGFloat) -> Void)] = [
    ("20-f99-glow", "F99, glowing", { s in
        background(s)
        f99(s, case: NSRect(x: 150 * s, y: 362 * s, width: 724 * s, height: 300 * s),
            style: { x, _ in (along(x), nil) }, strip: hex(0xd500f9))
    }),
    ("21-f99-outline", "F99, line art", { s in
        background(s)
        f99(s, case: NSRect(x: 150 * s, y: 362 * s, width: 724 * s, height: 300 * s),
            style: { x, _ in (nil, along(x)) }, strip: hex(0xd500f9), lineWidth: 7 * s, caseColor: nil)
        let outline = NSBezierPath(roundedRect: NSRect(x: 150 * s, y: 362 * s, width: 724 * s, height: 300 * s), xRadius: 40 * s, yRadius: 40 * s)
        hex(0xffffff, 0.35).setStroke(); outline.lineWidth = 6 * s; outline.stroke()
    }),
    ("22-f99-white-keys", "F99, white keys", { s in
        background(s, glowY: 470)
        // Keys you can read (white caps), with the glow underneath like underglow.
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        glow(NSPoint(x: 380 * s, y: 400 * s), 300 * s, hex(0x00e5ff, 0.45))
        glow(NSPoint(x: 680 * s, y: 420 * s), 300 * s, hex(0xd500f9, 0.45))
        NSGraphicsContext.current!.restoreGraphicsState()
        f99(s, case: NSRect(x: 150 * s, y: 362 * s, width: 724 * s, height: 300 * s),
            style: { _, _ in (hex(0xf2f2f7), nil) }, strip: hex(0xd500f9), caseColor: hex(0x1b1b24, 0.85))
    }),
    ("23-simple-board", "Simple keyboard", { s in
        background(s)
        let frame = NSRect(x: 190 * s, y: 372 * s, width: 644 * s, height: 280 * s)
        hex(0x1b1b24).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: -34 * s, dy: -34 * s), xRadius: 50 * s, yRadius: 50 * s).fill()
        keys(simpleRows, in: frame, gap: 18 * s, radius: 16 * s, style: { x, r in (along(x).withAlphaComponent(1 - r * 0.35), nil) })
    }),
    ("24-wave-board", "Wave across keys", { s in
        background(s)
        let frame = NSRect(x: 190 * s, y: 372 * s, width: 644 * s, height: 280 * s)
        hex(0x1b1b24).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: -34 * s, dy: -34 * s), xRadius: 50 * s, yRadius: 50 * s).fill()
        // Every key lit; brightness follows a wave, like an effect running.
        keys(simpleRows, in: frame, gap: 18 * s, radius: 16 * s, style: { x, r in
            let wave = 0.5 + 0.5 * sin(x * .pi * 2.2 - r * 1.2)
            return (hex(0x0d0d12).blended(withFraction: 0.35 + 0.65 * wave, of: along(x))!, nil)
        })
    }),
    ("25-big-crop", "Close-up keys", { s in
        background(s)
        // A big corner of a keyboard: five keys, unmistakably keycaps.
        NSGraphicsContext.current!.saveGraphicsState(); tile(s).addClip()
        let unit: CGFloat = 230 * s, gap: CGFloat = 34 * s
        let rows: [[CGFloat]] = [[1, 1, 1, 1], [1.5, 1, 1, 1], [1.25, 2.6, 1]]
        var y: CGFloat = 820 * s
        for (r, row) in rows.enumerated() {
            var x: CGFloat = (r == 0 ? 160 : 130) * s
            for w in row {
                let k = NSRect(x: x, y: y - unit, width: w * unit + (w - 1) * gap, height: unit)
                let t = (k.midX / s - 100) / 824
                let cap = NSBezierPath(roundedRect: k, xRadius: 44 * s, yRadius: 44 * s)
                along(t).withAlphaComponent(0.25 + 0.6 * t).setFill(); cap.fill()
                let top = NSBezierPath(roundedRect: k.insetBy(dx: 26 * s, dy: 30 * s).offsetBy(dx: 0, dy: 10 * s), xRadius: 30 * s, yRadius: 30 * s)
                NSColor(white: 1, alpha: 0.12).setFill(); top.fill()
                x += k.width + gap
            }
            y -= unit + gap
        }
        NSGraphicsContext.current!.restoreGraphicsState()
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
NSAttributedString(string: "F99 Mood: keyboard icons", attributes: [
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
    let label = NSAttributedString(string: "\(i + 20). \(name)", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: hex(0x1c1c22)])
    label.draw(at: NSPoint(x: x + 180 - label.size().width / 2, y: top - 510))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("concepts-sheet-4.png"))
print("Wrote \(out.path)")
