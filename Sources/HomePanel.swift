import SwiftUI
import UniformTypeIdentifiers

/// Groups of keys people often light together, as quick picks.
enum KeyGroup: String, CaseIterable, Identifiable {
    case wasd = "WASD", arrows = "Arrows", fRow = "F-row", numbers = "Number row", all = "All keys"
    var id: String { rawValue }

    var leds: Set<Int> {
        let names: [String]
        switch self {
        case .wasd: names = ["W", "A", "S", "D"]
        case .arrows: names = ["Up", "Down", "Left", "Right"]
        case .fRow: names = (1...12).map { "F\($0)" }
        case .numbers: names = ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
        case .all: return Set(F99.keys.map(\.led))
        }
        return Set(F99.keys.filter { names.contains($0.name) }.map(\.led))
    }
}

/// What's under a point on the keyboard picture.
enum PictureHit: Equatable {
    case key(Int)
    case light

    /// `p` is in the picture's own points, drawn at `scale` points per pixel.
    static func at(_ p: CGPoint, scale: Double) -> PictureHit? {
        let f = F99.stripFrame
        // The bar is thin, so it's easier to hit than it looks.
        let bar = CGRect(x: f.x * scale, y: f.y * scale, width: f.w * scale, height: f.h * scale).insetBy(dx: -5, dy: -2)
        if bar.contains(p) { return .light }
        if let key = F99.keys.first(where: { F99.keyRect($0, scale).insetBy(dx: -1.5, dy: -1.5).contains(p) }) {
            return .key(key.led)
        }
        return nil
    }
}

extension AppModel {
    /// A click on the picture: a key starts a new selection (⌘ or ⇧ adds or
    /// removes it), the light bar opens its panel, empty space clears.
    func clickPicture(_ hit: PictureHit?, adding: Bool) {
        switch hit {
        case .light:
            selectedKeys = []
            inspecting = .light
        case .key(let led):
            if adding {
                if selectedKeys.contains(led) { selectedKeys.remove(led) } else { selectedKeys.insert(led) }
            } else {
                selectedKeys = [led]
            }
            inspecting = selectedKeys.isEmpty ? nil : .keys
        case nil:
            selectedKeys = []
            if inspecting != .mood { inspecting = nil }
        }
    }

    func closePanel() {
        selectedKeys = []
        inspecting = nil
    }
}

/// The side panel on Home. It's only there while something is picked: the
/// light bar, some keys, or the mood's colours.
struct HomePanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.inspecting {
                    case .light: LightBarPanel()
                    case .keys: KeysPanel()
                    case .mood:
                        if let mood = model.activeMood { MoodPanel(mood: mood) }
                        else { Text("Pick a mood first.").foregroundStyle(.secondary) }
                    case nil: EmptyView()
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(14)
        }
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            let mood = model.activeMood
            let canRevert = mood.map(model.canRevert) ?? false
            if model.inspecting != .light, let mood {
                // Undo what was changed here first; a changed built-in
                // mood only goes all the way back when nothing else is left.
                Button {
                    if model.remixOriginals[mood.id] != nil { model.revertRemix(mood.id) } else { model.revert(mood.id) }
                } label: { Text("Revert").frame(maxWidth: .infinity) }
                    .disabled(!canRevert)
                    .help("Undo your changes to \(mood.name)")
            }
            Button {
                if let mood { model.keepRemix(mood.id) }
                model.closePanel()
            } label: { Text(model.inspecting == .light ? "Done" : "Save").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }
}

/// The panel's title: what's picked, and a line about it.
struct PanelHeader: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let note: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SELECTED").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Theme.lavender)
                Text(title).font(.title3.weight(.semibold))
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button { model.closePanel() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                .buttonStyle(.borderless).foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close")
        }
    }
}

/// A row you pick one of, like a radio button with room for its label.
struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.lavender : Color.secondary)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.lavender.opacity(0.10) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Theme.lavender : Color.black.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A round colour swatch you can pick.
struct ColourDot: View {
    let fill: AnyShapeStyle
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle().fill(fill)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
                .padding(2.5)
                .overlay(Circle().strokeBorder(selected ? Theme.lavender : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static let rainbow = AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
}

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: Light bar

struct LightBarPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let style = model.settings.stripStyle
        PanelHeader(title: "Light bar", note: "The slot beside Delete and Backspace.")
        VStack(spacing: 6) {
            ForEach(StripStyle.allCases) { s in
                ChoiceRow(title: s.rawValue, selected: style == s) { model.setStrip(style: s) }
            }
        }
        if style == .match {
            Text("It takes the colour of the mood or music theme that's on, and the keyboard's own colour cycle for rainbow moods.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if style == .color {
            PanelSection(title: "Colour") {
                HStack(spacing: 6) {
                    ForEach(F99.colors) { c in
                        ColourDot(fill: AnyShapeStyle(c.swiftUI), name: c.name, selected: model.settings.stripColor == c.id) {
                            model.setStrip(style: .color, color: c.id)
                        }
                    }
                }
            }
        }
        if model.stripAlert != nil {
            Text("An alert is blinking on the bar now. Your choice shows once it's cleared.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Label("After the keyboard restarts, press Fn + Shift once to wake the bar.", systemImage: "info.circle")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.lavender.opacity(0.08)))
        Divider()
        KeyGroupChips(title: "Or select keys")
    }
}

// MARK: Keys

struct KeysPanel: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var custom = ViewState(Color(red: 0.82, green: 0.72, blue: 1))

    private var title: String {
        let keys = F99.keys.filter { model.selectedKeys.contains($0.led) }
        if keys.count == 1, let key = keys.first {
            return (KeyboardPicture.labels(key.name).first ?? key.name) + " key"
        }
        if keys.count == F99.keys.count { return "All keys" }
        return "\(keys.count) keys"
    }

    private var note: String {
        if model.musicOn { return "Stop dancing to music to paint keys." }
        guard let mood = model.liveMood ?? model.activeMood else { return "Painting starts a painted mood, “My keys”." }
        if mood.live == nil { return "\(mood.name) is drawn by the keyboard itself, so painting starts a painted mood, “My keys”, in its colour." }
        return "Painted keys stay their colour over \(mood.name)."
    }

    /// The colour the picked keys share, if they're all painted the same.
    private var shared: RGB? {
        guard let mood = model.liveMood ?? model.activeMood else { return nil }
        let colours = model.selectedKeys.map { mood.paint[String($0)] }
        guard let first = colours.first, let first, colours.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var body: some View {
        PanelHeader(title: title, note: note)
        PanelSection(title: "Paint them") {
            let swatches = F99.colors.map { RGB($0.rgb.0, $0.rgb.1, $0.rgb.2) } + Self.pastels
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 7), alignment: .leading, spacing: 6) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { i, c in
                    ColourDot(fill: AnyShapeStyle(c.color), name: i < F99.colors.count ? F99.colors[i].name : "Pastel", selected: shared == c) { model.paintSelectedKeys(c) }
                }
            }
            HStack {
                ColorPicker("Any colour", selection: Binding(get: { custom.value },
                                                             set: { custom.value = $0; model.paintSelectedKeys(RGB($0)) }),
                            supportsOpacity: false)
                Spacer()
                Button("Unpaint") { model.paintSelectedKeys(nil) }
                    .disabled((model.liveMood ?? model.activeMood)?.live == nil)
                    .help("Take the paint off these keys")
            }
        }
        .disabled(model.musicOn)
        Divider()
        KeyGroupChips(title: "Select")
        Text("Drag across keys to pick several. ⌘-click adds or removes one.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// Soft colours like the F99's own pastel effects.
    static let pastels = [RGB(hex: 0xffb3d1), RGB(hex: 0xffd2a8), RGB(hex: 0xfff3a6), RGB(hex: 0xb8f5c8),
                          RGB(hex: 0xa8e6ff), RGB(hex: 0xb9b4ff), RGB(hex: 0xe2b8ff)]
}

/// Quick picks for groups of keys.
struct KeyGroupChips: View {
    @EnvironmentObject var model: AppModel
    let title: String

    var body: some View {
        PanelSection(title: title) {
            FlowRow(spacing: 6) {
                ForEach(KeyGroup.allCases) { g in
                    let on = model.selectedKeys == g.leds
                    Button {
                        model.selectedKeys = g.leds
                        model.inspecting = .keys
                    } label: {
                        Text(g.rawValue).font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(on ? Theme.lavender.opacity(0.15) : Theme.panel))
                            .overlay(Capsule().strokeBorder(on ? Theme.lavender : Color.black.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines.
struct FlowRow: Layout {
    var spacing: Double = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(bounds.width, subviews)
        for (i, p) in rows.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: Double, _ subviews: Subviews) -> (points: [CGPoint], width: Double, height: Double) {
        var points: [CGPoint] = []
        var x = 0.0, y = 0.0, line = 0.0, widest = 0.0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return (points, widest, y + line)
    }
}

// MARK: The mood's colours

struct MoodPanel: View {
    @EnvironmentObject var model: AppModel
    let mood: Mood

    var body: some View {
        let effect = F99.effect(mood.lighting.effect)
        PanelHeader(title: mood.name, note: mood.live.map { "Live: \($0.rawValue)" } ?? effect?.name)
        let fixedEffect = mood.live == nil && effect?.hasColor == false
        if mood.lighting.brightness == 0 || fixedEffect {
            Text("This effect picks its own colours.").font(.callout).foregroundStyle(.secondary)
        } else if mood.live == .painted {
            Text("Click keys on the picture to paint them.").font(.callout).foregroundStyle(.secondary)
        } else if mood.live != nil {
            PanelSection(title: "Colours") { themeChips }
        } else {
            PanelSection(title: "Colour") { colourDots }
        }
        if model.remixOriginals[mood.id] != nil {
            Button { model.saveRemix(mood.id); model.closePanel() } label: {
                Label("Save as a new mood", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Button { model.editMoodRequest = mood.id } label: { Label("Edit effect, speed and shortcut…", systemImage: "slider.horizontal.3") }
            Button { model.danceInColours(of: mood) } label: { Label("Dance to music in these colours", systemImage: "music.note") }
        }
        .buttonStyle(.borderless)
        .disabled(model.busy)
    }

    private var themeChips: some View {
        let own = mood.live?.palette ?? .electric
        let mine = MusicPalette(name: MusicPalette.customName, colors: model.settings.customColors)
        return FlowRow(spacing: 6) {
            chip("Own", own.colors, selected: mood.paletteName == nil && mood.lighting.color == F99.colorful) { m in
                m.paletteName = nil; m.lighting.color = F99.colorful
            }
            ForEach(MusicPalette.presets + [mine]) { p in
                chip(p.name == MusicPalette.customName ? "Mine" : p.name, p.colors, selected: mood.paletteName == p.name) { m in
                    m.paletteName = p.name
                }
            }
        }
    }

    private func chip(_ name: String, _ colors: [RGB], selected: Bool, _ change: @escaping (inout Mood) -> Void) -> some View {
        Button { model.remix(mood.id, change) } label: {
            HStack(spacing: 5) {
                MoodSwatch(colors: colors.map(\.color), corner: 4).frame(width: 16, height: 16)
                Text(name).font(.callout).lineLimit(1)
            }
            .padding(.leading, 4).padding(.trailing, 9).padding(.vertical, 3)
            .background(Capsule().fill(selected ? Theme.lavender.opacity(0.15) : Theme.panel))
            .overlay(Capsule().strokeBorder(selected ? Theme.lavender : Color.black.opacity(0.14), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) colours")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var colourDots: some View {
        HStack(spacing: 4) {
            ForEach(F99.colors) { c in
                ColourDot(fill: AnyShapeStyle(c.swiftUI), name: c.name, selected: mood.lighting.color == c.id) {
                    model.remix(mood.id) { $0.lighting.color = c.id }
                }
            }
            ColourDot(fill: ColourDot.rainbow, name: "Colourful", selected: mood.lighting.color == F99.colorful) {
                model.remix(mood.id) { $0.lighting.color = F99.colorful }
            }
        }
    }
}

/// The mood editor in a sheet over Home.
struct MoodEditorSheet: View {
    @EnvironmentObject var model: AppModel
    let id: UUID
    @StateObject private var confirmDelete = ViewState(false)

    var body: some View {
        Group {
            if let mood = model.settings.moods.first(where: { $0.id == id }) {
                MoodEditor(mood: Binding(
                    get: { model.settings.moods.first { $0.id == id } ?? mood },
                    set: { new in
                        if let i = model.settings.moods.firstIndex(where: { $0.id == new.id }) { model.settings.moods[i] = new }
                    }),
                    onDelete: { confirmDelete.value = true },
                    onClose: { model.editMoodRequest = nil })
            } else {
                VStack(spacing: 12) {
                    Text("This mood was deleted.").foregroundStyle(.secondary)
                    Button("Close") { model.editMoodRequest = nil }.keyboardShortcut(.cancelAction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 580, height: 700)
        .alert("Delete \(model.settings.moods.first { $0.id == id }.map { "“\($0.name)”" } ?? "this mood")?",
               isPresented: $confirmDelete.value) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                model.editMoodRequest = nil
                model.deleteMood(id)
            }
        } message: {
            Text(model.settings.moods.first { $0.id == id }?.builtIn != nil
                 ? "Built-in moods can be put back later with “Restore built-in moods” (… at the top of Home)."
                 : "This can't be undone.")
        }
    }
}

// MARK: Moods menus

/// + at the top of Home: make a mood. The editor opens with it, and you
/// pick a keyboard or live effect there.
struct NewMoodMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button { model.startNewMood() } label: { Label("New mood", systemImage: "plus") }
            .help("Make a new mood")
    }
}

/// The editor for a mood that isn't made yet: Create or Cancel.
struct NewMoodSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let mood = model.newMood {
                MoodEditor(mood: Binding(get: { model.newMood ?? mood }, set: { model.newMood = $0 }), isNew: true)
            }
        }
        .frame(width: 580, height: 700)
    }
}

/// … at the top of Home: hidden moods, sharing moods, and putting the
/// built-in ones back.
struct MoreMoodsMenu: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var message = ViewState<String?>(nil)

    var body: some View {
        let hidden = model.settings.moods.filter(\.hidden)
        Menu {
            if !hidden.isEmpty {
                Menu("Hidden moods") {
                    ForEach(hidden) { m in Button(m.name) { model.editMoodRequest = m.id } }
                }
                Divider()
            }
            Button("Import moods…") { importMoods() }
            Button("Export all moods…") { export(model.settings.moods) }
            if let mood = model.activeMood { Button("Export “\(mood.name)”…") { export([mood]) } }
            Divider()
            Button("Restore built-in moods") {
                let n = model.restoreBuiltInMoods()
                message.value = n == 0 ? "All the built-in moods are already here."
                    : "Added back \(n) built-in mood\(n == 1 ? "" : "s")."
            }
        } label: { Label("More", systemImage: "ellipsis") }
        .menuIndicator(.hidden)
        .help("Hidden moods, import and export")
        .alert(message.value ?? "", isPresented: Binding(get: { message.value != nil }, set: { if !$0 { message.value = nil } })) {
            Button("OK") { message.value = nil }
        }
    }

    private func export(_ moods: [Mood]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = moods.count == 1 ? "\(moods[0].name).f99mood.json" : "F99 Moods.f99mood.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportMoods(moods, to: url) } catch { message.value = "Couldn't save: \(error.localizedDescription)" }
    }

    private func importMoods() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var total = 0
        for url in panel.urls {
            do { total += try model.importMoods(from: url) } catch {
                message.value = "“\(url.lastPathComponent)” isn't an F99 Mood file."
                return
            }
        }
        message.value = "Imported \(total) mood\(total == 1 ? "" : "s"). Shortcuts aren't imported; add your own."
    }
}
