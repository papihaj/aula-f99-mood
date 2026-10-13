// Draws the F99 Mood app icon ("Wave across keys": a minimal keyboard, every
// key lit from cyan to magenta with a wave of light running through it) and
// writes Resources/AppIcon.icns and Resources/AppIcon.png.
// Run by build.sh when the icon is missing: swift Tools/make_icon.swift Resources
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xff) / 255, green: CGFloat(h >> 8 & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: a)
}
/// The "Electric" theme: cyan, blue, violet, magenta.
let electric = [hex(0x00e5ff), hex(0x2962ff), hex(0x7c4dff), hex(0xd500f9)]
func along(_ t: CGFloat) -> NSColor {
    let u = min(max(t, 0), 1) * CGFloat(electric.count - 1)
    let i = min(Int(u), electric.count - 2)
    return electric[i].blended(withFraction: u - CGFloat(i), of: electric[i + 1])!
}

func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Near-black macOS-shaped tile with a faint violet glow.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    hex(0x0d0d12).setFill(); tile.fill()
    NSGraphicsContext.current!.saveGraphicsState(); tile.addClip()
    let c = NSPoint(x: 512 * s, y: 512 * s)
    NSGradient(colors: [hex(0x7c4dff, 0.32), hex(0x7c4dff, 0)])!
        .draw(fromCenter: c, radius: 0, toCenter: c, radius: 360 * s, options: [])
    NSGraphicsContext.current!.restoreGraphicsState()

    // The keyboard case.
    let frame = NSRect(x: 190 * s, y: 372 * s, width: 644 * s, height: 280 * s)
    hex(0x1b1b24).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -34 * s, dy: -34 * s), xRadius: 50 * s, yRadius: 50 * s).fill()

    // Three rows of keys with a space bar, lit along the gradient, with a
    // wave of brightness passing through.
    let rows: [[CGFloat]] = [[1, 1, 1, 1, 1, 1, 1], [1.5, 1, 1, 1, 1, 1, 1.5], [1.25, 1.25, 4.5, 1.25, 1.25]]
    let gap = 18 * s, radius = 16 * s
    let keyH = (frame.height - gap * CGFloat(rows.count - 1)) / CGFloat(rows.count)
    for (r, row) in rows.enumerated() {
        let unitW = (frame.width - gap * CGFloat(row.count - 1)) / row.reduce(0, +)
        var x = frame.minX
        let y = frame.maxY - CGFloat(r + 1) * keyH - CGFloat(r) * gap
        for w in row {
            let k = NSRect(x: x, y: y, width: w * unitW, height: keyH)
            let t = (k.midX - frame.minX) / frame.width
            let wave = 0.5 + 0.5 * sin(t * .pi * 2.2 - CGFloat(r) * 1.2)
            hex(0x0d0d12).blended(withFraction: 0.35 + 0.65 * wave, of: along(t))!.setFill()
            NSBezierPath(roundedRect: k, xRadius: radius, yRadius: radius).fill()
            x += k.width + gap
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(CGFloat(px)).representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! draw(1024).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("AppIcon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)/AppIcon.icns" : "iconutil failed")
