import SwiftUI
import UniformTypeIdentifiers

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
                        let light = (c?.luminance ?? 0) > 0.6
                        KeyboardPicture.drawLabel(gc, key, in: rect, scale: scale,
                                                  color: light ? .black.opacity(0.7) : .white.opacity(0.75))
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

/// Moods at set times; a section of the Settings pane.
struct ScheduleSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
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
                Text("Schedule")
            }
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

/// Mail and now-playing on the keys; a section of the Settings pane.
/// An alert also blinks the light strip until it's over or cleared.
struct AlertsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
            Section {
                Toggle("Flash for new mail, Messages and Slack", isOn: $model.settings.mailAlerts)
                if model.settings.mailAlerts && model.mailNotAllowed {
                    HStack {
                        Image(systemName: "hand.raised").foregroundStyle(.orange)
                        Text("Mail alerts need permission to read Mail's unread count.").font(.callout)
                        Spacer()
                        Button("Turn on…") {
                            // Mail asks again on its next check, every few seconds.
                            PrivacyPane.turnOn(service: "AppleEvents", pane: "Privacy_Automation") {}
                        }
                    }
                }
            } header: {
                Text("Alerts")
            }
    }
}

// MARK: Typing sounds

struct SoundsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
            Section("Typing sounds") {
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
            }
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
