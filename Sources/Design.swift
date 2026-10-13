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
