import SwiftUI

/// "Keep every key lit" and how bright, used in a few places.
struct KeepLitControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Toggle("Keep every key lit", isOn: Binding(get: { model.settings.keepKeysLit },
                                                   set: { model.setKeepKeysLit($0) }))
        if model.settings.keepKeysLit {
            HStack {
                Text("At least")
                Slider(value: Binding(get: { model.settings.keysLitLevel }, set: { model.setKeysLitLevel($0) }),
                       in: 0.2...0.8)
                Text("\(Int((model.settings.keysLitLevel * 100).rounded()))%").monospacedDigit().frame(width: 40)
            }
        }
        Text("In live effects and music, no key drops below this brightness, and very dark colours are lifted, so you can always read the letters. The keyboard's own built-in effects draw themselves, so this can't apply to them.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Everything about how the lights behave: brightness floor, key presses,
/// idle and lock.
struct LightsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Brightness") {
                KeepLitControls()
            }
            Section("Light up keys I press") {
                Picker("In", selection: Binding(get: { model.settings.pressGlow },
                                                set: { model.settings.pressGlow = $0; model.updatePressGlow() })) {
                    ForEach(PressGlow.allCases) { Text($0.rawValue).tag($0) }
                }
                if model.settings.pressGlow != .off {
                    Picker("Colour", selection: Binding(get: { model.settings.pressColor },
                                                        set: { model.settings.pressColor = $0; model.updatePressGlow() })) {
                        ForEach(PressColor.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if model.settings.pressColor == .custom {
                        ColorPicker("My colour", selection: Binding(
                            get: { model.settings.pressCustomColor.color },
                            set: { model.settings.pressCustomColor = RGB($0); model.updatePressGlow() }),
                                    supportsOpacity: false)
                    }
                    HStack {
                        Text("Halo")
                        Slider(value: Binding(get: { model.settings.pressHalo },
                                              set: { model.settings.pressHalo = $0; model.updatePressGlow() }), in: 0...2)
                        Text(model.settings.pressHalo < 0.05 ? "none" : model.settings.pressHalo < 0.75 ? "small"
                             : model.settings.pressHalo < 1.4 ? "medium" : "large").frame(width: 56)
                    }
                    HStack {
                        Text("Fades in")
                        Slider(value: Binding(get: { model.settings.pressFade },
                                              set: { model.settings.pressFade = $0; model.updatePressGlow() }), in: 0.15...1.5)
                        Text(String(format: "%.1f s", model.settings.pressFade)).monospacedDigit().frame(width: 56)
                    }
                }
                Text("The key you press flashes bright and a halo spreads around it. F99 Mood needs Accessibility permission to see key presses in other apps; it only uses which key, to light it, and stores nothing.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.needsAccessibility { AccessibilityBanner(compact: false) }
            }
            Section("When I'm away") {
                Picker("Dim live effects and music after", selection: $model.settings.dimAfterMinutes) {
                    Text("Never").tag(0)
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s")").tag($0) }
                }
                Text("Any key or mouse movement brings them straight back. (This reads only how long since the last input, never what it was.)")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Lights off while the screen is locked or asleep", isOn: $model.settings.darkWhenLocked)
                Text("They come back when you unlock.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// App-wide options.
struct GeneralTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var loginError = ViewState<String?>(nil)
    @StateObject private var confirmReset = ViewState(false)
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Start-up") {
                Toggle("Open F99 Mood when I log in", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { loginError.value = model.setLaunchAtLogin($0) }))
                if let error = loginError.value { Text(error).font(.caption).foregroundStyle(.red) }
                Picker("Start-up mood", selection: Binding(get: { model.settings.startupMoodID },
                                                           set: { model.setStartupMood($0) })) {
                    Text("None: keep the keyboard's own lighting").tag(UUID?.none)
                    ForEach(model.settings.moods) { Text("\($0.emoji) \($0.name)").tag(UUID?.some($0.id)) }
                }
                Text("Switched on whenever F99 Mood opens. Marked with ★.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Toggle("Show in the Dock", isOn: Binding(get: { model.settings.showInDock },
                                                         set: { model.setShowInDock($0) }))
                Text("F99 Mood is always in the menu bar (the keyboard icon).").font(.caption).foregroundStyle(.secondary)
                Button("Show the welcome screen again") {
                    model.settings.welcomeDone = false
                    openWindow(id: "main")
                }
            }
            Section("Your settings") {
                LabeledContent("Saved in", value: Storage.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .textSelection(.enabled)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Storage.settingsURL]) }
                Button("Reset all settings…", role: .destructive) { confirmReset.value = true }
                Text("Moods are shared between computers with Export and Import (the ⋯ button under the mood list).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset F99 Mood to how it was when first installed?", isPresented: $confirmReset.value) {
            Button("Reset", role: .destructive) { model.resetAllSettings() }
        } message: {
            Text("Your moods, macros and options go back to the defaults. Export any moods you want to keep first. The copy of your keyboard's original lighting is kept.")
        }
    }
}

/// Shown while a live effect wants key presses but macOS hasn't allowed it.
struct AccessibilityBanner: View {
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("To light up the keys you press, allow F99 Mood under Privacy & Security → Accessibility.")
                    .font(compact ? .caption : .callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .controlSize(compact ? .small : .regular)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The first time F99 Mood opens: what it does and a few choices.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let icon = NSApp.applicationIconImage { Image(nsImage: icon).resizable().frame(width: 64, height: 64) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to F99 Mood").font(.title.bold())
                    Text("Lighting, moods, macros and music for the AULA F99 on your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("1. Connect the keyboard") {
                VStack(alignment: .leading, spacing: 6) {
                    StatusLine()
                    Text("Use the USB-C cable; the 2.4 GHz receiver and Bluetooth can't change the lighting. If macOS asks, allow F99 Mood under Privacy & Security → Input Monitoring, then press Reconnect.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Reconnect") { model.connect() }.disabled(model.busy)
                        Button("Open Input Monitoring") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("2. Pick how it starts") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Start-up mood", selection: Binding(get: { model.settings.startupMoodID },
                                                               set: { model.setStartupMood($0) })) {
                        Text("None: keep my keyboard's lighting").tag(UUID?.none)
                        ForEach(model.settings.moods) { Text("\($0.emoji) \($0.name)").tag(UUID?.some($0.id)) }
                    }
                    Toggle("Keep every key lit, so I can read the letters", isOn: Binding(
                        get: { model.settings.keepKeysLit }, set: { model.setKeepKeysLit($0) }))
                    Picker("Light up keys I press", selection: Binding(get: { model.settings.pressGlow },
                                                                      set: { model.settings.pressGlow = $0; model.updatePressGlow() })) {
                        ForEach(PressGlow.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Lights off while the screen is locked", isOn: $model.settings.darkWhenLocked)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Everything here can be changed later in Moods & Macros. Live effects and music ask for Accessibility and audio permission only when you first use them.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Start") {
                    model.settings.welcomeDone = true
                    if let id = model.settings.startupMoodID, let mood = model.settings.moods.first(where: { $0.id == id }) {
                        model.apply(mood)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
