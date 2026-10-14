import SwiftUI

// The look of the app: mood tiles in the style of Philips Hue and Apple Home
// scenes (each mood shown as its own colours), keycap badges for shortcuts
// like Raycast, and cards for groups of controls.

extension Mood {
    /// The tile's icon: the one picked in the editor, else one for the effect.
    var symbolName: String {
        if let symbol, !symbol.isEmpty { return symbol }
        if lighting.brightness == 0 { return "moon.fill" }
        if let s = Self.builtInSymbols[name] { return s }
        if let live { return live.symbolName }
        return switch lighting.effect {
        case 1: "lightbulb.fill"
        case 2: "wind"
        case 3: "rainbow"
        case 4: "bolt.fill"
        case 5: "cloud.rain.fill"
        case 6: "camera.aperture"
        case 7: "dot.radiowaves.left.and.right"
        case 8: "sparkles"
        case 9: "circle.lefthalf.filled"
        case 10: "gamecontroller.fill"
        case 11: "water.waves"
        case 12: "hand.tap.fill"
        case 13: "waveform.path"
        case 14: "scope"
        case 15: "fanblades.fill"
        case 16: "drop.fill"
        case 17: "camera.macro"
        case 18: "tornado"
        default: "lightbulb.fill"
        }
    }

    private static let builtInSymbols: [String: String] = [
        "Focus": "target", "Gaming": "gamecontroller.fill", "Typing Glow": "keyboard.fill",
        "WASD": "gamecontroller.fill", "Neon Night": "moon.stars.fill",
    ]

    /// Icons offered in the mood editor.
    static let symbolChoices = [
        "lightbulb.fill", "target", "sparkles", "moon.fill", "moon.stars.fill", "sun.max.fill",
        "flame.fill", "drop.fill", "leaf.fill", "snowflake", "wind", "tornado",
        "rainbow", "bolt.fill", "heart.fill", "star.fill", "atom", "water.waves",
        "gamecontroller.fill", "keyboard.fill", "headphones", "music.note", "film.fill", "book.fill",
        "briefcase.fill", "cup.and.saucer.fill", "bed.double.fill", "paintbrush.pointed.fill", "scope", "hand.tap.fill",
    ]

    /// The colours to show for this mood.
    /// Lights only where you type (Gaming), or shows its effect as you type.
    var lightsWhenTyping: Bool { live?.drawsPresses ?? (lighting.effect == 12) }

    func swatch(custom: [RGB]) -> [Color] {
        if lighting.brightness == 0 { return [Color(white: 0.28), Color(white: 0.1)] }
        if live == .painted {
            var seen: [RGB] = []
            for c in paint.values.sorted(by: { $0.hue < $1.hue }) where !seen.contains(c) { seen.append(c) }
            let colours = Array(seen.prefix(4)) + [paintBase].compactMap { $0 }
            return colours.isEmpty ? [Color(white: 0.4), Color(white: 0.2)] : (colours.count == 1 ? colours + colours : colours).map(\.color)
        }
        let fixed = (0..<F99.colorful).contains(lighting.color)
        if let live {
            if let name = paletteName {
                if name == MusicPalette.customName { return custom.map(\.color) }
                if let p = MusicPalette.presets.first(where: { $0.name == name }) { return p.colors.map(\.color) }
            }
            return (fixed ? MusicPalette.forMood(self).colors : live.palette.colors).map(\.color)
        }
        if F99.effect(lighting.effect)?.hasColor != false, fixed {
            return MusicPalette.forMood(self).colors.map(\.color)
        }
        // Some effects show their "colourful" setting as soft pastels.
        if F99.pastelEffects.contains(lighting.effect) {
            return [0xff0000, 0xff8000, 0xffff00, 0x00ff00, 0x00ffff, 0x0000ff, 0x8000ff]
                .map { RGB(hex: $0).mixed(with: RGB(1, 1, 1), 0.45).color }
        }
        return [Color.red, .orange, .yellow, .green, .cyan, .blue, .purple]
    }
}

extension LiveEffect {
    var symbolName: String {
        switch self {
        case .cascade: "wand.and.stars"
        case .matrix: "chevron.left.forwardslash.chevron.right"
        case .fire: "flame.fill"
        case .aurora: "rays"
        case .starlight: "star.fill"
        case .comet: "sparkle"
        case .visor: "light.beacon.max.fill"
        case .lavaLamp: "lamp.table.fill"
        case .plasma: "atom"
        case .heartbeat: "heart.fill"
        case .galaxy: "moon.stars.fill"
        case .spiral: "hurricane"
        case .candle: "flame"
        case .typingRipples: "drop.circle.fill"
        case .typingHeatmap: "thermometer.medium"
        case .painted: "paintbrush.pointed.fill"
        case .ripples: "circle.dotted.circle"
        }
    }
}

extension RGB {
    /// 0...1 round the colour wheel, for sorting.
    var hue: Double {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0.0001 else { return 0 }
        var h: Double
        if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        return h < 0 ? h + 1 : h
    }
}

/// A mood's colours as a rounded gradient, with its icon.
struct MoodSwatch: View {
    let colors: [Color]
    var symbol: String? = nil
    var corner: CGFloat = 8

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.black.opacity(0.08)))
    }
}

/// A shortcut drawn as little keycaps: ⌃ ⌥ 1.
struct KeycapBadge: View {
    let hotkey: Hotkey
    var onColor = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .frame(minWidth: 13, minHeight: 14)
                    .padding(.horizontal, 2)
                    .background(RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(onColor ? Color.black.opacity(0.28) : Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(onColor ? Color.white.opacity(0.25) : Color.primary.opacity(0.12), lineWidth: 0.5))
            }
        }
        .foregroundStyle(onColor ? Color.white : Color.secondary)
        .accessibilityLabel("Shortcut \(hotkey.display)")
    }

    private var parts: [String] {
        var p: [String] = []
        if hotkey.modifiers & Hotkey.control != 0 { p.append("⌃") }
        if hotkey.modifiers & Hotkey.option != 0 { p.append("⌥") }
        if hotkey.modifiers & Hotkey.shift != 0 { p.append("⇧") }
        if hotkey.modifiers & Hotkey.command != 0 { p.append("⌘") }
        p.append(Keys.name(for: hotkey.keyCode) ?? "?")
        return p
    }
}

/// A rounded panel for a group of controls, like the cards in System Settings.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// A small grey heading over a group, with an optional note beside it.
struct GroupHeader: View {
    let title: String
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 0)
        }
    }
}

/// A rounded "pill" showing whether the keyboard is connected.
struct StatusPill: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.callout.weight(.medium)).lineLimit(1)
            if model.busy { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .help(detail ?? "")
    }

    private var title: String {
        switch model.status {
        case .searching: "Looking for your F99…"
        case .connected(let name): "\(name) · connected"
        case .readOnly: "Unrecognised keyboard"
        case .unavailable: "Not connected"
        }
    }

    private var detail: String? {
        switch model.status {
        case .readOnly(let why), .unavailable(let why): why
        default: nil
        }
    }

    private var color: Color {
        switch model.status {
        case .connected: .green
        case .searching: .yellow
        case .readOnly, .unavailable: .orange
        }
    }
}

/// The app's colours, taken from the white F99 with periwinkle and lavender
/// keys: a white window (or a deep violet-grey one in dark mode), lavender for
/// buttons and selections. The keyboard picture stays white in both, like
/// the real board.
enum Theme {
    /// A colour for light mode and one for dark mode.
    static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Text on the mood tiles: dark on the light theme's pastel tiles,
    /// near-white on the dark theme's deep ones.
    static let ink = adaptive((0.16, 0.14, 0.26), (0.96, 0.95, 1.0))
    /// The side panel and chips.
    static let panel = adaptive((1, 1, 1), (0.15, 0.14, 0.19))
    /// Picked keys in the 3D view glow this colour.
    static let pickedNS = NSColor(red: 0.55, green: 0.47, blue: 0.90, alpha: 1)
    static let lavender = Color(red: 0.55, green: 0.47, blue: 0.90)
    static let periwinkle = Color(red: 0.62, green: 0.74, blue: 0.93)
    /// Behind the cards: white with a hint of lavender, or deep violet-grey.
    static let page = adaptive((0.965, 0.96, 0.985), (0.10, 0.095, 0.13))

    /// Keycap colours as RGB, so the picture can blend light into them.
    static let whiteCap = RGB(0.975, 0.975, 0.99)
    static let blueCap = RGB(0.66, 0.77, 0.94)
    static let purpleCap = RGB(0.58, 0.50, 0.90)

    /// Each key's cap, as on the white, periwinkle and lavender F99.
    static func cap(for name: String) -> RGB {
        switch name {
        case "Esc", "Enter", "Space", "Up", "Down", "Left", "Right": return purpleCap
        case "F5", "F6", "F7", "F8", "Delete", "Home", "End", "PgUp", "PgDn",
             "Backspace", "NumLock", "Num /", "Num*", "Num-", "Num+",
             "Tab", "CapsLock", "LShift", "RShift",
             "LCtrl", "LWin", "LAlt", "RAlt", "FN", "RCtrl": return blueCap
        default: return whiteCap
        }
    }
}

extension RGB {
    /// A straight blend towards `o`; cheap enough for every key, every frame.
    func lerp(_ o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
}

extension Color {
    /// Mixed towards white by `amount` (0 keeps it, 1 is white).
    func softened(_ amount: Double) -> Color { mixed(towards: (1, 1, 1), amount) }

    /// Mixed towards the dark theme's background, for tiles in dark mode.
    func deepened(_ amount: Double) -> Color { mixed(towards: (0.10, 0.095, 0.13), amount) }

    private func mixed(towards t: (Double, Double, Double), _ amount: Double) -> Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        func mix(_ v: CGFloat, _ to: Double) -> Double { Double(v) + (to - Double(v)) * amount }
        return Color(red: mix(c.redComponent, t.0), green: mix(c.greenComponent, t.1), blue: mix(c.blueComponent, t.2))
    }
}
