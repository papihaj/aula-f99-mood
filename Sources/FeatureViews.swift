import SwiftUI
import EventKit
import UniformTypeIdentifiers

// MARK: Remix

/// Under the keyboard: new colours for the mood that's on, in one tap.
/// The mood changes straight away; Revert puts it back and "Save as new"
/// keeps the remix as a mood of its own.
struct RemixBar: View {
    @EnvironmentObject var model: AppModel
    let mood: Mood
    var compact = false

    var body: some View {
        let changed = model.remixOriginals[mood.id] != nil
        let effect = F99.effect(mood.lighting.effect)
        let fixedEffect = mood.live == nil && effect?.hasColor == false
        // Nothing to remix when the effect picks its own colours or the
        // keys are painted (paint them in the mood editor instead).
        if mood.lighting.brightness > 0 && !fixedEffect && mood.live != .painted {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Remix").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    if changed {
                        Button { model.revertRemix(mood.id) } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                            .help("Put the mood's colours back")
                        if !compact {
                            Button { model.saveRemix(mood.id) } label: { Label("Save as new mood", systemImage: "plus.square.on.square") }
                        }
                    }
                }
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .buttonStyle(.borderless)
                .controlSize(.small)

                if mood.live != nil {
                    themeChips
                } else {
                    colourDots
                }
            }
        }
    }

    private var themeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let own = mood.live?.palette ?? .electric
                let mine = MusicPalette(name: MusicPalette.customName, colors: model.settings.customColors)
                chip("Own", own.colors, selected: mood.paletteName == nil && mood.lighting.color == F99.colorful) { m in
                    m.paletteName = nil; m.lighting.color = F99.colorful
                }
                ForEach(MusicPalette.presets + [mine]) { p in
                    chip(p.name == MusicPalette.customName ? "Mine" : p.name, p.colors, selected: mood.paletteName == p.name) { m in
                        m.paletteName = p.name
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ name: String, _ colors: [RGB], selected: Bool, _ change: @escaping (inout Mood) -> Void) -> some View {
        Button { model.remix(mood.id, change) } label: {
            HStack(spacing: 5) {
                MoodSwatch(colors: colors.map(\.color), corner: 4).frame(width: 16, height: 16)
                Text(name).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 3)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) colours")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var colourDots: some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(F99.colors) { c in
                dot(AnyShapeStyle(c.swiftUI), id: c.id, name: c.name)
            }
            dot(AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)),
                id: F99.colorful, name: "Colourful")
        }
    }

    private func dot(_ fill: AnyShapeStyle, id: Int, name: String) -> some View {
        let selected = mood.lighting.color == id
        return Button { model.remix(mood.id) { $0.lighting.color = id } } label: {
            Circle().fill(fill)
                .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                .padding(2.5)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: Painting

extension F99 {
    /// A key's outline in a picture drawn at `scale` points per pixel.
    static func keyRect(_ key: Key, _ scale: Double) -> CGRect {
        let f = key.frame
        return CGRect(x: f.x * scale, y: f.y * scale, width: f.w * scale, height: f.h * scale).insetBy(dx: 1.2, dy: 1.2)
    }
}

/// Paint each key its own colour: click or drag over keys. Option-click
/// picks up a key's colour.
struct PaintEditor: View {
    @Binding var mood: Mood
    @StateObject private var brush = ViewState(RGB(hex: 0x00e5ff))
    @StateObject private var erasing = ViewState(false)
    @StateObject private var lastKey = ViewState<Int?>(nil)

    static let quick: [UInt32] = [0x00e5ff, 0x2962ff, 0x7c4dff, 0xff2bd6, 0xff1744, 0xff9100, 0xffea00, 0x00e676, 0xffffff]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Tool", selection: $erasing.value) {
                    Image(systemName: "paintbrush.pointed.fill").tag(false).accessibilityLabel("Brush")
                    Image(systemName: "eraser.fill").tag(true).accessibilityLabel("Eraser")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 84)
                ColorPicker("Brush colour", selection: Binding(get: { brush.value.color },
                                                               set: { brush.value = RGB($0); erasing.value = false }),
                            supportsOpacity: false)
                    .labelsHidden()
                HStack(spacing: 4) {
                    ForEach(Self.quick, id: \.self) { hex in
                        let c = RGB(hex: hex)
                        Button { brush.value = c; erasing.value = false } label: {
                            Circle().fill(c.color).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                                .padding(2)
                                .overlay(Circle().strokeBorder(!erasing.value && brush.value == c ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Paint every key in the brush colour") {
                        for k in F99.keys { mood.paint["\(k.led)"] = brush.value }
                    }
                    Button("Use the brush colour for unpainted keys") { mood.paintBase = brush.value }
                    Divider()
                    Button("Clear the painting", role: .destructive) { mood.paint = [:] }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("More painting actions")
            }

            GeometryReader { geo in
                let scale = geo.size.width / F99.boardSize.w
                Canvas { gc, _ in
                    let paint = mood.paintByLED
                    for key in F99.keys {
                        let rect = F99.keyRect(key, scale)
                        let shape = RoundedRectangle(cornerRadius: 4 * scale).path(in: rect)
                        let c = paint[key.led] ?? mood.paintBase
                        gc.fill(shape, with: .color(c.map { $0.color } ?? Color(white: 0.16)))
                        gc.stroke(shape, with: .color(.white.opacity(paint[key.led] != nil ? 0.35 : 0.12)), lineWidth: 0.8)
                        let label = KeyboardPicture.label(key.name)
                        if !label.isEmpty {
                            let light = (c?.luminance ?? 0) > 0.6
                            gc.draw(Text(label).font(.system(size: max(6, min(10, rect.height * 0.3)), weight: .medium))
                                        .foregroundColor(light ? .black.opacity(0.7) : .white.opacity(0.75)),
                                    at: CGPoint(x: rect.minX + 3 * scale, y: rect.minY + 3 * scale), anchor: .topLeading)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in paintAt(value.location, scale: scale) }
                    .onEnded { _ in lastKey.value = nil })
            }
            .aspectRatio(F99.boardSize.w / F99.boardSize.h, contentMode: .fit)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.07)))
            .accessibilityLabel("Keyboard to paint. Click or drag over keys.")

            HStack {
                Toggle("Light the other keys", isOn: Binding(get: { mood.paintBase != nil },
                                                             set: { mood.paintBase = $0 ? RGB(hex: 0x1a0640) : nil }))
                if mood.paintBase != nil {
                    ColorPicker("Colour of the other keys", selection: Binding(
                        get: { (mood.paintBase ?? RGB(0, 0, 0)).color }, set: { mood.paintBase = RGB($0) }), supportsOpacity: false)
                        .labelsHidden()
                }
                Spacer()
                Text("\(mood.paint.count) key\(mood.paint.count == 1 ? "" : "s") painted").font(.caption).foregroundStyle(.secondary)
            }
            Text("Click or drag to paint. Option-click picks up a colour.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paintAt(_ point: CGPoint, scale: Double) {
        guard let key = F99.keys.first(where: { F99.keyRect($0, scale).insetBy(dx: -1.5, dy: -1.5).contains(point) }) else { return }
        guard lastKey.value != key.led else { return }
        lastKey.value = key.led
        if NSEvent.modifierFlags.contains(.option) {
            if let c = mood.paint["\(key.led)"] ?? mood.paintBase { brush.value = c; erasing.value = false }
            return
        }
        if erasing.value { mood.paint["\(key.led)"] = nil } else { mood.paint["\(key.led)"] = brush.value }
    }
}

// MARK: Schedule

struct ScheduleTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.settings.schedule.isEmpty {
                    Text("No times yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($model.settings.schedule) { $entry in
                    ScheduleRow(entry: $entry) {
                        model.settings.schedule.removeAll { $0.id == entry.id }
                    }
                }
                Button {
                    let mood = model.settings.moods.first { $0.name == "Campfire" } ?? model.settings.moods.first
                    model.settings.schedule.append(ScheduleEntry(hour: 22, minute: 0, moodID: mood?.id))
                } label: { Label("Add a time", systemImage: "plus") }
            } header: {
                Text("Switch moods at set times")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let now = Schedule.current(model.settings.schedule, at: Date()),
                       let mood = model.settings.moods.first(where: { $0.id == now.moodID }) {
                        Text("Right now: \(mood.name), since \(Self.time(now)).")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func time(_ e: ScheduleEntry) -> String {
        var c = DateComponents(); c.hour = e.hour; c.minute = e.minute
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// One time on the schedule, laid out like an alarm in the Clock app.
struct ScheduleRow: View {
    @EnvironmentObject var model: AppModel
    @Binding var entry: ScheduleEntry
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                DatePicker("Time", selection: Binding(
                    get: {
                        var c = DateComponents(); c.hour = entry.hour; c.minute = entry.minute
                        return Calendar.current.date(from: c) ?? Date()
                    },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        entry.hour = c.hour ?? 0; entry.minute = c.minute ?? 0
                    }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                if let mood = model.settings.moods.first(where: { $0.id == entry.moodID }) {
                    MoodSwatch(colors: mood.swatch(custom: model.settings.customColors), symbol: mood.symbolName, corner: 6)
                        .frame(width: 26, height: 26)
                }
                Picker("Mood", selection: $entry.moodID) {
                    Text("Choose a mood").tag(UUID?.none)
                    ForEach(model.settings.moods) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
                Toggle("On", isOn: $entry.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                Button(action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).accessibilityLabel("Delete this time")
            }
            HStack(spacing: 4) {
                let symbols = Calendar.current.veryShortWeekdaySymbols
                let order = Array(Calendar.current.firstWeekday...7) + Array(1..<Calendar.current.firstWeekday)
                ForEach(order, id: \.self) { day in
                    let on = entry.days.contains(day)
                    Button {
                        if on { entry.days.remove(day) } else { entry.days.insert(day) }
                    } label: {
                        Text(symbols[day - 1]).font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.07)))
                            .foregroundStyle(on ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Text(entry.daysText).font(.caption).foregroundStyle(.secondary).padding(.leading, 6)
            }
        }
        .opacity(entry.enabled ? 1 : 0.55)
        .padding(.vertical, 2)
    }
}

// MARK: Alerts and now playing

struct AlertsTab: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var denied = ViewState(CalendarWatcher.status == .denied || CalendarWatcher.status == .restricted)

    var body: some View {
        Form {
            Section {
                Toggle("Flash the keyboard before calendar events", isOn: Binding(
                    get: { model.settings.calendarAlerts },
                    set: { on in
                        guard on else { model.settings.calendarAlerts = false; return }
                        if CalendarWatcher.allowed { model.settings.calendarAlerts = true; return }
                        model.requestCalendarAccess { ok in
                            model.settings.calendarAlerts = ok
                            denied.value = !ok
                        }
                    }))
                if denied.value {
                    HStack {
                        Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
                        Text("Allow F99 Mood under Privacy & Security → Calendars.").font(.callout)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
                Picker("When", selection: $model.settings.alertMinutesBefore) {
                    Text("As it starts").tag(0)
                    ForEach([1, 2, 5, 10, 15], id: \.self) { Text("\($0) minute\($0 == 1 ? "" : "s") before").tag($0) }
                }
                ColorPicker("Colour", selection: Binding(get: { model.settings.alertColor.color },
                                                         set: { model.settings.alertColor = RGB($0) }), supportsOpacity: false)
                Stepper("Flashes: \(model.settings.alertFlashes)", value: $model.settings.alertFlashes, in: 1...6)
                HStack {
                    Button("Test flash") { model.flash(color: model.settings.alertColor, times: model.settings.alertFlashes) }
                    if model.settings.calendarAlerts, let next = model.calendar.nextEvent() {
                        Text("Next: \(next.title ?? "Event") at \(next.startDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Uses the Calendar app. Skips all-day events.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Flash when new mail arrives in Mail", isOn: $model.settings.mailAlerts)
                if model.settings.mailAlerts && model.mailNotAllowed {
                    HStack {
                        Image(systemName: "hand.raised").foregroundStyle(.orange)
                        Text("Allow F99 Mood to read Mail's unread count under Privacy & Security → Automation.").font(.callout)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                        }
                    }
                }
            } header: {
                Text("Mail")
            } footer: {
                Text("Checks Mail's unread count every 30 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Turn the light strip a colour while an alert is waiting", isOn: $model.settings.stripAlerts)
                HStack(spacing: 8) {
                    Text("Strip colour")
                    Spacer()
                    ForEach(F99.colors) { c in
                        let on = model.settings.stripAlertColor == c.id
                        Button { model.settings.stripAlertColor = c.id } label: {
                            Circle().fill(c.swiftUI).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                                .padding(2.5)
                                .overlay(Circle().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain).help(c.name).accessibilityLabel(c.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .disabled(!model.settings.stripAlerts)
                if let alert = model.stripAlert {
                    HStack {
                        Label(alert, systemImage: "bell.fill").foregroundStyle(.pink)
                        Spacer()
                        Button("Clear") { model.clearAlert() }
                    }
                }
                Button("Test an alert") {
                    model.raiseAlert("Test alert", until: Date().addingTimeInterval(20), mail: false)
                }
            } header: {
                Text("Light strip")
            } footer: {
                Text("The strip changes colour until the alert is over.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show how far through the song you are", isOn: $model.settings.nowPlayingBar)
                ColorPicker("Bar colour", selection: Binding(get: { model.settings.nowPlayingColor.color },
                                                             set: { model.settings.nowPlayingColor = RGB($0) }), supportsOpacity: false)
                    .disabled(!model.settings.nowPlayingBar)
                if model.settings.nowPlayingBar {
                    if model.nowPlayingNotAllowed {
                        HStack {
                            Image(systemName: "hand.raised").foregroundStyle(.orange)
                            Text("Allow F99 Mood to control Spotify or Music under Privacy & Security → Automation.").font(.callout)
                            Spacer()
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                            }
                        }
                    } else {
                        Label(model.songPlaying ? "A song is playing: watch the keys beside the light strip."
                                                : "Play something in Spotify or Music to see it.",
                              systemImage: model.songPlaying ? "music.note" : "pause.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Now playing")
            } footer: {
                Text("The keys beside the strip fill up as the song plays.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Typing sounds

struct SoundsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Play a sound when I type", isOn: $model.settings.keySounds)
                Picker("Sound", selection: $model.settings.keySound) {
                    ForEach(KeySound.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if model.settings.keySound == .custom {
                    HStack {
                        Text(model.settings.keySoundFile.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No file chosen")
                            .foregroundStyle(model.settings.keySoundFile == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFile() }
                    }
                }
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $model.settings.keySoundVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                Button { model.previewKeySound() } label: { Label("Hear it", systemImage: "play.circle") }
                if let error = model.keySoundError, model.settings.keySounds {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if model.needsAccessibility { AccessibilityBanner(compact: false) }
            } header: {
                Text("Typing sounds")
            } footer: {
                Text("Needs Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keep a copy, so the sound still works if the original moves.
        let dest = Storage.directory.appendingPathComponent("key-sound." + url.pathExtension)
        try? FileManager.default.removeItem(at: dest)
        let path = (try? FileManager.default.copyItem(at: url, to: dest)) != nil ? dest.path : url.path
        model.settings.keySoundFile = nil // reload even if the name is the same
        model.settings.keySoundFile = path
        model.previewKeySound()
    }
}
