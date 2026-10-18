import AppKit

/// Effects the Mac draws and streams to the keyboard, about 20 frames a
/// second, in the style of popular effects from other brands. The F99's own
/// firmware only has its 18 effects; these run while F99 Mood is open.
enum LiveEffect: String, Codable, CaseIterable, Identifiable {
    case cascade = "Neon Cascade"
    case matrix = "Matrix Rain"
    case fire = "Fire"
    case aurora = "Aurora"
    case starlight = "Starlight"
    case comet = "Comet"
    case visor = "Visor"
    case lavaLamp = "Lava Lamp"
    case plasma = "Plasma"
    case heartbeat = "Heartbeat"
    case galaxy = "Galaxy"
    case spiral = "Spiral Rainbow"
    case candle = "Candlelight"
    case typingRipples = "Typing Ripples"
    case typingHeatmap = "Typing Heatmap"
    case painted = "Painted keys"
    case ripples = "Ripples"
    var id: String { rawValue }

    /// The live effects the mood editor offers. The others move like one of
    /// these or like a keyboard effect; they still work in saved moods.
    static let offered: [LiveEffect] = [.cascade, .aurora, .matrix, .fire, .ripples, .typingRipples, .typingHeatmap, .painted]

    var reactsToTyping: Bool { self == .typingRipples || self == .typingHeatmap || self == .cascade }

    /// Pressed keys flash bright with a halo of the palette's lightest colour,
    /// on top of the effect (with the "Light up keys I press" setting on its
    /// default, only Neon Cascade; it can be turned on for every effect).
    var pressGlow: Bool { self == .cascade }

    /// The typing effects draw presses themselves; the glow would hide them.
    var drawsPresses: Bool { self == .typingRipples || self == .typingHeatmap }

    /// Colours used when the mood is set to "colourful".
    var palette: MusicPalette {
        func p(_ hex: [UInt32]) -> MusicPalette { MusicPalette(name: rawValue, colors: hex.map { RGB(hex: $0) }) }
        switch self {
        case .cascade: return MusicPalette.neonElectric
        case .matrix: return p([0x002b0a, 0x00ff41, 0xc8ffd2])
        case .fire, .candle: return p([0x3a0000, 0xff2a00, 0xff8a00, 0xffd36b])
        case .aurora: return p([0x00ff9c, 0x00c2ff, 0x7c4dff, 0xff4fd8])
        case .starlight, .galaxy: return p([0x1a0b5e, 0x5b2bff, 0x00d0ff, 0xffffff])
        case .comet, .visor: return p([0xff0055, 0xff7a00, 0x00e5ff])
        case .lavaLamp: return p([0x3b0a78, 0xd500f9, 0xff6d00])
        case .heartbeat: return p([0x400000, 0xff1744, 0xff8a80])
        case .typingHeatmap: return p([0x0033ff, 0x00e676, 0xffea00, 0xff1744])
        case .ripples: return MusicPalette.electric
        case .plasma, .spiral, .typingRipples, .painted:
            return MusicPalette.presets.first { $0.name == "Rainbow" }!
        }
    }
}

/// Paints live effects.
final class LiveRenderer {
    var effect: LiveEffect = .aurora
    var palette: MusicPalette = LiveEffect.aurora.palette
    /// 0...1, from the mood's brightness.
    var brightnessScale = 1.0
    /// From the mood's speed setting (0-4).
    var speed = 2
    /// The dimmest any key may get, 0...1 ("Keep every key lit" sets about
    /// half, so the letters stay readable).
    var minimumBrightness = 0.0
    /// Draw the press glow on top of the effect.
    var pressGlow = false
    /// The glow's colour; nil uses the palette's lightest colour.
    var pressColor: RGB? = nil
    /// Halo size around a pressed key: 0 none, 1 normal, 2 large.
    var haloSize = 1.0
    /// Seconds for a pressed key to fade.
    var pressFade = 0.45
    /// Painted keys: a colour per LED (over any effect), and for the
    /// Painted keys effect, the colour of the rest.
    var paint: [Int: RGB] = [:]
    var paintBase: RGB? = nil

    private var start = Date()
    private var presses: [(led: Int, x: Double, y: Double, at: Date)] = []
    private var heat = [Double](repeating: 0, count: Keyboard.streamSlots)
    private var lastHeatUpdate = Date()
    private var previous: [Double] = []

    /// A key was pressed (typing effects only).
    func keyPressed(led: Int, at now: Date = Date()) {
        guard let key = F99.keys.first(where: { $0.led == led }) else { return }
        presses.append((led, key.x, key.y, now))
        if presses.count > 24 { presses.removeFirst() }
        // Heat spreads a little to the neighbouring keys.
        for k in F99.keys {
            let d = Self.distance(k, key.x, key.y)
            if d < 0.09 { heat[k.led] = min(1, heat[k.led] + (d < 0.001 ? 0.22 : 0.08 * (1 - d / 0.09))) }
        }
    }

    func render(now: Date = Date()) -> [UInt8] {
        let speedFactor = 0.5 + Double(speed) * 0.35
        let t = now.timeIntervalSince(start) * speedFactor
        if effect == .typingHeatmap {
            // Heat fades over about 6 seconds.
            let dt = now.timeIntervalSince(lastHeatUpdate)
            lastHeatUpdate = now
            let keep = exp(-dt / 6)
            for i in heat.indices { heat[i] *= keep }
        }
        let keepPresses = max(2, pressFade * 5)
        presses.removeAll { now.timeIntervalSince($0.at) > keepPresses }

        var values = [Double](repeating: 0, count: Keyboard.streamSlots * 3)
        let light = pressColor
            ?? palette.colors.max { $0.luminance < $1.luminance }.map { $0.mixed(with: RGB(1, 1, 1), 0.5) } ?? RGB(1, 1, 1)
        for key in F99.keys where key.led < Keyboard.streamSlots {
            // Painted keys keep their colour over any effect.
            var (c, v) = paint[key.led].map { ($0, 1.0) } ?? color(key, t, now)
            if minimumBrightness > 0 { c = c.atLeast(peak: 0.7) }
            if pressGlow && !presses.isEmpty { (c, v) = pressed(key, c, v, light, now) }
            v = minimumBrightness + (1 - minimumBrightness) * min(max(v, 0), 1)
            let level = v * MusicRenderer.maxBrightness * brightnessScale
            values[key.led * 3] = c.r * level
            values[key.led * 3 + 1] = c.g * level
            values[key.led * 3 + 2] = c.b * level
        }
        limitSwing(&values)
        return values.map { UInt8(min(max($0, 0), 1) * 255) }
    }

    private func color(_ key: F99.Key, _ t: Double, _ now: Date) -> (RGB, Double) {
        let x = key.x, y = key.y
        let dx = (x - 0.5) * 3, dy = y - 0.5
        let dist = sqrt(dx * dx + dy * dy)
        let angle = atan2(dy, dx) / (2 * .pi) + 0.5

        switch effect {
        case .cascade:
            // The Neon and Electric colours flowing diagonally across the
            // board; every key always bright, with a gentle shimmer.
            let position = x * 0.55 + (1 - y) * 0.18 - t * 0.09
            let shimmer = 0.5 + 0.5 * sin(x * 7 - y * 2 - t * 1.6)
            return (palette.sample(position, wrap: true), 0.8 + 0.2 * shimmer)

        case .matrix:
            // Columns of falling code: a bright head with a fading tail.
            let column = Int(x * 22)
            let rate = 0.35 + 0.4 * Self.hash(column, 1)
            let cycle = t * rate + Self.hash(column, 2)
            let head = (cycle - floor(cycle)) * 1.8 - 0.4
            let behind = head - y
            guard behind >= 0 else { return (palette.sample(0, wrap: false), 0.02) }
            let v = exp(-behind * 5)
            let c = behind < 0.08 ? palette.sample(1, wrap: false) : palette.sample(0.5, wrap: false)
            return (c, v)

        case .fire:
            // Hot at the bottom, flickering flames rising.
            let rise = y * 1.15 - 0.2
            let flicker = Self.noise(x * 7, t * 2.2 - y * 3) * 0.6 + Self.noise(x * 15, t * 4) * 0.25
            // Glowing embers keep even the top rows warm.
            let heat = min(max(rise + flicker - 0.35, 0.22 + 0.12 * Self.noise(x * 11, t * 1.3)), 1)
            return (palette.sample(heat, wrap: false), 0.05 + 0.95 * pow(heat, 0.8))

        case .aurora:
            // Slow curtains of colour drifting sideways.
            let curtain = 0.5 + 0.5 * sin(x * 4 + sin(t * 0.5 + y * 2.5) * 1.6 + t * 0.35)
            let hue = 0.5 + 0.5 * sin(x * 1.7 - t * 0.15 + y * 0.8)
            return (palette.sample(hue, wrap: true), 0.15 + 0.85 * pow(curtain, 1.4))

        case .starlight:
            // Random keys softly fade in and out in random palette colours.
            let tw = Self.twinkle(key.led, t, rate: 0.45)
            return (palette.sample(Self.hash(key.led, Int(t * 0.45)), wrap: true), 0.03 + 0.97 * tw)

        case .comet:
            // A bright head racing along each row with a long tail.
            let row = Int((y * 5).rounded())
            let p = (t * 0.32 + Double(row) * 0.17).truncatingRemainder(dividingBy: 1) * 1.4 - 0.2
            let behind = p - x
            guard behind >= 0 else { return (palette.sample(0, wrap: true), 0.02) }
            return (palette.sample(Double(row) / 5, wrap: true), exp(-behind * 7))

        case .visor:
            // A band sweeping back and forth with a trailing glow.
            let pos = 0.5 + 0.55 * sin(t * 1.3)
            let moving = cos(t * 1.3) // direction of travel
            let d = x - pos
            let trail = d * (moving > 0 ? -1 : 1) // positive behind the band
            let v = abs(d) < 0.03 ? 1 : (trail > 0 ? exp(-trail * 9) : exp(-abs(d) * 40))
            return (palette.sample(moving > 0 ? 0.2 : 0.8, wrap: false), v)

        case .lavaLamp:
            // Slow blobs merging and splitting.
            var field = 0.0
            for i in 0..<4 {
                let bx = 0.5 + 0.42 * sin(t * (0.18 + 0.05 * Double(i)) + Double(i) * 1.7)
                let by = 0.5 + 0.45 * sin(t * (0.23 + 0.04 * Double(i)) + Double(i) * 2.9)
                let d2 = pow((x - bx) * 3, 2) + pow(y - by, 2)
                field += 0.05 / max(d2, 0.002)
            }
            let f = min(field / 1.2, 1)
            return (palette.sample(f, wrap: false), 0.08 + 0.92 * pow(f, 1.5))

        case .plasma:
            // Classic demoscene plasma.
            let v = sin(x * 9 + t) + sin(y * 7 + t * 1.3) + sin((x + y) * 6 + t * 0.7) + sin(dist * 5 - t)
            return (palette.sample(v / 8 + 0.5 + t * 0.03, wrap: true), 0.85)

        case .heartbeat:
            // Lub-dub (two soft pulses per beat), spreading out from the centre.
            // 60-90 beats a minute by speed: at most three pulses a second.
            let bpm = 60 + Double(speed) * 7.5
            let real = now.timeIntervalSince(start)
            let phase = (real * bpm / 60).truncatingRemainder(dividingBy: 1)
            let delay = dist * 0.08
            let p = phase - delay
            // Soft, fairly wide pulses over a steady red glow, so the
            // anti-strobe limit never has to flatten them.
            let beat = min(exp(-pow(p, 2) / 0.012) + 0.6 * exp(-pow(p - 0.22, 2) / 0.012), 1)
            return (palette.sample(0.35 + 0.65 * beat, wrap: false), 0.25 + 0.75 * beat)

        case .galaxy:
            // A slowly turning spiral of dusky colour with twinkling stars.
            let swirl = 0.5 + 0.5 * sin(angle * 2 * .pi * 2 + dist * 6 - t * 0.6)
            let star = Self.twinkle(key.led, t, rate: 0.6)
            let c = star > 0.5 ? RGB(1, 1, 1) : palette.sample(0.15 + swirl * 0.5, wrap: false)
            return (c, max(0.12 + 0.35 * swirl, star))

        case .spiral:
            return (palette.sample(angle + dist * 0.35 - t * 0.12, wrap: true), 0.85)

        case .candle:
            // Warm, gently flickering light, like a room lit by candles.
            let room = Self.noise(t * 1.8, 0) * 0.3
            let local = Self.noise(Double(key.led) * 0.37, t * 3.1) * 0.25
            let v = 0.35 + room + local
            return (palette.sample(0.45 + local, wrap: false), v)

        case .typingRipples:
            // Every key keeps a soft glow in the theme; rings spread from
            // each key you press. Below about half, the LEDs lose red and
            // green and every colour turns a dim blue.
            var v = 0.5
            // Each key its own colour, so neighbours differ, drifting slowly.
            let c = palette.sample(Self.hash(key.led, 3) + t * 0.02, wrap: true)
            for p in presses {
                let age = now.timeIntervalSince(p.at)
                let d = Self.distance(key, p.x, p.y)
                let ring = exp(-pow(d - age * 0.9, 2) / 0.0025) * max(0, 1 - age / 1.6)
                let tap = d < 0.001 ? max(0, 1 - age / 0.4) : 0
                // The ring brightens each key in its own colour, like the
                // keyboard's own Ripples, rather than painting one colour.
                v = max(v, ring, tap)
            }
            return (c, v)

        case .typingHeatmap:
            let h = heat[key.led]
            return (palette.sample(h, wrap: false), 0.05 + 0.95 * min(h * 1.3, 1))

        case .ripples:
            // Soft rings spreading out from the centre, the colour drifting
            // through the theme as they go.
            let ring = pow(0.5 + 0.5 * sin(dist * 7 - t * 2.6), 3)
            return (palette.sample(dist * 0.35 - t * 0.06, wrap: true), 0.2 + 0.8 * ring)

        case .painted:
            if let c = paint[key.led] { return (c, 1) }
            if let base = paintBase { return (base, 1) }
            return (RGB(0, 0, 0), 0)
        }
    }

    /// A pressed key flashes bright in the lightest colour and fades over
    /// about half a second; a soft halo spreads around it and fades too.
    private func pressed(_ key: F99.Key, _ c: RGB, _ v: Double, _ light: RGB, _ now: Date) -> (RGB, Double) {
        var color = c, value = v
        // The key itself goes nearly white, tinted with the light colour.
        let flash = light.mixed(with: RGB(1, 1, 1), 0.55)
        for p in presses {
            let age = now.timeIntervalSince(p.at)
            let d = Self.distance(key, p.x, p.y)
            if d < 0.001 {
                let g = exp(-age / pressFade)
                color = color.mixed(with: flash, g)
                value = max(value, g)
            } else if haloSize > 0 {
                let g = exp(-pow(d / ((0.05 + age * 0.12) * haloSize), 2)) * exp(-age / (pressFade * 1.33)) * 0.75
                if g > 0.02 {
                    color = color.mixed(with: light, g)
                    value = max(value, g)
                }
            }
        }
        return (color, value)
    }

    /// Same rule as music mode: the whole board can't jump too far in
    /// brightness from one frame to the next.
    private func limitSwing(_ values: inout [Double]) {
        defer { previous = values }
        guard previous.count == values.count else { return }
        let mean = values.reduce(0, +) / Double(values.count)
        let before = previous.reduce(0, +) / Double(values.count)
        let maxStep = 0.12
        guard abs(mean - before) > maxStep else { return }
        let keep = maxStep / abs(mean - before)
        for i in values.indices { values[i] = previous[i] + (values[i] - previous[i]) * keep }
    }

    static func distance(_ k: F99.Key, _ x: Double, _ y: Double) -> Double {
        sqrt(pow(k.x - x, 2) + pow((k.y - y) * 0.33, 2))
    }

    /// 0...1, the same for the same inputs.
    static func hash(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(bitPattern: Int64(a &* 73856093 ^ b &* 19349663 ^ 0x5bd1e995))
        h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }

    /// Smooth random value 0...1 (value noise).
    static func noise(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func h(_ i: Int, _ j: Int) -> Double { hash(i &* 31 &+ 7, j &* 17 &+ 3) }
        let top = h(xi, yi) + (h(xi + 1, yi) - h(xi, yi)) * sx
        let bottom = h(xi, yi + 1) + (h(xi + 1, yi + 1) - h(xi, yi + 1)) * sx
        return top + (bottom - top) * sy
    }

    /// A key that now and then fades in and back out: 0...1.
    static func twinkle(_ led: Int, _ t: Double, rate: Double) -> Double {
        let cycle = t * rate + hash(led, 0)
        let n = Int(floor(cycle))
        guard hash(led, n) < 0.3 else { return 0 }
        let f = cycle - floor(cycle)
        return pow(sin(f * .pi), 2)
    }
}

/// Drawn on top of whatever is streaming: a song's progress up the column of
/// keys beside the light strip, and alert flashes.
struct Overlays {
    /// 0...1, or nil for no bar.
    var progress: Double?
    var progressColor = RGB(1, 1, 1)
    var flash: Flash?

    struct Flash {
        var start: Date
        var color: RGB
        var count: Int
        static let period = 0.6 // seconds per flash: under two a second
        func intensity(at now: Date) -> Double? {
            let e = now.timeIntervalSince(start)
            guard e >= 0, e < Double(count) * Self.period else { return nil }
            let phase = e.truncatingRemainder(dividingBy: Self.period) / Self.period
            return pow(sin(.pi * phase), 2)
        }
    }

    /// The keys beside the light strip, bottom to top.
    static let column: [Int] = ["Right", "Num1", "Num4", "Num7", "NumLock", "Home"].compactMap { name in
        F99.keys.first { $0.name == name }?.led
    }

    var isEmpty: Bool { progress == nil && flash == nil }

    mutating func apply(_ frame: [UInt8], now: Date = Date()) -> [UInt8] {
        guard !isEmpty else { return frame }
        var out = frame
        func set(_ led: Int, _ c: RGB, _ v: Double) {
            guard led * 3 + 2 < out.count else { return }
            let level = v * MusicRenderer.maxBrightness
            out[led * 3] = UInt8(min(max(c.r * level, 0), 1) * 255)
            out[led * 3 + 1] = UInt8(min(max(c.g * level, 0), 1) * 255)
            out[led * 3 + 2] = UInt8(min(max(c.b * level, 0), 1) * 255)
        }
        if let p = progress {
            let filled = min(max(p, 0), 1) * Double(Self.column.count)
            for (i, led) in Self.column.enumerated() {
                let f = min(max(filled - Double(i), 0), 1)
                // Unfilled keys stay faintly lit, so the bar reads as a track.
                set(led, progressColor, 0.08 + 0.92 * f)
            }
        }
        if let f = flash {
            if let k = f.intensity(at: now) {
                let level = k * MusicRenderer.maxBrightness
                for i in stride(from: 0, to: out.count - 2, by: 3) {
                    let target = [f.color.r, f.color.g, f.color.b]
                    for j in 0..<3 {
                        let a = Double(out[i + j]) / 255
                        out[i + j] = UInt8(min(max(a + (target[j] * level - a) * k, 0), 1) * 255)
                    }
                }
            } else if now.timeIntervalSince(f.start) >= 0 {
                flash = nil
            }
        }
        return out
    }
}

/// macOS key codes to F99 key names, for the typing effects.
enum KeyMap {
    static let names: [UInt16: String] = {
        var m: [UInt16: String] = [:]
        for (name, code) in Keys.all { m[UInt16(code)] = name }
        let extra: [UInt16: String] = [
            53: "Esc", 50: "`", 27: "-", 24: "=", 51: "Backspace", 48: "Tab", 33: "[", 30: "]", 42: "\\",
            41: ";", 39: "'", 36: "Enter", 43: ",", 47: ".", 44: "/", 49: "Space",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
            117: "Delete", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            71: "NumLock", 75: "Num /", 67: "Num*", 78: "Num-", 69: "Num+", 65: "Num .",
            82: "Num0", 83: "Num1", 84: "Num2", 85: "Num3", 86: "Num4", 87: "Num5", 88: "Num6",
            89: "Num7", 91: "Num8", 92: "Num9",
            // Modifiers, as the F99 sends them in Windows mode (Win is ⌘,
            // Alt is ⌥). Right ⌘ only exists with the keys swapped, where
            // it's the right Alt key.
            56: "LShift", 60: "RShift", 59: "LCtrl", 62: "RCtrl", 58: "LAlt", 61: "RAlt",
            55: "LWin", 54: "RAlt", 57: "CapsLock",
        ]
        m.merge(extra) { _, new in new }
        return m
    }()

    /// A modifier key's change is a press when its flag is now held. Caps
    /// Lock toggles, so every change counts.
    static func isPress(_ event: NSEvent) -> Bool {
        let flag: NSEvent.ModifierFlags? = switch event.keyCode {
        case 56, 60: .shift
        case 59, 62: .control
        case 58, 61: .option
        case 54, 55: .command
        default: nil
        }
        guard let flag else { return true }
        return event.modifierFlags.contains(flag)
    }

    static func led(forKeyCode code: UInt16) -> Int? {
        if code == 76 { return F99.keys.last { $0.name == "Enter" }?.led } // keypad Enter
        guard let name = names[code] else { return nil }
        return F99.keys.first { $0.name == name }?.led
    }
}
