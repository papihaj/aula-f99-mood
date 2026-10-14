import Combine
import SwiftUI
import IOKit.hid
import AVFoundation

/// The Settings pane: macros, lights, schedule, alerts, typing sounds,
/// start-up, the keyboard connection and permissions, on one page.
struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var loginError = ViewState<String?>(nil)
    @StateObject private var confirmReset = ViewState(false)
    @StateObject private var confirmRestore = ViewState(false)

    var body: some View {
        Form {
            if model.needsAccessibility { AccessibilityBanner(compact: false) }
            MacrosSection()
            Section("Lights") {
                Toggle("Keep every key lit", isOn: Binding(get: { model.settings.keepKeysLit },
                                                           set: { model.setKeepKeysLit($0) }))
                Picker("Light up keys I press", selection: Binding(get: { model.settings.pressGlow },
                                                                   set: { model.settings.pressGlow = $0; model.updatePressGlow() })) {
                    ForEach(PressGlow.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker(selection: Binding(get: { model.settings.stripStyle }, set: { model.setStrip(style: $0) })) {
                    ForEach(StripStyle.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    Text("Light bar")
                    Text("Also on Home: click the bar on the picture. After the keyboard restarts, it stays green until you press Fn + Shift once.")
                }
                if model.settings.stripStyle == .color {
                    ColorRow(color: Binding(get: { model.settings.stripColor },
                                            set: { model.setStrip(style: .color, color: min($0, F99.colors.count - 1)) }),
                             colourful: false)
                }
                Picker("Dim when I'm away", selection: $model.settings.dimAfterMinutes) {
                    Text("Never").tag(0)
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("After \($0) min").tag($0) }
                }
                Toggle("Lights off while locked", isOn: $model.settings.darkWhenLocked)
            }
            ScheduleSection()
            AlertsSection()
            SoundsSection()
            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { loginError.value = model.setLaunchAtLogin($0) }))
                if let error = loginError.value { Text(error).font(.caption).foregroundStyle(.red) }
                Picker("Start-up mood", selection: Binding(get: { model.settings.startupMoodID },
                                                           set: { model.setStartupMood($0) })) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.settings.moods) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show in the Dock", isOn: Binding(get: { model.settings.showInDock },
                                                         set: { model.setShowInDock($0) }))
            }
            Section("Keyboard") {
                StatusLine()
                HStack {
                    Button("Reconnect") { model.connect() }.disabled(model.busy)
                    Button("Restore original lighting…") { confirmRestore.value = true }
                        .disabled(!model.canWrite || !model.hasBackup || model.busy)
                }
            }
            PermissionsSection()
            Section {
                Button("Reset all settings…", role: .destructive) { confirmReset.value = true }
            }
        }
        .formStyle(.grouped)
        // Open without the first schedule time field already selected.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
        .alert("Reset F99 Mood to how it was when first installed?", isPresented: $confirmReset.value) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetAllSettings() }
        } message: {
            Text("All the built-in moods come back, including any you deleted. Moods you made, macros and options are removed.")
        }
        .confirmationDialog("Restore the lighting your keyboard had before F99 Mood?", isPresented: $confirmRestore.value) {
            Button("Restore") { model.restoreOriginal() }
        }
    }
}

/// The permissions F99 Mood needs, in the order setup asks for them.
enum Permission: CaseIterable, Identifiable {
    case inputMonitoring, accessibility, music

    var id: Self { self }

    var name: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        case .music: return MusicInput.systemAvailable ? "Screen & System Audio Recording" : "Microphone"
        }
    }

    var use: String {
        switch self {
        case .inputMonitoring: return "Talking to the keyboard over USB"
        case .accessibility: return "Typing effects, key-press glow, typing sounds and typing macros"
        case .music: return "Making the keys move with music"
        }
    }

    /// The System Settings pane, and the name `tccutil` knows it by.
    private var pane: String {
        switch self {
        case .inputMonitoring: return "Privacy_ListenEvent"
        case .accessibility: return "Privacy_Accessibility"
        case .music: return MusicInput.systemAvailable ? "Privacy_AudioCapture" : "Privacy_Microphone"
        }
    }

    private var service: String {
        switch self {
        case .inputMonitoring: return "ListenEvent"
        case .accessibility: return "Accessibility"
        case .music: return MusicInput.systemAvailable ? "AudioCapture" : "Microphone"
        }
    }

    /// True or false, or nil when macOS can't tell us.
    var allowed: Bool? {
        switch self {
        case .inputMonitoring: return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .accessibility: return AXIsProcessTrusted()
        case .music:
            if MusicInput.systemAvailable { return SystemAudioAccess.allowed }
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// Puts F99 Mood in the right list in System Settings and opens it there,
    /// so you only have to switch it on.
    func turnOn() {
        guard allowed != true else { return PrivacyPane.open(pane) }
        PrivacyPane.turnOn(service: service, pane: pane) {
            switch self {
            case .inputMonitoring: IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            case .accessibility: MacroRunner.askForAccessibility()
            case .music:
                if MusicInput.systemAvailable { SystemAudioAccess.request() }
                else { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
            }
        }
    }
}

/// Opening a Privacy & Security list with F99 Mood already in it. A list
/// can be missing the app (it never asked) or hold an entry for an older
/// copy (the switch looks on but doesn't count), so: clear our entry, ask
/// macOS again (which adds a fresh one), then open that list.
enum PrivacyPane {
    static func turnOn(service: String, pane: String, ask: () -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", service, Bundle.main.bundleIdentifier ?? "local.f99mood"]
        try? p.run()
        p.waitUntilExit()
        ask()
        // Give macOS a moment to add the entry before the list is shown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(pane) }
    }

    static func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

/// macOS has no public way to check Screen & System Audio Recording, so this
/// uses the same private TCC calls as Apple's own sample code does. If they
/// ever go away, the status is unknown and setup just offers the button.
enum SystemAudioAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let service = "kTCCServiceAudioCapture" as CFString

    static var allowed: Bool? {
        guard let sym = dlsym(tcc, "TCCAccessPreflight") else { return nil }
        switch unsafeBitCast(sym, to: Preflight.self)(service, nil) {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    static func request() {
        guard let sym = dlsym(tcc, "TCCAccessRequest") else { return }
        unsafeBitCast(sym, to: Request.self)(service, nil) { _ in }
    }
}

/// One permission: whether it's on, and a button to turn it on.
struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        let ok = permission.allowed
        HStack(spacing: 10) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok == true ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.name)
                Text("\(ok == true ? "Allowed" : ok == false ? "Not allowed" : "Turn on F99 Mood here") · \(permission.use)")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if ok != true {
                Button("Turn on…") { permission.turnOn() }
                    .help("Opens System Settings on the right list, with F99 Mood already in it")
            }
        }
    }
}

/// What macOS really reports for each permission, with a way to fix one
/// whose switch looks on but belongs to an older copy of the app.
struct PermissionsSection: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var tick = ViewState(0)
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            ForEach(Permission.allCases) { PermissionRow(permission: $0) }
            if model.settings.calendarAlerts || CalendarWatcher.status != .notDetermined {
                calendarRow
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Turn on opens the right list in System Settings with F99 Mood already in it. Just switch it on.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .id(tick.value)
        .onReceive(timer) { _ in tick.value += 1 }
    }

    private var calendarRow: some View {
        let ok = CalendarWatcher.allowed
        return HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Calendars")
                Text(ok ? "Allowed · Calendar alerts" : "Not allowed · Calendar alerts").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Turn on…") { model.turnOnCalendars() }
                    .help("Opens System Settings on the right list, with F99 Mood already in it")
            }
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
                Text("Typing effects need Accessibility. Turn it on for F99 Mood.")
                    .font(compact ? .caption : .callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn on…") { Permission.accessibility.turnOn() }
                .controlSize(compact ? .small : .regular)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The first time F99 Mood opens: plug in, allow permissions, then the tour.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var tick = ViewState(0)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

            GroupBox("1. Plug in the keyboard") {
                VStack(alignment: .leading, spacing: 6) {
                    StatusLine()
                    Text("Use a USB-C cable that carries data. Some cables only charge.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Label("Then press Fn + Shift once, so the light strip can follow your moods. Do this again whenever the keyboard restarts.",
                          systemImage: "keyboard")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button("Reconnect") { model.connect() }.disabled(model.busy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("2. Allow three permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Click Turn on next to each one. System Settings opens on the right list with F99 Mood already in it: just switch it on.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Permission.allCases) { PermissionRow(permission: $0) }
                    HStack {
                        Text("macOS only applies some of these after F99 Mood reopens.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Reopen F99 Mood") { model.relaunch() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(tick.value)
                .onReceive(timer) { _ in
                    tick.value += 1
                    // Input Monitoring can start working without a restart.
                    if case .connected = model.status {} else if !model.busy,
                       Permission.inputMonitoring.allowed == true, Keyboard.isPresent, tick.value % 3 == 0 {
                        model.connect()
                    }
                }
            }

            HStack {
                Button("Skip the tour") { model.settings.welcomeDone = true }
                Spacer()
                Button("Next: a quick tour") {
                    model.settings.welcomeDone = true
                    model.tourStep = 0
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// A short first-run tour: one card per page, saying what the page is for.
enum Tour {
    struct Stop {
        let pane: EditorView.Pane
        let title: String
        let text: String
    }

    static let stops = [
        Stop(pane: .home, title: "Home",
             text: "This is your keyboard. Click a tile to change its lighting: keyboard effects are saved on the keyboard, live effects are drawn by your Mac and need the cable. Click keys on the picture to paint them, or the light bar to change it. + at the top makes a new mood, and right-click a tile to edit it."),
        Stop(pane: .music, title: "Music",
             text: "Choose how the keys dance and in which colours, and whether they follow the sound playing on your Mac or the microphone."),
        Stop(pane: .settings, title: "Settings",
             text: "Macros come first: shortcuts that type text or open an app or link (try \u{2303}\u{2325}M for the Music app). Below them: a start-up mood, keeping keys lit, a schedule, alerts, typing sounds and permissions."),
    ]
}

/// The tour's card, in the corner of the window over the page it describes.
struct TourCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let step = model.tourStep {
            let stop = Tour.stops[step]
            let last = step == Tour.stops.count - 1
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(stop.title).font(.headline)
                    Spacer()
                    Text("\(step + 1) of \(Tour.stops.count)").font(.caption).foregroundStyle(.secondary)
                }
                Text(stop.text).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !last { Button("Skip") { model.tourStep = nil }.buttonStyle(.borderless) }
                    Spacer()
                    if step > 0 { Button("Back") { model.tourStep = step - 1 } }
                    Button(last ? "Done" : "Next") {
                        if last { model.tourStep = nil; model.pane = .home } else { model.tourStep = step + 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
            .shadow(radius: 12, y: 4)
            .padding(20)
        }
    }
}

/// Macros, at the top of Settings: shortcuts that type text or open an app
/// or link. Each opens in a sheet to edit.
struct MacrosSection: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var editing = ViewState<UUID?>(nil)
    @StateObject private var trusted = ViewState(MacroRunner.canType)

    var body: some View {
        Section {
            if !trusted.value && model.settings.macros.contains(where: { $0.action == .typeText }) {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("To type text for you, F99 Mood needs Accessibility permission.")
                    Spacer()
                    Button("Allow…") { MacroRunner.askForAccessibility() }
                    Button("Check again") { trusted.value = MacroRunner.canType }
                }
            }
            ForEach(model.settings.macros) { m in
                HStack(spacing: 12) {
                    Text(m.hotkey?.display ?? "No shortcut")
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.name)
                        Text(summary(m)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let id = m.moodID, let mood = model.settings.moods.first(where: { $0.id == id }) {
                        Text("Only in \(mood.name)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Edit") { editing.value = m.id }
                }
                .contextMenu {
                    Button("Edit…") { editing.value = m.id }
                    Button("Delete", role: .destructive) { model.settings.macros.removeAll { $0.id == m.id } }
                }
            }
            if model.settings.macros.isEmpty {
                Text("No macros yet.").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Macros")
                Spacer()
                Button {
                    let m = Macro(name: "New macro", hotkey: nil, action: .typeText, value: "", moodID: nil)
                    model.settings.macros.append(m)
                    editing.value = m.id
                } label: { Label("Add macro", systemImage: "plus") }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .sheet(isPresented: Binding(get: { editing.value != nil }, set: { if !$0 { editing.value = nil } })) {
            if let id = editing.value, let macro = model.settings.macros.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    // Bound by id, so deleting can't leave it pointing at a gone index.
                    MacroEditor(macro: Binding(
                        get: { model.settings.macros.first { $0.id == id } ?? macro },
                        set: { new in
                            if let i = model.settings.macros.firstIndex(where: { $0.id == id }) { model.settings.macros[i] = new }
                        }))
                    Divider()
                    HStack {
                        Button("Delete Macro", role: .destructive) {
                            editing.value = nil
                            model.settings.macros.removeAll { $0.id == id }
                        }
                        Spacer()
                        Button("Done") { editing.value = nil }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(14)
                }
                .frame(width: 520, height: 520)
                .environmentObject(model)
            }
        }
    }

    private func summary(_ m: Macro) -> String {
        if m.value.isEmpty { return "Does nothing yet" }
        return m.action == .typeText ? "Types “\(m.value.prefix(30))”" : "Opens \(m.value)"
    }
}
