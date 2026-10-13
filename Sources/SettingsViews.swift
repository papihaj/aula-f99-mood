import Combine
import SwiftUI
import IOKit.hid

/// The Settings pane: lights, schedule, alerts, typing sounds, start-up,
/// appearance, the keyboard connection and permissions, on one page.
struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var loginError = ViewState<String?>(nil)
    @StateObject private var confirmReset = ViewState(false)
    @StateObject private var confirmRestore = ViewState(false)

    var body: some View {
        Form {
            if model.needsAccessibility { AccessibilityBanner(compact: false) }
            Section("Lights") {
                Toggle("Keep every key lit", isOn: Binding(get: { model.settings.keepKeysLit },
                                                           set: { model.setKeepKeysLit($0) }))
                Picker("Light up keys I press", selection: Binding(get: { model.settings.pressGlow },
                                                                   set: { model.settings.pressGlow = $0; model.updatePressGlow() })) {
                    ForEach(PressGlow.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Strip matches colours", isOn: Binding(get: { model.settings.stripFollowsColors },
                                                              set: { model.setStripFollowsColors($0) }))
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
        .confirmationDialog("Reset F99 Mood to how it was when first installed?", isPresented: $confirmReset.value) {
            Button("Reset", role: .destructive) { model.resetAllSettings() }
        } message: {
            Text("Moods, macros and options go back to the defaults.")
        }
        .confirmationDialog("Restore the lighting your keyboard had before F99 Mood?", isPresented: $confirmRestore.value) {
            Button("Restore") { model.restoreOriginal() }
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
            row("Accessibility", "Typing effects, key-press glow, typing sounds and typing macros",
                AXIsProcessTrusted(), pane: "Privacy_Accessibility", service: "Accessibility") {
                MacroRunner.askForAccessibility()
            }
            row("Input Monitoring", "Talking to the keyboard over USB",
                IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
                pane: "Privacy_ListenEvent", service: "ListenEvent") {
                IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                model.connect()
            }
            if model.settings.calendarAlerts || CalendarWatcher.status != .notDetermined {
                row("Calendars", "Calendar alerts", CalendarWatcher.allowed, pane: "Privacy_Calendars", service: "Calendar") {
                    model.requestCalendarAccess { _ in }
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Switch already on but still asked? Press Fix.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .id(tick.value)
        .onReceive(timer) { _ in tick.value += 1 }
    }

    private func row(_ name: String, _ use: String, _ ok: Bool, pane: String, service: String,
                     ask: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(ok ? "Allowed · \(use)" : "Not allowed · \(use)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Fix") {
                    // Clear any old entry for this app, then ask afresh.
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                    p.arguments = ["reset", service, Bundle.main.bundleIdentifier ?? "local.f99mood"]
                    try? p.run()
                    p.waitUntilExit()
                    ask()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
                .help("Clears the old entry and asks again")
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
                Text("Allow F99 Mood in Privacy & Security → Accessibility. Already on? Press Fix in Settings.")
                    .font(compact ? .caption : .callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow…") {
                    MacroRunner.askForAccessibility()
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
                    Text("Use the USB-C cable. If asked, allow Input Monitoring, then Reconnect.")
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
                        ForEach(model.settings.moods) { Text($0.name).tag(UUID?.some($0.id)) }
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
