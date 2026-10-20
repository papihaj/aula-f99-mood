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

    /// A plain menu, like Keystro's: the window, music, off, and the moods.
    var body: some View {
        Button("Open F99 Mood") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if !model.canWrite { Text("Keyboard not connected") }
        Divider()
        Toggle("Dance to Music", isOn: Binding(get: { model.musicOn }, set: { _ in model.toggleMusic() }))
        Toggle("Lights Off", isOn: Binding(get: { model.isOff }, set: { if $0 { model.turnOff() } }))
            .disabled(model.isOff)
        Divider()
        let shown = model.settings.moods.filter { !$0.hidden }
        ForEach(shown.filter { $0.live == nil }) { moodItem($0) }
        Divider()
        ForEach(shown.filter { $0.live != nil }) { moodItem($0) }
        Divider()
        Button("Quit F99 Mood") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func moodItem(_ mood: Mood) -> some View {
        Toggle(mood.name, isOn: Binding(get: { model.settings.activeMoodID == mood.id && !model.musicOn },
                                        set: { _ in model.apply(mood) }))
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
            if let mood = model.activeMood { return "Mood: \(mood.name)" }
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

/// A mood as a tile filled with its own colours, like a scene in Philips
/// Hue or Apple Home.
struct MoodButton: View {
    @EnvironmentObject var model: AppModel
    let mood: Mood
    @StateObject private var confirmDelete = ViewState(false)
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let active = model.settings.activeMoodID == mood.id
        let dark = scheme == .dark
        let startup = model.settings.startupMoodID == mood.id
        Button { model.apply(mood) } label: {
            ZStack(alignment: .bottomLeading) {
                // Soft versions of the mood's colours on the white theme, deep
                // ones on the dark theme.
                LinearGradient(colors: mood.swatch(custom: model.settings.customColors).map { dark ? $0.deepened(0.45) : $0.softened(0.5) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Image(systemName: mood.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 4)
                        if mood.live != nil {
                            Text("LIVE").font(.system(size: 8, weight: .heavy)).tracking(0.5)
                                .padding(.horizontal, 4).padding(.vertical, 1.5)
                                .background(Capsule().fill(dark ? Color.black.opacity(0.3) : Color.white.opacity(0.7)))
                        }
                        if active {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, Theme.lavender)
                        } else if let key = mood.hotkey {
                            KeycapBadge(hotkey: key)
                        }
                    }
                    Spacer(minLength: 2)
                    HStack(spacing: 4) {
                        Text(mood.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            .minimumScaleFactor(0.75) // long names shrink a little before cutting off
                        if startup { Image(systemName: "power").font(.system(size: 9, weight: .bold)).help("Start-up mood") }
                        Spacer(minLength: 0)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(9)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(active ? Theme.lavender : Color.primary.opacity(0.08), lineWidth: active ? 2.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .disabled(model.busy)
        .help(mood.hotkey.map { "\(mood.name) (\($0.display))" } ?? mood.name)
        .accessibilityLabel("\(mood.name)\(mood.live != nil ? ", live effect" : "")\(startup ? ", start-up mood" : "")")
        .accessibilityAddTraits(active ? .isSelected : [])
        .contextMenu {
            Button("Edit…") { model.editMoodRequest = mood.id }
            Button("Duplicate") { model.duplicateMood(mood.id) }
            Button("Move Left") { model.moveMood(mood.id, by: -1) }
            Button("Move Right") { model.moveMood(mood.id, by: 1) }
            if model.canRevert(mood) {
                Button("Revert to original") { model.revert(mood.id) }
            }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete.value = true }
        }
        .alert("Delete “\(mood.name)”?", isPresented: $confirmDelete.value) {
            Button("Delete", role: .destructive) { model.deleteMood(mood.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(mood.builtIn != nil ? "Built-in moods can be put back later with “Restore built-in moods” (… at the top of Home)."
                                     : "This can't be undone.")
        }
    }
}

/// Tiles sink a little when pressed.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Editor window

/// The main window, laid out like System Settings: a sidebar of panes with
/// outline icons. Home is the keyboard picture, moods and music.
struct EditorView: View {
    @EnvironmentObject var model: AppModel

    enum Pane: String, CaseIterable, Identifiable {
        case home = "Home"
        case music = "Music", settings = "Settings"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .home: "house"
            case .music: "music.note"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Drawn by hand, so the picked page shows in lavender rather
            // than the system's blue.
            List {
                ForEach(Pane.allCases) { row($0) }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.pane {
                case .home: MainView()
                case .music: MusicTab()
                case .settings: SettingsTab()
                }
            }
            .navigationTitle(model.pane == .home ? "F99 Mood" : model.pane.rawValue)
            .overlay(alignment: .bottomTrailing) { TourCard() }
        }
        .frame(minWidth: 980, minHeight: 680)
        // Editing a mood (from a tile, the panel or + New mood) opens over Home.
        // Sheets don't inherit the window's button style, so each sets it.
        .sheet(isPresented: Binding(get: { model.editMoodRequest != nil },
                                    set: { if !$0 { model.editMoodRequest = nil } })) {
            if let id = model.editMoodRequest { MoodEditorSheet(id: id).environmentObject(model).buttonStyle(MacButtonStyle()) }
        }
        .background {
            Color.clear.sheet(isPresented: Binding(get: { model.newMood != nil },
                                                   set: { if !$0 { model.cancelNewMood() } })) {
                NewMoodSheet().environmentObject(model).buttonStyle(MacButtonStyle())
            }
        }
    }

    private func row(_ p: Pane) -> some View {
        let on = model.pane == p
        return Button { model.pane = p } label: {
            Label {
                Text(p.rawValue).fontWeight(on ? .semibold : .regular)
            } icon: {
                // Plain outline icons, all alike; the picked row is solid
                // lavender with white text, like Keystro.
                Image(systemName: p.symbol)
                    .font(.system(size: 14, weight: .medium))
                    // Set here too, or the sidebar paints icons the Mac's blue.
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .frame(width: 22, height: 22)
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.lavender : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct MoodEditor: View {
    @EnvironmentObject var model: AppModel
    @Binding var mood: Mood
    var onDelete: (() -> Void)? = nil
    /// Shown in a sheet: closing it asks about unsaved changes.
    var onClose: (() -> Void)? = nil
    /// A mood that isn't made yet: changes go straight in, and the buttons
    /// are Cancel and Create.
    var isNew = false
    @StateObject private var askToSave = ViewState(false)
    /// Changes not saved yet. The editor is rebuilt for each mood, so this
    /// starts empty whenever another mood is picked.
    @StateObject private var draft = ViewState<Mood?>(nil)

    /// The mood as shown: unsaved changes if there are any.
    private var current: Mood { draft.value ?? mood }
    private var edit: Binding<Mood> {
        isNew ? $mood : Binding(get: { draft.value ?? mood }, set: { draft.value = $0 == mood ? nil : $0 })
    }

    var body: some View {
        let mood = current
        let effect = F99.effect(mood.lighting.effect)
        Form {
            Section {
                HStack {
                    Button("Use this mood now") { model.apply(mood) }
                        .disabled(model.busy)
                        .help(isNew ? "Try it on the keyboard. Cancel puts back the mood from before."
                              : draft.value == nil ? "Show this mood on the keyboard" : "Try your changes on the keyboard without saving them")
                    Button("Dance to music in these colours") { model.danceInColours(of: mood) }
                        .disabled(model.busy)
                    if let onDelete, !isNew {
                        Spacer()
                        Button("Delete mood…", role: .destructive, action: onDelete)
                    }
                }
                if !model.canWrite { Text("Shown on screen until the keyboard is connected by USB-C").font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                TextField("Name", text: edit.name)
                    // Return keeps the new name, like Save.
                    .onSubmit { if !isNew, let d = draft.value { self.mood = d; draft.value = nil } }
                if mood.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Give the mood a name so you can tell it apart.").font(.caption).foregroundStyle(.red)
                } else if model.settings.moods.filter({ $0.name == mood.name }).count > 1 {
                    Text("Another mood has this name too.").font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Icon") { SymbolPicker(mood: edit) }
                Toggle("Show on Home and in the menu bar", isOn: Binding(get: { !mood.hidden }, set: { edit.wrappedValue.hidden = !$0 }))
                if !isNew {
                    // Not part of the draft: it's about which mood, not how it looks.
                    Toggle("Start-up mood", isOn: Binding(get: { model.settings.startupMoodID == mood.id },
                                                          set: { model.setStartupMood($0 ? mood.id : nil) }))
                        .help("Switch to this mood whenever F99 Mood opens or the keyboard connects")
                }
            }
            if mood.live == .painted {
                Section("Painting") { PaintEditor(mood: edit) }
            }
            Section("Lighting") {
                Picker("Effect", selection: Binding(
                    get: { mood.live.map { 100 + (LiveEffect.allCases.firstIndex(of: $0) ?? 0) } ?? mood.lighting.effect },
                    set: { v in
                        var m = edit.wrappedValue
                        if v >= 100 {
                            m.live = LiveEffect.allCases[v - 100]
                            m.lighting.effect = 1
                            if m.live == .painted && m.paintBase == nil { m.paintBase = RGB(hex: 0x1a0640) }
                        } else {
                            m.live = nil
                            m.lighting.effect = v
                        }
                        edit.wrappedValue = m
                    })) {
                    Section("Keyboard's own effects (Fn + \\)") {
                        ForEach(F99.effects.filter { F99.offeredEffects.contains($0.id) || (mood.live == nil && $0.id == mood.lighting.effect) }) {
                            Text($0.name).tag($0.id)
                        }
                    }
                    Section("Live effects, drawn by your Mac") {
                        ForEach(Array(LiveEffect.allCases.enumerated()).filter { LiveEffect.offered.contains($0.element) || $0.element == mood.live },
                                id: \.offset) { i, e in
                            Text(e.rawValue).tag(100 + i)
                        }
                    }
                }
                .macMenu()
                if let live = mood.live {
                    Text("Runs while F99 Mood is open" + (live.reactsToTyping ? " · needs Accessibility" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LevelSlider(title: "Brightness", value: edit.lighting.brightness, range: F99.brightnessLevels,
                            note: mood.lighting.brightness == 0 ? "0 turns the lights off" : nil)
                LevelSlider(title: "Speed", value: edit.lighting.speed, range: F99.speedLevels, note: nil)
                    .disabled(mood.live == nil && effect?.hasSpeed == false)
                if mood.live != nil {
                    Picker("Colours", selection: Binding(
                        get: { mood.paletteName ?? "" },
                        set: { edit.wrappedValue.paletteName = $0.isEmpty ? nil : $0 })) {
                        Text("The colour below").tag("")
                        ForEach(MusicPalette.presets) { Text("Theme: \($0.name)").tag($0.name) }
                        Text("Theme: my custom colours").tag(MusicPalette.customName)
                    }
                    .macMenu()
                    if mood.paletteName == MusicPalette.customName {
                        Text("Edit your custom colours under Music → Colour theme.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ColorRow(color: edit.lighting.color)
                    .disabled((mood.live == nil && effect?.hasColor == false) || mood.paletteName != nil)
                if mood.live != nil && mood.paletteName == nil && mood.lighting.color == F99.colorful {
                    Text("Colourful uses the effect's own colours.").font(.caption).foregroundStyle(.secondary)
                } else if mood.live == nil && effect?.hasColor == false {
                    Text("This effect picks its own colours.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Shortcut and apps") {
                HotkeyPicker(hotkey: edit.hotkey)
                AppList(apps: edit.apps)
                Text("Switches on by itself while one of these apps is in front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isNew {
                Section {
                    HStack {
                        Spacer()
                        Button("Cancel") { model.cancelNewMood() }.keyboardShortcut(.cancelAction)
                        Button("Create") { model.createNewMood() }
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(mood.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
            Section {
                HStack {
                    if let onClose {
                        Button("Close") { if draft.value != nil { askToSave.value = true } else { onClose() } }
                            .keyboardShortcut(.cancelAction)
                    }
                    if draft.value != nil {
                        Text("Unsaved changes").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button {
                        if draft.value != nil { draft.value = nil } else { model.revert(mood.id) }
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(draft.value == nil && !model.canRevert(mood))
                    .help(draft.value != nil ? "Undo your unsaved changes"
                          : mood.changedFromBuiltIn ? "Put this built-in mood back how it came" : "Undo the colour remix")
                    Button("Save") {
                        if let d = draft.value { self.mood = d; draft.value = nil }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.value == nil)
                }
            }
            }
        }
        .formStyle(.grouped)
        .alert("Save your changes to “\(mood.name)”?", isPresented: $askToSave.value) {
            Button("Save") { if let d = draft.value { self.mood = d; draft.value = nil }; onClose?() }
            Button("Don't Save", role: .destructive) { draft.value = nil; onClose?() }
            Button("Cancel", role: .cancel) {}
        }
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
    /// Offer "colourful" (the keys can cycle colours; the light bar can't).
    var colourful = true

    var body: some View {
        HStack(spacing: 8) {
            Text("Colour")
            Spacer()
            ForEach(F99.colors) { c in
                dot(Circle().fill(c.swiftUI), id: c.id, name: c.name)
            }
            if colourful {
                dot(Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)),
                    id: F99.colorful, name: "Colourful (cycles colours)")
            }
        }
    }

    private func dot(_ fill: some View, id: Int, name: String) -> some View {
        Button { color = id } label: {
            fill.frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary, lineWidth: color == id ? 2.5 : 0.5))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(color == id ? .isSelected : [])
    }
}

/// Apps that switch a mood on, picked from /Applications.
struct AppList: View {
    @Binding var apps: [String]

    var body: some View {
        ForEach(apps, id: \.self) { id in
            HStack {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                } else {
                    Text(id).foregroundStyle(.secondary)
                }
                Spacer()
                Button { apps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove")
            }
        }
        Button("Add an app…") {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = true
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            guard panel.runModal() == .OK else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
            }
        }
    }
}

struct HotkeyPicker: View {
    @EnvironmentObject var model: AppModel
    @Binding var hotkey: Hotkey?

    var body: some View {
        let key = hotkey ?? model.settings.freeHotkey
        let isFunctionKey = (Keys.name(for: key.keyCode) ?? "").hasPrefix("F")
        Toggle("Keyboard shortcut", isOn: Binding(get: { hotkey != nil },
                                                  set: { hotkey = $0 ? model.settings.freeHotkey : nil }))
        if let current = hotkey {
            HStack {
                ForEach([("⌃", Hotkey.control), ("⌥", Hotkey.option), ("⇧", Hotkey.shift), ("⌘", Hotkey.command)], id: \.1) { label, bit in
                    Toggle(label, isOn: Binding(
                        get: { key.modifiers & bit != 0 },
                        set: { on in
                            let mods = on ? key.modifiers | bit : key.modifiers & ~bit
                            // A letter or number with no modifier would stop
                            // that key typing anywhere on the Mac.
                            if mods == 0 && !isFunctionKey { return }
                            hotkey?.modifiers = mods
                        }))
                    .toggleStyle(.button)
                    // Its own style, so a pressed key shows lavender and the
                    // others grey.
                    .buttonStyle(.automatic)
                    .tint(key.modifiers & bit != 0 ? Theme.lavender : Color.secondary)
                    .accessibilityLabel(["⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command"][label] ?? label)
                }
                Picker("Key", selection: Binding(get: { key.keyCode }, set: { code in
                    hotkey?.keyCode = code
                    let fn = (Keys.name(for: code) ?? "").hasPrefix("F")
                    if !fn && hotkey?.modifiers == 0 { hotkey?.modifiers = Hotkey.control | Hotkey.option }
                })) {
                    ForEach(Keys.all, id: \.code) { Text($0.name).tag($0.code) }
                }
                .labelsHidden()
                .macMenu()
                .frame(width: 80)
            }
            if model.settings.duplicateHotkeys.contains(current) {
                Text("Another mood, macro or the music shortcut uses \(current.display) too. Only one of them will work, so pick a different one.")
                    .font(.caption).foregroundStyle(.red)
            } else if model.refusedHotkeys.contains(current) {
                Text("macOS or another app already uses \(current.display). Pick a different one.")
                    .font(.caption).foregroundStyle(.red)
            } else if key.modifiers == 0 {
                Text("With no modifier, \(Keys.name(for: key.keyCode) ?? "this key") won't do its usual job while F99 Mood is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: Macros

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
                .macMenu()
                if macro.action == .typeText {
                    VStack(alignment: .leading) {
                        Text("Text to type")
                        TextEditor(text: $macro.value).font(.body.monospaced()).frame(minHeight: 90)
                    }
                } else {
                    TextField("App or link", text: $macro.value, prompt: Text("Paste a link (YouTube, Spotify…) or an app name"))
                }
            }
            Section("When") {
                Picker("Active in", selection: $macro.moodID) {
                    Text("Every mood").tag(UUID?.none)
                    ForEach(model.settings.moods) { Text("\($0.name) only").tag(UUID?.some($0.id)) }
                }
                .macMenu()
                HotkeyPicker(hotkey: $macro.hotkey)
            }
            Section {
                Button("Test now") { MacroRunner.run(macro) }
                    .disabled(macro.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if macro.value.isEmpty {
                    Text(macro.action == .typeText ? "Add the text to type; until then the shortcut does nothing."
                                                   : "Add an app or link to open; until then the shortcut does nothing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if macro.action == .typeText {
                    Text("For your safety, macros never type into password fields.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Music

/// The music card: a round play button like a mini player, the level and
/// tempo, the style and the colours.
struct MusicControls: View {
    @EnvironmentObject var model: AppModel
    /// Style and colours too; only in the Music pane.
    var full = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { model.toggleMusic() } label: {
                    Image(systemName: model.musicOn ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(LinearGradient(colors: model.settings.musicPalette.colors.prefix(3).map(\.color),
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(Circle().strokeBorder(.black.opacity(0.1)))
                }
                .buttonStyle(TileButtonStyle())
                .disabled(model.busy && !model.musicOn)
                .accessibilityLabel(model.musicOn ? "Stop dancing to music" : "Dance to music")

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.musicOn ? "Dancing to music" : "Dance to music").font(.system(size: 13, weight: .semibold))
                    if model.musicOn {
                        HStack(spacing: 8) { MusicMeterView(meter: model.meter) }
                    } else {
                        Text("\(model.settings.musicStyle.rawValue) · \(model.musicMood?.name ?? model.settings.musicPalette.name)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let key = model.settings.musicHotkey { KeycapBadge(hotkey: key) }
            }

            if full {
                Picker("Style", selection: Binding(get: { model.settings.musicStyle }, set: { model.setMusicStyle($0) })) {
                    ForEach(MusicStyle.shown(with: model.settings.musicStyle)) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.settings.musicStyle.summary).font(.caption).foregroundStyle(.secondary)
                PaletteChooser()
            }
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
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
                        ColorPicker("Colour \(i + 1)", selection: Binding(
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
                        }.buttonStyle(.borderless).help("Add a colour").accessibilityLabel("Add a colour")
                    }
                    if model.settings.customColors.count > 2 {
                        Button { model.setCustomColors(Array(model.settings.customColors.dropLast())) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless).help("Remove the last colour").accessibilityLabel("Remove the last colour")
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
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.lavender.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Theme.lavender : Color.secondary.opacity(0.3),
                                                              lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(palette.name) colours")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MusicTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                MusicControls(full: true)
                if model.musicOn && model.hearingNothing { NotHearingBanner() }
            }
            Section("Listen to") {
                Picker("Source", selection: Binding(get: { model.settings.musicInput }, set: { model.setMusicInput($0) })) {
                    ForEach(MusicInput.available) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(model.settings.musicInput == .system
                     ? "Anything playing on this Mac."
                     : MusicInput.systemAvailable ? "Music playing in the room."
                     : "Music playing in the room. Hearing your Mac's own sound needs macOS 14.2 or later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Reduced flashing", isOn: Binding(get: { model.settings.reducedFlashing },
                                                         set: { model.setReducedFlashing($0) }))
                Toggle("Start dancing when F99 Mood opens", isOn: $model.settings.musicAtLaunch)
                HotkeyPicker(hotkey: $model.settings.musicHotkey)
            }
        }
        .formStyle(.grouped)
    }
}

/// Pick the icon on a mood's tile from a grid of symbols.
struct SymbolPicker: View {
    @EnvironmentObject var model: AppModel
    @Binding var mood: Mood
    @StateObject private var open = ViewState(false)

    var body: some View {
        Button { open.value = true } label: {
            HStack(spacing: 6) {
                MoodSwatch(colors: mood.swatch(custom: model.settings.customColors), symbol: mood.symbolName, corner: 6)
                    .frame(width: 28, height: 28)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose an icon")
        .popover(isPresented: $open.value) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Mood.symbolChoices, id: \.self) { name in
                        Button {
                            mood.symbol = name
                            open.value = false
                        } label: {
                            Image(systemName: name).font(.system(size: 14))
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7).fill(mood.symbolName == name ? Theme.lavender.opacity(0.25) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        // "flame.fill" reads as "flame".
                        .accessibilityLabel(name.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                    }
                }
                Button("Use the effect's icon") { mood.symbol = nil; open.value = false }
                    .buttonStyle(.borderless).font(.caption)
            }
            .padding(12)
        }
    }
}
