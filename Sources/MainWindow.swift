import SwiftUI
import AVFoundation

/// The main window: a live picture of the F99, moods, and music controls.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    /// Remembered for this Mac only; the picture is the same either way.
    @AppStorage("keyboardIn3D") private var in3D = false
    /// How tall the picture may be, set by dragging the card's bottom edge;
    /// 0 means as big as the window allows.
    @AppStorage("keyboardHeight") private var pictureHeight = 0.0
    @StateObject private var shownHeight = ViewState<CGFloat>(0)
    @StateObject private var dragStart = ViewState<CGFloat?>(nil)
    var body: some View {
        HStack(spacing: 0) {
            page
            // Only there while something is picked, like an inspector.
            if model.inspecting != nil {
                Divider()
                HomePanel().transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.inspecting)
        // Down into the window's rounded bottom edge too, or a white strip shows there.
        .background(Theme.page.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NewMoodMenu()
                MoreMoodsMenu()
            }
        }
        .sheet(isPresented: Binding(get: { !model.settings.welcomeDone },
                                    set: { if !$0 { model.settings.welcomeDone = true } })) {
            WelcomeView().environmentObject(model).buttonStyle(MacButtonStyle())
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusPill()
                Button { model.turnOff() } label: { Label("Off", systemImage: "power") }
                    .controlSize(.small)
                    .disabled(model.isOff)
                    .help("Turn the keyboard's lights off. Pick any mood to turn them back on.")
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
                            .accessibilityLabel("Clear the alert")
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
                // Grows with the window, up to a comfortable size.
                Group {
                    if in3D {
                        Keyboard3D().aspectRatio(2.5, contentMode: .fit).frame(minWidth: 0, maxWidth: .infinity)
                    } else {
                        KeyboardPicture.inCase(KeyboardPicture()
                            .aspectRatio(F99.boardSize.w / F99.boardSize.h, contentMode: .fit))
                    }
                }
                .frame(maxWidth: in3D ? 980 : 760)
                .frame(maxHeight: pictureHeight > 0 ? pictureHeight : nil)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { shownHeight.value = g.size.height }
                        .onChange(of: g.size.height) { shownHeight.value = $0 }
                })
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                HStack {
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Text(in3D ? "Click keys or the light bar · drag to turn · scroll to zoom · double-click to reset"
                              : "Click keys or the light bar to change them")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    if let mood = model.activeMood, !model.musicOn {
                        Button { model.selectedKeys = []; model.inspecting = model.inspecting == .mood ? nil : .mood } label: {
                            Label("Colours", systemImage: "paintpalette")
                        }
                        .controlSize(.small)
                        .help("Change \(mood.name)'s colours")
                    }
                    Picker("View", selection: $in3D) {
                        Text("2D").tag(false)
                        Text("3D").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .controlSize(.small)
                }
            }
            .overlay(alignment: .bottom) { resizeHandle }
            // The picture gets its room first; the mood tiles scroll.
            .layoutPriority(1)

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
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
    }

    /// Drag the card's bottom edge up to make the keyboard smaller, so the
    /// moods below fit without scrolling. Double-click to put it back.
    private var resizeHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 5)
            .frame(width: 90, height: 14)
            .contentShape(Rectangle())
            .offset(y: 7)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart.value ?? shownHeight.value
                    dragStart.value = start
                    pictureHeight = Double(min(max(start + drag.translation.height, 180), 600))
                }
                .onEnded { _ in dragStart.value = nil })
            .onTapGesture(count: 2) { pictureHeight = 0 }
            .help("Drag to make the keyboard smaller or bigger. Double-click to reset.")
            .accessibilityLabel("Keyboard picture size")
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
                }
            }
        }
    }

    static let liveInfo = "Drawn by your Mac, so they need F99 Mood open and the USB-C cable plugged in."

    private var caption: String {
        let preview = model.canWrite ? "" : " · preview, plug in by USB-C"
        if model.musicOn { return "Dancing · \(model.settings.musicStyle.rawValue)" + preview }
        if model.busy && model.canWrite { return "Sending to the keyboard. This takes a second." }
        if let mood = model.liveMood ?? model.activeMood {
            if !model.canWrite { return mood.name + preview }
            if mood.lightsWhenTyping { return mood.name + " · press a few keys to see it" }
            if mood.live != nil { return mood.name + " · if the keys stay dark, press any key" }
            return mood.name
        }
        if let l = model.shownLighting, let effect = F99.effect(l.effect) { return effect.name + preview }
        return "Pick a mood"
    }
}

/// What the keyboard pictures (2D and 3D) show.
extension AppModel {
    /// Nothing moves: a steady or switched-off mood with no live effect or music.
    var pictureIsStill: Bool {
        if liveMood != nil || musicOn { return false }
        guard let l = shownLighting else { return true }
        return l.brightness == 0 || l.effect == 1
    }

    /// The strip's colour as the app expects it: what the keyboard reports,
    /// or, without a keyboard, what the current theme or mood would set.
    var pictureStripColor: F99.FirmwareColor? {
        var id: Int?
        if stripAlert != nil {
            id = settings.stripAlertColor
        } else if settings.stripStyle == .off {
            return nil
        } else if settings.stripStyle == .color {
            id = settings.stripColor
        } else if musicOn {
            id = musicMood.map { $0.lighting.color } ?? settings.musicPalette.stripColor
        } else if let mood = activeMood, mood.lighting.color < F99.colorful {
            id = mood.lighting.color
        }
        if canWrite, let page, id == nil || page.stripColor == id {
            id = page.stripColor
        }
        return F99.colors.first { $0.id == id }
    }

    /// The light under a key, as 0...1 RGB (black when it's dark).
    func light(for key: F99.Key, time: Double) -> RGB {
        if let frame = streamFrame, key.led * 3 + 2 < frame.count {
            return RGB(Double(frame[key.led * 3]) / 255, Double(frame[key.led * 3 + 1]) / 255,
                       Double(frame[key.led * 3 + 2]) / 255)
        }
        guard let l = shownLighting else { return RGB(0, 0, 0) }
        return LightingSimulator.light(for: key, lighting: l, time: time)
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
    /// While dragging across keys: true adds the keys passed over, false
    /// takes them off (a ⌘-drag that started on a picked key).
    @StateObject private var dragAdds = ViewState<Bool?>(nil)

    private func drag(at p: CGPoint, start: CGPoint, scale: Double) {
        let hit = PictureHit.at(p, scale: scale)
        guard let adds = dragAdds.value else {
            // The first touch.
            let flags = NSEvent.modifierFlags
            let adding = flags.contains(.command) || flags.contains(.shift)
            if case .key(let led) = hit {
                dragAdds.value = !(adding && model.selectedKeys.contains(led))
            } else {
                dragAdds.value = true
            }
            model.clickPicture(hit, adding: adding)
            return
        }
        guard case .key(let led) = hit, case .key = PictureHit.at(start, scale: scale) else { return }
        if adds, !model.selectedKeys.contains(led) {
            model.selectedKeys.insert(led)
        } else if !adds, model.selectedKeys.contains(led) {
            model.selectedKeys.remove(led)
        }
        model.inspecting = model.selectedKeys.isEmpty ? nil : .keys
    }

    var body: some View {
        // The light changes every frame; the key legends don't, so they're a
        // separate layer drawn only when the size changes. 20 frames a second
        // looks smooth and costs little (drawing takes well under a
        // millisecond); it stops while another app is in front or nothing is
        // moving, to save CPU.
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: model.pictureIsStill || activeState == .inactive)) { context in
                Canvas { gc, size in
                    let scale = min(size.width / F99.boardSize.w, size.height / F99.boardSize.h)
                    let t = context.date.timeIntervalSinceReferenceDate
                    let lights = F99.keys.map { model.light(for: $0, time: t) }
                    drawStrip(gc, scale)
                    // Light spilling onto the plate around each lit key, under the caps.
                    for (key, light) in zip(F99.keys, lights) {
                        let a = max(light.r, light.g, light.b)
                        guard a > 0.03 else { continue }
                        let hue = Color(red: light.r / a, green: light.g / a, blue: light.b / a)
                        let rect = F99.keyRect(key, scale)
                        gc.fill(RoundedRectangle(cornerRadius: 7 * scale).path(in: rect.insetBy(dx: -4 * scale, dy: -4 * scale)),
                                with: .color(hue.opacity(0.35 * a)))
                        gc.fill(RoundedRectangle(cornerRadius: 5 * scale).path(in: rect.insetBy(dx: -1.8 * scale, dy: -1.8 * scale)),
                                with: .color(hue.opacity(0.75 * a)))
                    }
                    for (key, light) in zip(F99.keys, lights) {
                        drawCap(gc, key, light: light, scale: scale)
                    }
                }
            }
            Canvas { gc, size in
                let scale = min(size.width / F99.boardSize.w, size.height / F99.boardSize.h)
                for key in F99.keys {
                    Self.drawLabel(gc, key, in: Self.face(F99.keyRect(key, scale), scale), scale: scale,
                                   color: Color(red: 0.30, green: 0.28, blue: 0.42).opacity(0.85))
                }
                // What's picked, outlined in lavender.
                for key in F99.keys where model.selectedKeys.contains(key.led) {
                    let rect = F99.keyRect(key, scale).insetBy(dx: -1.5, dy: -1.5)
                    gc.stroke(RoundedRectangle(cornerRadius: 6 * scale).path(in: rect), with: .color(Theme.lavender), lineWidth: 2.2)
                }
                if model.inspecting == .light {
                    let f = F99.stripFrame
                    let rect = CGRect(x: f.x * scale, y: f.y * scale, width: f.w * scale, height: f.h * scale).insetBy(dx: -3.5, dy: -3.5)
                    gc.stroke(Capsule().path(in: rect), with: .color(Theme.lavender), lineWidth: 2.2)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(GeometryReader { geo in
            let scale = min(geo.size.width / F99.boardSize.w, geo.size.height / F99.boardSize.h)
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    drag(at: value.location, start: value.startLocation, scale: scale)
                }.onEnded { _ in dragAdds.value = nil })
        })
        .accessibilityElement()
        .accessibilityLabel("Picture of your keyboard's lighting")
    }

    /// The keyboard in its white case, the way it sits on a desk.
    static func inCase<V: View>(_ picture: V) -> some View {
        picture
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.93, green: 0.93, blue: 0.95)))
            // The F99's case: a thin white rim, a little deeper at the front.
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6))
    }

    /// The top of a keycap: the rect inside its sloped sides.
    static func face(_ rect: CGRect, _ scale: Double) -> CGRect {
        CGRect(x: rect.minX + 2.5 * scale, y: rect.minY + 1.5 * scale,
               width: rect.width - 5 * scale, height: rect.height - 5 * scale)
    }

    /// A keycap in its own colour, tinted by the light shining through it.
    private func drawCap(_ gc: GraphicsContext, _ key: F99.Key, light: RGB, scale: Double) {
        let rect = F99.keyRect(key, scale)
        let cap = Theme.cap(for: key.name)
        let a = max(light.r, light.g, light.b)
        let lit = a > 0.01 ? RGB(light.r / a, light.g / a, light.b / a) : cap
        // The caps keep their own colour, so the board still looks like yours;
        // the light tints them and shows most around their edges.
        let face = cap.lerp(lit, 0.35 * a)
        let side = RGB(face.r * 0.86, face.g * 0.86, face.b * 0.9)
        gc.fill(RoundedRectangle(cornerRadius: 5 * scale).path(in: rect), with: .color(side.color))
        gc.fill(RoundedRectangle(cornerRadius: 4 * scale).path(in: Self.face(rect, scale)), with: .color(face.color))
    }

    /// The light strip, the short slot right of Backspace and Delete, in its
    /// saved colour (the keyboard animates its own style).
    private func drawStrip(_ gc: GraphicsContext, _ scale: Double) {
        let f = F99.stripFrame
        let rect = CGRect(x: f.x * scale, y: f.y * scale, width: f.w * scale, height: f.h * scale)
        let shape = Capsule().path(in: rect)
        gc.fill(shape, with: .color(Color(white: 0.85)))
        if let c = model.pictureStripColor {
            gc.fill(shape, with: .color(Color(red: c.rgb.0, green: c.rgb.1, blue: c.rgb.2).opacity(0.85)))
        }
        gc.stroke(shape, with: .color(.black.opacity(0.2)), lineWidth: 0.8)
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
    static func light(for key: F99.Key, lighting l: ConfigPage.Lighting, time t: Double) -> RGB {
        guard let effect = F99.effect(l.effect) else { return RGB(0, 0, 0) }
        let brightness = Double(min(max(l.brightness, 0), 4)) / 4
        guard brightness > 0 else { return RGB(0, 0, 0) }
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
            let (r, g, b) = rgb(hue: hue - floor(hue))
            guard F99.pastelEffects.contains(effect.id) else { return (r, g, b) }
            return (0.55 + 0.45 * r, 0.55 + 0.45 * g, 0.55 + 0.45 * b)
        }

        var hue = x * 0.8 + ts * 0.08
        var v = 1.0
        switch effect.id {
        case 1: // Fixed on
            break
        case 2: // Breathing
            v = 0.12 + 0.88 * pow(0.5 + 0.5 * sin(ts * 2), 1.5)
        case 3: // Rainbow: the whole board changes colour together
            hue = ts * 0.15
        case 4: // Flash away: the board flashes, then fades
            let p = (ts * 0.6).truncatingRemainder(dividingBy: 1)
            v = pow(1 - p, 3)
            hue = floor(ts * 0.6) * 0.17
        case 5: // Raindrops: random keys light and fade
            v = 0.08 + 0.92 * drop(key.led, ts, rate: 0.9)
            hue = Double(hash(key.led, Int(ts * 0.9))) / 97
        case 6: // Rainbow wheel: hues turn around the centre
            hue = angle - ts * 0.15
        case 7: // Ripples shining: rings from the keys you press; shown from the centre
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
        case 11: // Neon stream: a rainbow wave across the whole board
            hue = x - ts * 0.3
        case 12: // Reaction: dark until you type; only pressed keys light
            v = 0.04
        case 13: // Sine wave: every key lit, brighter along a rolling wave
            let wave = 0.5 + 0.4 * sin(x * 9 - ts * 3)
            v = 0.6 + 0.4 * max(0, 1 - abs((1 - y) - wave) * 3)
            hue = x * 0.8 - ts * 0.15
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

        // Dim keys go dark, and the picture shows the bare keycap.
        let (r, g, b) = fixed(hue)
        let level = max(0, min(v, 1)) * brightness
        return RGB(r * level, g * level, b * level)
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
            Button("Turn on…") {
                // Already allowed: just show the list, don't clear it.
                if model.settings.musicInput == .system {
                    if SystemAudioAccess.allowed == true { PrivacyPane.open("Privacy_AudioCapture") }
                    else { PrivacyPane.turnOn(service: "AudioCapture", pane: "Privacy_AudioCapture") { SystemAudioAccess.request() } }
                } else {
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { PrivacyPane.open("Privacy_Microphone") }
                    else {
                        PrivacyPane.turnOn(service: "Microphone", pane: "Privacy_Microphone") {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in }
                        }
                    }
                }
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
