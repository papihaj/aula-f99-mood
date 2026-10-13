import SwiftUI

/// The main window: a live picture of the F99, moods, and music controls.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                StatusLine()
                Spacer()
                Button {
                    openWindow(id: "editor")
                } label: {
                    Label("Edit moods & macros", systemImage: "slider.horizontal.3")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                KeyboardPicture()
                    .aspectRatio(F99.boardSize.w / F99.boardSize.h * 0.97, contentMode: .fit)
                    .padding(14)
                    .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.1)))
                Text(caption).font(.callout).foregroundStyle(.secondary)
            }

            if model.needsAccessibility { AccessibilityBanner(compact: false) }
            if model.darkened || model.idleDimmed {
                Label(model.darkened ? "Lights off while the screen is locked." : "Dimmed while you're away; touch a key to bring them back.",
                      systemImage: "moon.zzz").font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    moodSection("Keyboard effects", "Built into the keyboard; they keep running after you quit.",
                                model.settings.moods.filter { $0.live == nil && !$0.hidden })
                    moodSection("Live effects", "Drawn by your Mac in the style of Razer, Corsair, ASUS and QMK; they run while F99 Mood is open.",
                                model.settings.moods.filter { $0.live != nil && !$0.hidden })
                }
            }
            .frame(minHeight: 140)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Music").font(.headline)
                    if model.musicOn { MusicMeterView(meter: model.meter) }
                }
                if model.musicOn && model.hearingNothing {
                    NotHearingBanner()
                }

                MusicControls()
                HStack(spacing: 18) {
                    Toggle("Reduced flashing", isOn: Binding(get: { model.settings.reducedFlashing },
                                                             set: { model.setReducedFlashing($0) }))
                    Toggle("Light strip matches colours", isOn: Binding(get: { model.settings.stripFollowsColors },
                                                                         set: { model.setStripFollowsColors($0) }))
                    Toggle("Keep every key lit", isOn: Binding(get: { model.settings.keepKeysLit },
                                                               set: { model.setKeepKeysLit($0) }))
                        .help("In live effects and music, no key drops below a set brightness, so you can always read the letters.")
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }
        }
        .padding(22)
        .frame(minWidth: 640, minHeight: 580)
        .sheet(isPresented: Binding(get: { !model.settings.welcomeDone },
                                    set: { if !$0 { model.settings.welcomeDone = true } })) {
            WelcomeView().environmentObject(model)
        }
    }

    @ViewBuilder
    private func moodSection(_ title: String, _ note: String, _ moods: [Mood]) -> some View {
        if !moods.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(moods) { MoodButton(mood: $0) }
                }
            }
        }
    }

    private var caption: String {
        let where_ = model.canWrite ? "on your keyboard" : "preview — plug in the F99 by USB-C to light it up"
        if model.musicOn {
            let colours = model.musicMood.map { "\($0.emoji) \($0.name) colours" } ?? model.settings.musicPalette.name
            return "Dancing to music: \(model.settings.musicStyle.rawValue), \(colours) (\(where_))"
        }
        if let mood = model.liveMood, let live = mood.live {
            return "\(mood.emoji) \(mood.name): live \(live.rawValue) (\(where_))"
        }
        if let l = model.shownLighting, let effect = F99.effect(l.effect) {
            let mood = model.activeMood.map { "\($0.emoji) \($0.name): " } ?? ""
            return "\(mood)\(effect.name), brightness \(l.brightness)/4 (\(where_))"
        }
        return "Pick a mood or start the music"
    }
}

/// Draws the F99 from its real key positions and colours each key.
///
/// With music on it shows the exact colours being sent to the keyboard. For
/// moods it imitates the keyboard's built-in effect. That part is only an
/// approximation, because the keyboard draws those effects itself.
struct KeyboardPicture: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { gc, size in
                let scale = min(size.width / F99.boardSize.w, size.height / F99.boardSize.h)
                let t = context.date.timeIntervalSinceReferenceDate

                // The light strip, in the gap right of Backspace and left of
                // Num Lock, above the Up arrow.
                if let back = F99.keys.first(where: { $0.name == "Backspace" }),
                   let numLock = F99.keys.first(where: { $0.name == "NumLock" }),
                   let up = F99.keys.first(where: { $0.name == "Up" }) {
                    let left = back.frame.x + back.frame.w, right = numLock.frame.x
                    let width = max(4, (right - left) * 0.35)
                    let x = (left + right) / 2 - width / 2
                    let top = 4.0 // level with the top row of keys
                    let bottom = up.frame.y - 4
                    // Its saved colour (the keyboard animates its own style).
                    let rect = CGRect(x: x * scale, y: top * scale, width: width * scale, height: (bottom - top) * scale)
                    let shape = Capsule().path(in: rect)
                    gc.fill(shape, with: .color(Color(white: 0.85)))
                    if let c = stripColor {
                        gc.fill(shape, with: .color(Color(red: c.rgb.0, green: c.rgb.1, blue: c.rgb.2).opacity(0.85)))
                    }
                    gc.stroke(shape, with: .color(.black.opacity(0.2)), lineWidth: 0.8)
                }
                for key in F99.keys {
                    let f = key.frame
                    let rect = CGRect(x: f.x * scale, y: f.y * scale, width: f.w * scale, height: f.h * scale)
                        .insetBy(dx: 1.2, dy: 1.2)
                    let glow = color(for: key, time: t)
                    let shape = RoundedRectangle(cornerRadius: 4 * scale).path(in: rect)

                    // Keycap, then the light shining through it.
                    gc.fill(shape, with: .color(Color(white: 0.98)))
                    gc.fill(shape, with: .color(glow.opacity(0.85)))
                    gc.stroke(shape, with: .color(.black.opacity(0.18)), lineWidth: 0.8)

                    let label = Self.label(key.name)
                    if !label.isEmpty {
                        let font = Font.system(size: max(6, min(11, rect.height * 0.32)), weight: .medium)
                        gc.draw(Text(label).font(font).foregroundColor(.black.opacity(0.75)),
                                at: CGPoint(x: rect.minX + 3 * scale, y: rect.minY + 3 * scale),
                                anchor: .topLeading)
                    }
                }
            }
        }
    }

    /// The strip's colour as the app expects it: what the keyboard reports,
    /// or, without a keyboard, what the current theme or mood would set.
    private var stripColor: F99.FirmwareColor? {
        var id: Int?
        if model.settings.stripFollowsColors {
            if model.musicOn {
                id = model.musicMood.map { $0.lighting.color } ?? model.settings.musicPalette.stripColor
            } else if let mood = model.activeMood, mood.lighting.color < F99.colorful {
                id = mood.lighting.color
            }
        }
        if model.canWrite, let page = model.page, id == nil || model.page?.stripColor == id {
            id = page.stripColor
        }
        return F99.colors.first { $0.id == id }
    }

    private func color(for key: F99.Key, time: Double) -> Color {
        if let frame = model.streamFrame, key.led * 3 + 2 < frame.count {
            return Color(red: Double(frame[key.led * 3]) / 255,
                         green: Double(frame[key.led * 3 + 1]) / 255,
                         blue: Double(frame[key.led * 3 + 2]) / 255)
        }
        guard let l = model.shownLighting else { return .clear }
        return LightingSimulator.color(for: key, lighting: l, time: time)
    }

    static func label(_ name: String) -> String {
        switch name {
        case "Backspace": return "⌫"
        case "Delete": return "Del"
        case "NumLock": return "Num"
        case "Tab": return "⇥"
        case "CapsLock": return "Caps"
        case "Enter": return "⏎"
        case "LShift", "RShift": return "⇧"
        case "LCtrl", "RCtrl": return "Ctrl"
        case "LWin": return "Win"
        case "LAlt", "RAlt": return "Alt"
        case "FN": return "Fn"
        case "Space": return ""
        case "Up": return "↑"
        case "Down": return "↓"
        case "Left": return "←"
        case "Right": return "→"
        case "PgUp": return "PgUp"
        case "PgDn": return "PgDn"
        default:
            if name.hasPrefix("Num ") { return String(name.dropFirst(4)) }
            if name.hasPrefix("Num") { return String(name.dropFirst(3)) }
            return name
        }
    }
}

/// An imitation of the keyboard's built-in effects, for the preview. The
/// keyboard draws the real ones itself, so these are approximations of what
/// each looks like, based on the effect names.
enum LightingSimulator {
    static func color(for key: F99.Key, lighting l: ConfigPage.Lighting, time t: Double) -> Color {
        guard let effect = F99.effect(l.effect) else { return .clear }
        let brightness = Double(min(max(l.brightness, 0), 4)) / 4
        guard brightness > 0 else { return .clear }
        let speed = 0.4 + Double(l.speed) * 0.4
        let ts = t * speed
        let x = key.x, y = key.y
        // Centre-relative position, with the board's 3:1 shape evened out.
        let dx = (x - 0.5) * 3, dy = y - 0.5
        let dist = sqrt(dx * dx + dy * dy)
        let angle = atan2(dy, dx) / (2 * .pi) + 0.5

        // The chosen colour, or a rainbow for "colourful" and for effects
        // that pick their own colours.
        let rainbow = !effect.hasColor || l.color == F99.colorful
        func fixed(_ hue: Double) -> (Double, Double, Double) {
            if !rainbow, let c = F99.colors.first(where: { $0.id == l.color }) { return c.rgb }
            let h = hue - floor(hue)
            return rgb(hue: h)
        }

        var hue = x * 0.8 + ts * 0.08
        var v = 1.0
        switch effect.id {
        case 1: // Fixed on
            break
        case 2: // Breathing
            v = 0.12 + 0.88 * pow(0.5 + 0.5 * sin(ts * 2), 1.5)
        case 3: // Rainbow: hues sweep across
            hue = x - ts * 0.15
        case 4: // Flash away: the board flashes, then fades
            let p = (ts * 0.6).truncatingRemainder(dividingBy: 1)
            v = pow(1 - p, 3)
            hue = floor(ts * 0.6) * 0.17
        case 5: // Raindrops: random keys light and fade
            v = 0.08 + 0.92 * drop(key.led, ts, rate: 0.9)
            hue = Double(hash(key.led, Int(ts * 0.9))) / 97
        case 6: // Rainbow wheel: hues turn around the centre
            hue = angle - ts * 0.15
        case 7: // Ripples shining: rings from the centre
            v = 0.12 + 0.88 * pow(0.5 + 0.5 * sin(dist * 9 - ts * 4), 4)
            hue = dist * 0.4 - ts * 0.1
        case 8: // Stars twinkle: soft, sparse twinkles
            v = 0.05 + 0.95 * drop(key.led, ts, rate: 0.5) * 0.9
            hue = Double(hash(key.led, Int(ts * 0.5))) / 97
        case 9: // Shadow disappear: lit board with dark patches drifting away
            v = 0.25 + 0.75 * (1 - drop(key.led, ts, rate: 0.7))
        case 10: // Retro snake: a lit snake running along the rows
            let row = (y * 5).rounded()
            let along = row.truncatingRemainder(dividingBy: 2) == 0 ? x : 1 - x
            let pos = (row + along) / 6
            let head = (ts * 0.25).truncatingRemainder(dividingBy: 1)
            var gap = head - pos
            if gap < 0 { gap += 1 }
            v = gap < 0.12 ? 1 - gap / 0.12 : 0.04
        case 11: // Neon stream: bands of colour flowing sideways
            hue = x * 1.5 - ts * 0.3
            v = 0.5 + 0.5 * sin((x - ts * 0.3) * 12)
        case 12: // Reaction: lights where you type; shown as a soft glow
            v = 0.15 + 0.85 * drop(key.led, ts, rate: 2.5) * 0.7
        case 13: // Sine wave: a wave rolling across
            let wave = 0.5 + 0.4 * sin(x * 9 - ts * 3)
            v = 0.1 + 0.9 * max(0, 1 - abs((1 - y) - wave) * 3)
        case 14: // Retinue scanning: a bar sweeping back and forth
            let bar = 0.5 + 0.5 * sin(ts * 1.5)
            v = 0.05 + 0.95 * max(0, 1 - abs(x - bar) * 7)
        case 15: // Rotating windmill: blades turning around the centre
            v = 0.1 + 0.9 * pow(0.5 + 0.5 * sin((angle - ts * 0.25) * 2 * .pi * 4), 3)
            hue = angle - ts * 0.1
        case 16: // Colorful waterfall: colour pouring down
            hue = y * 0.8 - ts * 0.25 + x * 0.1
        case 17: // Blossoming: colour opening out from the centre
            hue = dist * 0.5 - ts * 0.2
            v = 0.3 + 0.7 * (0.5 + 0.5 * sin(dist * 6 - ts * 2.5))
        case 18: // Rotating storm: a spiral turning
            hue = angle + dist * 0.6 - ts * 0.2
            v = 0.2 + 0.8 * pow(0.5 + 0.5 * sin((angle * 2 * .pi) + dist * 8 - ts * 3), 2)
        default:
            break
        }

        let (r, g, b) = fixed(hue)
        let level = max(0, min(v, 1)) * brightness
        return Color(red: r, green: g, blue: b).opacity(level)
    }

    /// A key that lights now and then and fades: 1 at the start of its
    /// cycle, falling to 0.
    private static func drop(_ led: Int, _ t: Double, rate: Double) -> Double {
        let offset = Double(hash(led, 0) % 100) / 100
        let cycle = t * rate + offset
        let n = Int(floor(cycle))
        guard hash(led, n) % 3 == 0 else { return 0 } // about a third light each cycle
        return pow(1 - (cycle - floor(cycle)), 2)
    }

    private static func hash(_ a: Int, _ b: Int) -> Int {
        var h = UInt64(bitPattern: Int64(a &* 73856093 ^ b &* 19349663))
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        return Int(h % 97)
    }

    private static func rgb(hue h: Double) -> (Double, Double, Double) {
        let i = Int(h * 6) % 6, f = h * 6 - floor(h * 6)
        switch i {
        case 0: return (1, f, 0)
        case 1: return (1 - f, 1, 0)
        case 2: return (0, 1, f)
        case 3: return (0, 1 - f, 1)
        case 4: return (f, 0, 1)
        default: return (1, 0, 1 - f)
        }
    }
}

/// Shown when music mode has heard only silence for a few seconds.
struct NotHearingBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speaker.slash").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("F99 Mood isn't hearing any sound.").font(.callout.weight(.semibold))
                Text(model.settings.musicInput == .system
                     ? "If music is playing, macOS is probably blocking it. Turn on F99 Mood under Screen & System Audio Recording, then stop and start the music again."
                     : "Check that the microphone is allowed and music is playing nearby.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") {
                let pane = model.settings.musicInput == .system ? "Privacy_AudioCapture" : "Privacy_Microphone"
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The music level bar and tempo; the only view that redraws as they change.
struct MusicMeterView: View {
    @ObservedObject var meter: MusicMeter

    var body: some View {
        ProgressView(value: Double(meter.level))
            .frame(width: 120)
            .tint(.pink)
            .accessibilityLabel("Music level")
        Text(meter.bpm > 0 ? "\(Int(meter.bpm)) BPM" : "listening…")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
}
