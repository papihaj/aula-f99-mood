import SwiftUI

/// Local view state. Used instead of `@State`, whose macro needs a full Xcode
/// install; the Command Line Tools alone don't ship it.
final class ViewState<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

extension F99.FirmwareColor {
    var swiftUI: Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
}

// MARK: Menu bar

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusLine()

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(model.settings.moods) { mood in
                        MoodButton(mood: mood)
                    }
                }
            }
            .frame(maxHeight: 340)

            MusicControls()

            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button("Open F99 Mood") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

struct StatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    private var title: String {
        switch model.status {
        case .searching: return "Looking for your F99…"
        case .connected(let name): return name
        case .readOnly: return "Unrecognised keyboard"
        case .unavailable: return "Keyboard not connected"
        }
    }

    private var detail: String? {
        switch model.status {
        case .searching: return nil
        case .connected:
            if let mood = model.activeMood { return "Mood: \(mood.emoji) \(mood.name)" }
            return "Pick a mood"
        case .readOnly(let why), .unavailable(let why): return why
        }
    }

    private var color: Color {
        switch model.status {
        case .connected: return .green
        case .searching: return .yellow
        case .readOnly, .unavailable: return .orange
        }
    }
}

struct MoodButton: View {
    @EnvironmentObject var model: AppModel
    let mood: Mood

    var body: some View {
        let active = model.settings.activeMoodID == mood.id
        Button { model.apply(mood) } label: {
            VStack(spacing: 2) {
                Text(mood.emoji).font(.title2)
                Text((model.settings.startupMoodID == mood.id ? "★ " : "") + mood.name).font(.callout).lineLimit(1)
                if mood.live != nil {
                    Text("LIVE").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.pink, in: Capsule())
                }
                if let key = mood.hotkey {
                    Text(key.display).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(active ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
    }
}

// MARK: Editor window

struct EditorView: View {
    var body: some View {
        TabView {
            MoodsTab().tabItem { Label("Moods", systemImage: "paintpalette") }
            MacrosTab().tabItem { Label("Macros", systemImage: "command") }
            MusicTab().tabItem { Label("Music", systemImage: "music.note") }
            KeyboardTab().tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 480)
    }
}

struct MoodsTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var selection = ViewState<UUID?>(nil)

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection.value) {
                    ForEach(model.settings.moods) { mood in
                        Text("\(mood.emoji)  \(mood.name)").tag(mood.id)
                    }
                    .onMove { model.settings.moods.move(fromOffsets: $0, toOffset: $1) }
                }
                ListButtons(add: {
                    let mood = Mood(name: "New mood", emoji: "✨",
                                    lighting: .init(effect: 1, brightness: 3, speed: 2, color: 6))
                    model.settings.moods.append(mood)
                    selection.value = mood.id
                }, remove: {
                    model.settings.moods.removeAll { $0.id == selection.value }
                    selection.value = nil
                }, canRemove: selection.value != nil)
            }
            .frame(minWidth: 180, maxWidth: 240)

            Group {
                if let i = model.settings.moods.firstIndex(where: { $0.id == selection.value }) {
                    MoodEditor(mood: $model.settings.moods[i])
                } else {
                    Text("Select a mood to edit it").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420)
        }
        .onAppear { selection.value = selection.value ?? model.settings.moods.first?.id }
    }
}

struct MoodEditor: View {
    @EnvironmentObject var model: AppModel
    @Binding var mood: Mood

    var body: some View {
        let effect = F99.effect(mood.lighting.effect)
        Form {
            Section {
                TextField("Name", text: $mood.name)
                TextField("Emoji", text: $mood.emoji)
            }
            Section("Lighting") {
                Picker("Effect", selection: Binding(
                    get: { mood.live.map { 100 + (LiveEffect.allCases.firstIndex(of: $0) ?? 0) } ?? mood.lighting.effect },
                    set: { v in
                        if v >= 100 {
                            mood.live = LiveEffect.allCases[v - 100]
                            mood.lighting.effect = 1
                        } else {
                            mood.live = nil
                            mood.lighting.effect = v
                        }
                    })) {
                    Section("Keyboard's own effects (Fn + \\)") {
                        ForEach(F99.effects) { Text($0.name).tag($0.id) }
                    }
                    Section("Live effects, drawn by your Mac") {
                        ForEach(Array(LiveEffect.allCases.enumerated()), id: \.offset) { i, e in
                            Text(e.rawValue).tag(100 + i)
                        }
                    }
                }
                if let live = mood.live {
                    Text("Inspired by \(live.inspiredBy). Live effects run while F99 Mood is open." +
                         (live.reactsToTyping ? " Lights the keys you press (needs Accessibility permission)." : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LevelSlider(title: "Brightness", value: $mood.lighting.brightness, range: F99.brightnessLevels,
                            note: mood.lighting.brightness == 0 ? "0 turns the lights off" : nil)
                LevelSlider(title: "Speed", value: $mood.lighting.speed, range: F99.speedLevels, note: nil)
                    .disabled(mood.live == nil && effect?.hasSpeed == false)
                ColorRow(color: $mood.lighting.color)
                    .disabled(mood.live == nil && effect?.hasColor == false)
                if mood.live != nil && mood.lighting.color == F99.colorful {
                    Text("Colourful uses the effect's own colours.").font(.caption).foregroundStyle(.secondary)
                } else if mood.live == nil && effect?.hasColor == false {
                    Text("This effect picks its own colours.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Shortcut") {
                HotkeyPicker(hotkey: $mood.hotkey)
            }
            Section {
                Toggle("Start-up mood", isOn: Binding(
                    get: { model.settings.startupMoodID == mood.id },
                    set: { model.setStartupMood($0 ? mood.id : nil) }))
                Text("Switched on whenever F99 Mood opens. Marked with ★.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Use this mood now") { model.apply(mood) }
                        .disabled(!model.canWrite || model.busy)
                    if !model.canWrite { Text("Connect the keyboard by USB-C first").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LevelSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                Text("\(value)").monospacedDigit().frame(width: 20)
            }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ColorRow: View {
    @Binding var color: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("Colour")
            Spacer()
            ForEach(F99.colors) { c in
                Circle().fill(c.swiftUI)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary, lineWidth: color == c.id ? 2.5 : 0.5))
                    .onTapGesture { color = c.id }
                    .help(c.name)
            }
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary, lineWidth: color == F99.colorful ? 2.5 : 0.5))
                .onTapGesture { color = F99.colorful }
                .help("Colourful (cycles colours)")
        }
    }
}

struct HotkeyPicker: View {
    @Binding var hotkey: Hotkey?

    var body: some View {
        let key = hotkey ?? Hotkey(keyCode: 18, modifiers: Hotkey.control | Hotkey.option)
        Toggle("Keyboard shortcut", isOn: Binding(get: { hotkey != nil },
                                                  set: { hotkey = $0 ? key : nil }))
        if hotkey != nil {
            HStack {
                ForEach([("⌃", Hotkey.control), ("⌥", Hotkey.option), ("⇧", Hotkey.shift), ("⌘", Hotkey.command)], id: \.1) { label, bit in
                    Toggle(label, isOn: Binding(
                        get: { key.modifiers & bit != 0 },
                        set: { on in hotkey?.modifiers = on ? key.modifiers | bit : key.modifiers & ~bit }))
                    .toggleStyle(.button)
                }
                Picker("", selection: Binding(get: { key.keyCode }, set: { hotkey?.keyCode = $0 })) {
                    ForEach(Keys.all, id: \.code) { Text($0.name).tag($0.code) }
                }
                .frame(width: 80)
            }
            if key.modifiers == 0 && !(Keys.name(for: key.keyCode) ?? "").hasPrefix("F") {
                Text("Add at least one modifier, or this key will stop typing normally.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct ListButtons: View {
    let add: () -> Void
    let remove: () -> Void
    let canRemove: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) { Image(systemName: "plus").frame(width: 24, height: 20) }
            Button(action: remove) { Image(systemName: "minus").frame(width: 24, height: 20) }
                .disabled(!canRemove)
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(4)
    }
}

// MARK: Macros

struct MacrosTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var selection = ViewState<UUID?>(nil)
    @StateObject private var trusted = ViewState(MacroRunner.canType)

    var body: some View {
        VStack(alignment: .leading) {
            if !trusted.value {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("To type text for you, F99 Mood needs Accessibility permission.")
                    Spacer()
                    Button("Allow…") { MacroRunner.askForAccessibility() }
                    Button("Check again") { trusted.value = MacroRunner.canType }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            HSplitView {
                VStack(spacing: 0) {
                    List(selection: $selection.value) {
                        ForEach(model.settings.macros) { m in
                            VStack(alignment: .leading) {
                                Text(m.name)
                                Text(m.hotkey?.display ?? "No shortcut").font(.caption).foregroundStyle(.secondary)
                            }.tag(m.id)
                        }
                    }
                    ListButtons(add: {
                        let m = Macro(name: "New macro", hotkey: nil, action: .typeText, value: "", moodID: nil)
                        model.settings.macros.append(m)
                        selection.value = m.id
                    }, remove: {
                        model.settings.macros.removeAll { $0.id == selection.value }
                        selection.value = nil
                    }, canRemove: selection.value != nil)
                }
                .frame(minWidth: 180, maxWidth: 240)

                Group {
                    if let i = model.settings.macros.firstIndex(where: { $0.id == selection.value }) {
                        MacroEditor(macro: $model.settings.macros[i])
                    } else {
                        Text("Select a macro to edit it").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 420)
            }
        }
        .onAppear { selection.value = selection.value ?? model.settings.macros.first?.id }
    }
}

struct MacroEditor: View {
    @EnvironmentObject var model: AppModel
    @Binding var macro: Macro

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $macro.name)
                Picker("Action", selection: $macro.action) {
                    ForEach(Macro.Action.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if macro.action == .typeText {
                    VStack(alignment: .leading) {
                        Text("Text to type")
                        TextEditor(text: $macro.value).font(.body.monospaced()).frame(minHeight: 90)
                    }
                } else {
                    TextField("App or link", text: $macro.value, prompt: Text("Spotify, https://…, or /path/to/file"))
                }
            }
            Section("When") {
                Picker("Active in", selection: $macro.moodID) {
                    Text("Every mood").tag(UUID?.none)
                    ForEach(model.settings.moods) { Text("\($0.emoji) \($0.name) only").tag(UUID?.some($0.id)) }
                }
                HotkeyPicker(hotkey: $macro.hotkey)
                if let key = macro.hotkey, model.refusedHotkeys.contains(key) {
                    Text("macOS or another app already uses this shortcut. Pick a different one.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Button("Test now") { MacroRunner.run(macro) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Keyboard

struct KeyboardTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var confirmRestore = ViewState(false)

    var body: some View {
        Form {
            Section("Connection") {
                StatusLine()
                if !model.identity.isEmpty {
                    LabeledContent("Identity", value: model.identity).font(.body.monospaced())
                }
                Button("Reconnect") { model.connect() }.disabled(model.busy)
            }
            if let page = model.page, let cur = page.current {
                Section("On the keyboard right now") {
                    LabeledContent("Effect", value: F99.effect(cur.effect)?.name ?? "Other (\(cur.effect))")
                    LabeledContent("Brightness", value: "\(cur.brightness)")
                    LabeledContent("Speed", value: "\(cur.speed)")
                    LabeledContent("Colour", value: cur.color == F99.colorful ? "Colourful"
                                   : F99.colors.first { $0.id == cur.color }?.name ?? "\(cur.color)")
                    Button("Read again") { model.refresh() }.disabled(model.busy)
                    DisclosureGroup("Raw settings page") {
                        Text(page.hexDump).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            Section("Light strip") {
                StripNote()
            }
            Section("Safety") {
                Text("The first time F99 Mood connects, it saves your keyboard's original settings. Restoring puts back only the lighting from that copy.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Restore original lighting…") { confirmRestore.value = true }
                    .disabled(!model.canWrite || !model.hasBackup || model.busy)
                Text("If the keyboard ever acts strangely, hold Fn + Esc to factory-reset it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore the lighting your keyboard had before F99 Mood?", isPresented: $confirmRestore.value) {
            Button("Restore") { model.restoreOriginal() }
        }
    }
}

// MARK: Music

struct MusicControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.toggleMusic() } label: {
                HStack {
                    Image(systemName: model.musicOn ? "stop.fill" : "music.note")
                    Text(model.musicOn ? "Stop dancing" : "Dance to music")
                    Spacer()
                    if let key = model.settings.musicHotkey {
                        Text(key.display).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(model.musicOn ? Color.pink.opacity(0.25) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(model.busy && !model.musicOn)

            Picker("", selection: Binding(get: { model.settings.musicStyle }, set: { model.setMusicStyle($0) })) {
                ForEach(MusicStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            PaletteChooser()
        }
    }
}

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
}

/// Colour themes for music mode, plus your own colours.
struct PaletteChooser: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                ForEach(MusicPalette.presets + [model.settings.musicPalette.name == MusicPalette.customName
                                                ? model.settings.musicPalette
                                                : MusicPalette(name: MusicPalette.customName, colors: model.settings.customColors)]) { palette in
                    chip(palette)
                }
            }
            if model.settings.musicPaletteName == MusicPalette.customName {
                HStack(spacing: 10) {
                    Text("Your colours").font(.caption)
                    ForEach(model.settings.customColors.indices, id: \.self) { i in
                        ColorPicker("", selection: Binding(
                            get: { model.settings.customColors[i].color },
                            set: { c in
                                var colors = model.settings.customColors
                                colors[i] = RGB(c)
                                model.setCustomColors(colors)
                            }), supportsOpacity: false)
                        .labelsHidden()
                    }
                    if model.settings.customColors.count < 5 {
                        Button { model.setCustomColors(model.settings.customColors + [RGB(1, 1, 1)]) } label: {
                            Image(systemName: "plus.circle")
                        }.buttonStyle(.borderless).help("Add a colour")
                    }
                    if model.settings.customColors.count > 2 {
                        Button { model.setCustomColors(Array(model.settings.customColors.dropLast())) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless).help("Remove the last colour")
                    }
                }
            }
        }
    }

    private func chip(_ palette: MusicPalette) -> some View {
        let selected = model.settings.musicPaletteName == palette.name
        return Button { model.setMusicPalette(palette.name) } label: {
            VStack(spacing: 3) {
                LinearGradient(colors: palette.colors.map(\.color), startPoint: .leading, endPoint: .trailing)
                    .frame(height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(palette.name).font(.caption2).lineLimit(1)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                              lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct MusicTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                MusicControls()
                if model.musicOn && model.hearingNothing { NotHearingBanner() }
                Text("Click a mood while the music plays to dance in that mood's colours and brightness. Picking a colour theme here switches back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Style") {
                ForEach(MusicStyle.allCases) { style in
                    HStack {
                        Image(systemName: model.settings.musicStyle == style ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(style.rawValue)
                            Text(style.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.setMusicStyle(style) }
                }
            }
            Section("Listen to") {
                Picker("Source", selection: Binding(get: { model.settings.musicInput }, set: { model.setMusicInput($0) })) {
                    ForEach(MusicInput.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(model.settings.musicInput == .system
                     ? "Works with Spotify, Apple Music, YouTube and anything else playing on this Mac. The first time, macOS asks to allow audio recording. F99 Mood only measures the sound and never saves it."
                     : "Listens through the microphone, for music playing in the room. Nothing is saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard colours") {
                Toggle("Colour correction for LEDs", isOn: Binding(get: { model.settings.ledColorCorrection },
                                                                  set: { model.setColorCorrection($0) }))
                Text("LEDs look brighter than a screen at the same setting, so dim colours wash out. This adjusts the colours sent to the keyboard so it matches the picture on screen. Turn it off if the keyboard looks too dark.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Comfort") {
                Toggle("Keep every key lit", isOn: Binding(get: { model.settings.keepKeysLit },
                                                           set: { model.setKeepKeysLit($0) }))
                Text("In live effects and music, no key drops below about half brightness, so the letters stay readable. (The keyboard's own built-in effects draw themselves, so this can't apply to them.)")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Reduced flashing", isOn: Binding(get: { model.settings.reducedFlashing },
                                                         set: { model.setReducedFlashing($0) }))
                Text("Softer beats, no white flashes, and slower changes. Even with this off, F99 Mood never flashes the keyboard more than three times a second, and keeps brightness at 80% or less.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcut") {
                HotkeyPicker(hotkey: $model.settings.musicHotkey)
            }
            Section {
                Text("While music mode is on, the Mac sends colours to the keyboard about 20 times a second over the USB-C cable. When you stop it, pick a mood or quit the app, your previous lighting comes back.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Light strip

/// The strip between Backspace and Num Lock: its colour follows moods and
/// themes; its style is picked on the keyboard with Fn + Shift.
struct StripNote: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Light strip matches my mood and theme colours", isOn: Binding(
                get: { model.settings.stripFollowsColors }, set: { model.setStripFollowsColors($0) }))
            Text("The strip changes colour when you pick a mood or a music theme. It can't flash with each beat: its colour is a saved setting, and saving it many times a second would wear out the keyboard's memory. Press Fn + Shift on the keyboard to change its style (static, blinking, …).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
