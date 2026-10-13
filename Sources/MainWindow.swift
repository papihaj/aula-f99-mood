import SwiftUI

/// The main window: a live picture of the F99, moods, and music controls.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusPill()
                if model.darkened || model.idleDimmed {
                    Label(model.darkened ? "Lights off while locked" : "Dimmed while you're away",
                          systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(.secondary)
                }
                if let alert = model.stripAlert {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.fill").foregroundStyle(.pink)
                        Text(alert).lineLimit(1)
                        Button { model.clearAlert() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear the alert")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.pink.opacity(0.12)))
                }
                Spacer()
                // Undo for the mood that's on, right above the keyboard.
                if let mood = model.activeMood, !model.musicOn, model.canRevert(mood) {
                    Button { model.revert(mood.id) } label: {
                        Label(mood.changedFromBuiltIn ? "Revert \(mood.name) to original" : "Revert colours",
                              systemImage: "arrow.uturn.backward")
                    }
                    .controlSize(.small)
                    .help("Undo your changes to this mood")
                }
            }

            Card(padding: 12) {
                // Always the same size, whatever is below it.
                KeyboardPicture()
                    .frame(width: 600, height: 600 * F99.boardSize.h / F99.boardSize.w)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .underPageBackgroundColor)))
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let mood = model.activeMood, !model.musicOn {
                    Divider()
                    RemixBar(mood: mood)
                }
            }

            if case .unavailable = model.status { WirelessNote() }
            if model.needsAccessibility { AccessibilityBanner(compact: false) }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    moodSection("Keyboard effects", nil,
                                model.settings.moods.filter { $0.live == nil && !$0.hidden })
                    moodSection("Live effects", nil,
                                model.settings.moods.filter { $0.live != nil && !$0.hidden }, info: Self.liveInfo)
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 140)

            Card(padding: 12) {
                if model.musicOn && model.hearingNothing { NotHearingBanner() }
                MusicControls()
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: Binding(get: { !model.settings.welcomeDone },
                                    set: { if !$0 { model.settings.welcomeDone = true } })) {
            WelcomeView().environmentObject(model)
        }
    }

    @ViewBuilder
    private func moodSection(_ title: String, _ note: String?, _ moods: [Mood], info: String? = nil) -> some View {
        if !moods.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    GroupHeader(title: title, note: note)
                    if let info { InfoButton(text: info) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                    ForEach(moods) { MoodButton(mood: $0) }
                    NewMoodTile(live: moods.first?.live != nil)
                }
            }
        }
    }

    static let liveInfo = "Drawn by your Mac, so they need F99 Mood open and the USB-C cable plugged in."

    private var caption: String {
        let preview = model.canWrite ? "" : " · preview, plug in by USB-C"
        if model.musicOn { return "Dancing · \(model.settings.musicStyle.rawValue)" + preview }
        if let mood = model.liveMood ?? model.activeMood { return mood.name + preview }
        if let l = model.shownLighting, let effect = F99.effect(l.effect) { return effect.name + preview }
        return "Pick a mood"
    }
}

/// Draws the F99 from its real key positions and colours each key.
///
/// With music on it shows the exact colours being sent to the keyboard. For
/// moods it imitates the keyboard's built-in effect. That part is only an
/// approximation, because the keyboard draws those effects itself.
struct KeyboardPicture: View {
    @EnvironmentObject var model: AppModel
    /// `.inactive` while another app is in front.
    @Environment(\.controlActiveState) private var activeState

    /// Nothing moves: a steady or switched-off mood with no live effect or music.
    private var isStill: Bool {
        if model.liveMood != nil || model.musicOn { return false }
        guard let l = model.shownLighting else { return true }
        return l.brightness == 0 || l.effect == 1
    }

    var body: some View {
        // The colours change every frame; the key labels and outlines don't,
        // so they're a separate layer drawn only when the size changes.
        // 12 frames a second is smooth enough for a preview, and it stops
        // while another app is in front or nothing is moving, to save CPU.
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 12, paused: isStill || activeState == .inactive)) { context in
                Canvas { gc, size in
                    let scale = min(size.width / F99.boardSize.w, size.height / F99.boardSize.h)
                    let t = context.date.timeIntervalSinceReferenceDate
                    drawStrip(gc, scale)
                    for key in F99.keys {
                        let shape = RoundedRectangle(cornerRadius: 4 * scale).path(in: F99.keyRect(key, scale))
                        // Keycap, then the light shining through it.
                        gc.fill(shape, with: .color(Color(white: 0.98)))
                        gc.fill(shape, with: .color(color(for: key, time: t).opacity(0.85)))
                    }
                }
            }
            Canvas { gc, size in
                let scale = min(size.width / F99.boardSize.w, size.height / F99.boardSize.h)
                for key in F99.keys {
                    let rect = F99.keyRect(key, scale)
                    gc.stroke(RoundedRectangle(cornerRadius: 4 * scale).path(in: rect),
                              with: .color(.black.opacity(0.18)), lineWidth: 0.8)
                    Self.drawLabel(gc, key, in: rect, scale: scale, color: .black.opacity(0.75))
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel("Picture of your keyboard's lighting")
    }

    /// The light strip, in the gap right of Backspace and left of Num Lock,
    /// above the Up arrow, in its saved colour (the keyboard animates its
    /// own style).
    private func drawStrip(_ gc: GraphicsContext, _ scale: Double) {
        guard let back = F99.keys.first(where: { $0.name == "Backspace" }),
              let numLock = F99.keys.first(where: { $0.name == "NumLock" }),
              let up = F99.keys.first(where: { $0.name == "Up" }) else { return }
        let left = back.frame.x + back.frame.w, right = numLock.frame.x
        let width = max(4, (right - left) * 0.35)
        let x = (left + right) / 2 - width / 2
        let top = 4.0 // level with the top row of keys
        let bottom = up.frame.y - 4
        let rect = CGRect(x: x * scale, y: top * scale, width: width * scale, height: (bottom - top) * scale)
        let shape = Capsule().path(in: rect)
        gc.fill(shape, with: .color(Color(white: 0.85)))
        if let c = stripColor {
            gc.fill(shape, with: .color(Color(red: c.rgb.0, green: c.rgb.1, blue: c.rgb.2).opacity(0.85)))
        }
        gc.stroke(shape, with: .color(.black.opacity(0.2)), lineWidth: 0.8)
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

    /// Draw a key's legend in its top-left corner: the longest version
    /// that fits on the key, else the shortest one, shrunk to fit.
    static func drawLabel(_ gc: GraphicsContext, _ key: F99.Key, in rect: CGRect, scale: Double, color: Color) {
        let options = labels(key.name)
        guard !options.isEmpty else { return }
        let inset = 3 * scale
        let room = CGSize(width: rect.width - 2 * inset, height: rect.height - 2 * inset)
        var size = max(6, min(11, rect.height * 0.32))
        func resolved(_ text: String) -> GraphicsContext.ResolvedText {
            gc.resolve(Text(text).font(.system(size: size, weight: .medium)).foregroundColor(color))
        }
        // Measured without a limit: a limited measure wraps to fit and hides
        // the overflow.
        let unlimited = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        var text = options.lazy.map(resolved).first { $0.measure(in: unlimited).width <= room.width }
        if text == nil, let shortest = options.last {
            let width = resolved(shortest).measure(in: unlimited).width
            if width > 0 { size = max(5, size * room.width / width) }
            text = resolved(shortest)
        }
        if let text { gc.draw(text, at: CGPoint(x: rect.minX + inset, y: rect.minY + inset), anchor: .topLeading) }
    }

    /// A key's legends as printed on a Mac keyboard, longest first.
    static func labels(_ name: String) -> [String] {
        switch name {
        case "Esc": return ["esc"]
        case "Backspace": return ["⌫ delete", "⌫"]
        case "Delete": return ["⌦"]
        case "NumLock": return ["clear", "⌧"]
        case "Tab": return ["⇥ tab", "⇥"]
        case "CapsLock": return ["⇪ caps lock", "⇪"]
        case "Enter": return ["⏎ return", "⏎"]
        case "LShift", "RShift": return ["⇧ shift", "⇧"]
        // Modifiers sit where they do on an Apple keyboard: control, option,
        // command on the left; command, fn, option on the right.
        case "LCtrl": return ["⌃ control", "⌃"]
        case "LWin", "RCtrl": return ["⌥ option", "⌥"]
        case "LAlt", "RAlt": return ["⌘ command", "⌘"]
        case "FN": return ["fn"]
        case "Space": return []
        case "Up": return ["▲"]
        case "Down": return ["▼"]
        case "Left": return ["◀"]
        case "Right": return ["▶"]
        case "Home": return ["home"]
        case "End": return ["end"]
        case "PgUp": return ["pg up", "pg↑"]
        case "PgDn": return ["pg dn", "pg↓"]
        default:
            if name.hasPrefix("Num ") { return [String(name.dropFirst(4))] }
            if name.hasPrefix("Num") { return [String(name.dropFirst(3))] }
            return [name]
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
        // Calmer than the keyboard itself, so the window isn't busy.
        let speed = (0.4 + Double(l.speed) * 0.4) * 0.6
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

/// The last tile in a group: make a new mood and open it in the editor.
struct NewMoodTile: View {
    @EnvironmentObject var model: AppModel
    let live: Bool

    var body: some View {
        Menu {
            Button("Keyboard effect") { make(.keyboard) }
            Button("Live effect") { make(.live) }
            Button("Painted keys") { make(.painted) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                Text("New mood").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } primaryAction: {
            make(live ? .live : .keyboard)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Click for a new \(live ? "live" : "keyboard-effect") mood; hold for other kinds")
        .accessibilityLabel("New mood")
    }

    private func make(_ kind: AppModel.NewMoodKind) {
        model.createMood(kind) // switches the sidebar to Moods
    }
}

/// Shown while no keyboard is connected by cable.
struct WirelessNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cable.connector").foregroundStyle(.secondary).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Plug in the keyboard with a USB-C cable to change its lights").font(.callout.weight(.semibold))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// An (i) button that shows a short explanation.
struct InfoButton: View {
    let text: String
    @StateObject private var open = ViewState(false)

    var body: some View {
        Button { open.value.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Why?")
            .popover(isPresented: $open.value) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .frame(width: 300).padding(14)
            }
    }
}
