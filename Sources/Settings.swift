import Foundation

/// A keyboard shortcut: macOS virtual key code plus Carbon modifier flags.
struct Hotkey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    // Carbon modifier bits (cmdKey, shiftKey, optionKey, controlKey).
    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + (Keys.name(for: keyCode) ?? "?")
    }
}

/// Keys offered for shortcuts, with their macOS virtual key codes.
enum Keys {
    static let all: [(name: String, code: UInt32)] = [
        ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3), ("G", 5), ("H", 4),
        ("I", 34), ("J", 38), ("K", 40), ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35),
        ("Q", 12), ("R", 15), ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
        ("Y", 16), ("Z", 6),
        ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23), ("6", 22), ("7", 26), ("8", 28),
        ("9", 25), ("0", 29),
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97), ("F7", 98),
        ("F8", 100), ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111), ("F13", 105),
        ("F14", 107), ("F15", 113), ("F16", 106), ("F17", 64), ("F18", 79), ("F19", 80),
    ]
    static func name(for code: UInt32) -> String? { all.first { $0.code == code }?.name }
}

struct Mood: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String
    var lighting: ConfigPage.Lighting
    var hotkey: Hotkey?
    /// A live effect drawn by the Mac instead of one of the keyboard's own.
    /// Brightness, speed and colour still come from `lighting`.
    var live: LiveEffect? = nil
    /// Live moods: a colour theme by name ("Electric", "Custom", …) used
    /// instead of `lighting.color`. Nil uses the colour, or the effect's own.
    var paletteName: String? = nil
    /// Bundle ids of apps that switch this mood on while they're in front.
    var apps: [String] = []
    /// Left out of the mood grids and the menu bar (still in the editor).
    var hidden = false
    /// An SF Symbol for the mood's tile; nil picks one from the effect.
    var symbol: String? = nil
    /// Painted moods: a colour per key, by LED index ("12": colour).
    var paint: [String: RGB] = [:]
    /// Painted moods: the colour of keys that aren't painted (nil: off).
    var paintBase: RGB? = nil

    init(id: UUID = UUID(), name: String, emoji: String, lighting: ConfigPage.Lighting,
         hotkey: Hotkey?, live: LiveEffect? = nil) {
        self.id = id; self.name = name; self.emoji = emoji
        self.lighting = lighting; self.hotkey = hotkey; self.live = live
    }

    // Every field added after the first version is optional in the file, and
    // a live effect this version doesn't know (from a newer one) is dropped
    // rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "✨"
        lighting = try c.decode(ConfigPage.Lighting.self, forKey: .lighting)
        hotkey = try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        live = try? c.decodeIfPresent(LiveEffect.self, forKey: .live)
        paletteName = try? c.decodeIfPresent(String.self, forKey: .paletteName)
        apps = (try? c.decodeIfPresent([String].self, forKey: .apps)) ?? []
        hidden = (try? c.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        symbol = try? c.decodeIfPresent(String.self, forKey: .symbol)
        paint = (try? c.decodeIfPresent([String: RGB].self, forKey: .paint)) ?? [:]
        paintBase = try? c.decodeIfPresent(RGB.self, forKey: .paintBase)
    }

    /// The painted colour of each LED.
    var paintByLED: [Int: RGB] {
        var m: [Int: RGB] = [:]
        for (k, v) in paint { if let i = Int(k) { m[i] = v } }
        return m
    }

    /// A copy with a new id and no shortcut, for "Duplicate" and imports.
    func copy(named newName: String? = nil) -> Mood {
        var m = self
        m.id = UUID()
        m.name = newName ?? name
        m.hotkey = nil
        m.apps = []
        return m
    }

    /// The built-in mood this one is (matched by name), if any.
    var builtIn: Mood? { AppSettings.builtInMoods.first { $0.name == name } }

    /// Whether this is a built-in mood whose look has been changed.
    var changedFromBuiltIn: Bool {
        guard let b = builtIn else { return false }
        return lighting != b.lighting || live != b.live || paletteName != b.paletteName
            || paint != b.paint || paintBase != b.paintBase || symbol != b.symbol || emoji != b.emoji
    }

    /// The built-in mood's look back, keeping this mood's id, shortcut,
    /// apps and whether it's shown.
    func revertedToBuiltIn() -> Mood {
        guard var m = builtIn else { return self }
        m.id = id
        m.hotkey = hotkey
        m.apps = apps
        m.hidden = hidden
        return m
    }
}

/// Skips list entries that fail to decode, instead of failing the list.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    func decodeLenientArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decode([Lenient<T>].self, forKey: key).compactMap(\.value)
    }
}

struct Macro: Codable, Identifiable, Hashable {
    enum Action: String, Codable, CaseIterable {
        case typeText = "Type text"
        case open = "Open app or link"
    }

    var id = UUID()
    var name: String
    var hotkey: Hotkey?
    var action: Action
    /// The text to type, or the URL / app name / app path to open.
    var value: String
    /// Only active while this mood is on; nil means always active.
    var moodID: UUID?

    init(id: UUID = UUID(), name: String, hotkey: Hotkey?, action: Action, value: String, moodID: UUID?) {
        self.id = id; self.name = name; self.hotkey = hotkey
        self.action = action; self.value = value; self.moodID = moodID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        hotkey = try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        action = try c.decode(Action.self, forKey: .action)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        moodID = try? c.decodeIfPresent(UUID.self, forKey: .moodID)
    }
}

/// How pressed keys light up in live effects.
enum PressGlow: String, Codable, CaseIterable, Identifiable {
    case typingEffects = "Neon Cascade and typing effects"
    case allLive = "Every live effect"
    case off = "Off"
    var id: String { rawValue }
}

enum PressColor: String, Codable, CaseIterable, Identifiable {
    case lightest = "Lightest theme colour"
    case white = "White"
    case custom = "My colour"
    var id: String { rawValue }
}

/// Switch to a mood at a time of day, like an alarm.
struct ScheduleEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var hour: Int
    var minute: Int
    /// Days it runs: 1 Sunday ... 7 Saturday, as `Calendar` counts them.
    var days: Set<Int> = Set(1...7)
    var moodID: UUID?
    var enabled = true

    init(hour: Int, minute: Int, days: Set<Int> = Set(1...7), moodID: UUID?) {
        self.hour = hour; self.minute = minute; self.days = days; self.moodID = moodID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        hour = min(max((try? c.decode(Int.self, forKey: .hour)) ?? 0, 0), 23)
        minute = min(max((try? c.decode(Int.self, forKey: .minute)) ?? 0, 0), 59)
        let d = (try? c.decodeIfPresent(Set<Int>.self, forKey: .days)) ?? Set(1...7)
        days = d.filter { (1...7).contains($0) }
        moodID = try? c.decodeIfPresent(UUID.self, forKey: .moodID)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
    }

    var minuteOfDay: Int { hour * 60 + minute }

    /// "Every day", "Weekdays", "Weekends", "Never" or "Mon, Wed".
    var daysText: String {
        if days.count == 7 { return "Every day" }
        if days.isEmpty { return "Never" }
        if days == Set(2...6) { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let names = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }
}

enum Schedule {
    /// The entry that starts exactly at this minute, if any.
    static func due(_ entries: [ScheduleEntry], at date: Date, calendar: Calendar = .current) -> ScheduleEntry? {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return entries.last { $0.enabled && $0.moodID != nil && $0.days.contains(c.weekday ?? 0)
            && $0.hour == c.hour && $0.minute == c.minute }
    }

    /// The entry that most recently started after `start` and no later than
    /// `end`, if any. Catches an entry whose minute was never checked: the Mac
    /// was asleep, or a clock change skipped it. Looks back at most a week.
    static func latest(_ entries: [ScheduleEntry], after start: Date, through end: Date,
                       calendar: Calendar = .current) -> ScheduleEntry? {
        let from = max(start, end.addingTimeInterval(-7 * 86_400))
        guard from < end else { return nil }
        var best: (at: Date, entry: ScheduleEntry)?
        var day = calendar.startOfDay(for: from)
        while day <= end {
            let weekday = calendar.component(.weekday, from: day)
            for e in entries where e.enabled && e.moodID != nil && e.days.contains(weekday) {
                // A time a clock change skipped moves on to the next one that exists.
                guard let at = calendar.date(bySettingHour: e.hour, minute: e.minute, second: 0, of: day),
                      at > from, at <= end, at >= (best?.at ?? .distantPast) else { continue }
                best = (at, e) // a tie goes to the later entry, as in `due`
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best?.entry
    }

    /// The entry in charge right now: the latest one that has started today,
    /// else the latest from an earlier day this week.
    static func current(_ entries: [ScheduleEntry], at date: Date, calendar: Calendar = .current) -> ScheduleEntry? {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday else { return nil }
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let live = entries.filter { $0.enabled && $0.moodID != nil }
        for back in 0..<7 {
            let day = (weekday - 1 - back + 7) % 7 + 1
            let candidates = live.filter { $0.days.contains(day) && (back > 0 || $0.minuteOfDay <= now) }
            if let e = candidates.max(by: { $0.minuteOfDay < $1.minuteOfDay }) { return e }
        }
        return nil
    }
}

/// What the light bar beside Delete shows.
enum StripStyle: String, Codable, CaseIterable, Identifiable {
    case match = "Match the keys"
    case color = "One colour"
    case off = "Off"
    var id: String { rawValue }
}

/// Light or dark windows, or follow macOS (Settings → General).
enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system = "Match the Mac"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

/// Built-in typing sounds, recorded from real keyboards (CC0; see
/// Resources/Sounds/CREDITS.md), or your own file.
enum KeySound: String, Codable, CaseIterable, Identifiable {
    case tactile = "Tactile"
    case thocky = "Thocky"
    case creamy = "Creamy"
    case rainy = "Creamy light"
    case creamySoft = "Creamy soft"
    case clicky = "Clicky"
    case soft = "Soft"
    case custom = "My own sound file"

    /// The folder in the app's Resources/Sounds holding this sound's takes.
    var folder: String? { self == .custom ? nil : String(describing: self) }
    var id: String { rawValue }
}

struct AppSettings: Codable {
    var musicPalette: MusicPalette {
        if musicPaletteName == MusicPalette.customName {
            return MusicPalette(name: MusicPalette.customName, colors: customColors)
        }
        return MusicPalette.presets.first { $0.name == musicPaletteName } ?? .electric
    }

    var moods: [Mood]
    var macros: [Macro]
    var activeMoodID: UUID?
    var musicStyle: MusicStyle = .spectrum
    var musicInput: MusicInput = .preferred
    /// "Electric", "Fire", … or "Custom".
    var musicPaletteName = MusicPalette.electric.name
    var customColors = [RGB(hex: 0xff00aa), RGB(hex: 0x00e5ff), RGB(hex: 0xffffff)]
    var reducedFlashing = false
    /// Adjust streamed colours for how LEDs look (gamma 2.2).
    var ledColorCorrection = true
    /// The light bar: match moods and music themes, one colour, or off.
    var stripStyle: StripStyle = .match
    /// The light bar's colour for `.color` (a firmware colour id).
    var stripColor = 2
    var stripFollowsColors: Bool { stripStyle == .match }
    /// In live effects and music, no key goes below about half brightness,
    /// so the letters stay readable (the F99's keycaps aren't see-through).
    var keepKeysLit = false
    /// How bright "Keep every key lit" keeps keys, 0.2...0.8.
    var keysLitLevel = 0.5
    /// The mood switched on whenever the app starts or the keyboard connects.
    var startupMoodID: UUID?
    var pressGlow: PressGlow = .typingEffects
    var pressColor: PressColor = .lightest
    var pressCustomColor = RGB(hex: 0xffffff)
    /// Halo size around a pressed key, 0 (none) ... 2.
    var pressHalo = 1.0
    /// How long a pressed key stays lit, in seconds.
    var pressFade = 0.45
    /// Dim live effects and music after this many minutes without typing or
    /// using the mouse; 0 = never.
    var dimAfterMinutes = 0
    /// Turn the lights off while the screen is locked or asleep.
    var darkWhenLocked = true
    /// Show the app in the Dock (it's always in the menu bar).
    var showInDock = true
    /// Start music mode when the app opens.
    var musicAtLaunch = false
    /// The welcome screen has been seen.
    var welcomeDone = false
    /// Moods that switch on at set times.
    var schedule: [ScheduleEntry] = []
    var alertColor = RGB(hex: 0xffb300)
    var alertFlashes = 3
    /// Flash for new messages in Mail, and blink the strip for new
    /// messages in Messages and Slack.
    var mailAlerts = false
    /// Turn the light strip a colour while an alert is waiting (one saved
    /// change per alert, so it doesn't wear the keyboard's memory).
    var stripAlerts = true
    /// A keyboard colour id (4 is magenta: the F99's pink).
    var stripAlertColor = 4
    /// A song's progress on the column of keys beside the light strip.
    var nowPlayingBar = false
    var nowPlayingColor = RGB(hex: 0xffffff)
    var appearance: Appearance = .system
    /// Typing sounds.
    var keySounds = false
    var keySound: KeySound = .tactile
    var keySoundVolume = 0.5
    var keySoundFile: String? = nil
    /// Which set of built-in moods this file was last updated to.
    var moodsVersion = 1
    var musicHotkey: Hotkey? = Hotkey(keyCode: 2, modifiers: Hotkey.control | Hotkey.option) // ⌃⌥D

    private enum LegacyKeys: String, CodingKey { case stripFollowsColors }

    init(moods: [Mood], macros: [Macro], activeMoodID: UUID?) {
        self.moods = moods
        self.macros = macros
        self.activeMoodID = activeMoodID
    }

    // Settings saved by an older version lack the music fields; keep the
    // defaults for those instead of throwing the whole file away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moods = try c.decodeLenientArray(Mood.self, forKey: .moods)
        macros = (try? c.decodeLenientArray(Macro.self, forKey: .macros)) ?? []
        activeMoodID = try c.decodeIfPresent(UUID.self, forKey: .activeMoodID)
        musicStyle = (try? c.decodeIfPresent(MusicStyle.self, forKey: .musicStyle)) ?? .spectrum
        musicInput = (try? c.decodeIfPresent(MusicInput.self, forKey: .musicInput)) ?? .preferred
        if !MusicInput.available.contains(musicInput) { musicInput = .preferred }
        musicPaletteName = try c.decodeIfPresent(String.self, forKey: .musicPaletteName) ?? MusicPalette.electric.name
        reducedFlashing = try c.decodeIfPresent(Bool.self, forKey: .reducedFlashing) ?? false
        ledColorCorrection = try c.decodeIfPresent(Bool.self, forKey: .ledColorCorrection) ?? true
        // Older files had a yes/no "strip matches colours".
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Bool.self, forKey: .stripFollowsColors)
        stripStyle = (try? c.decodeIfPresent(StripStyle.self, forKey: .stripStyle)) ?? (legacy == false ? .off : .match)
        stripColor = min(max((try? c.decodeIfPresent(Int.self, forKey: .stripColor)) ?? 2, 0), F99.colors.count - 1)
        moodsVersion = try c.decodeIfPresent(Int.self, forKey: .moodsVersion) ?? 1
        keepKeysLit = try c.decodeIfPresent(Bool.self, forKey: .keepKeysLit) ?? false
        startupMoodID = try c.decodeIfPresent(UUID.self, forKey: .startupMoodID)
        func opt<T: Decodable>(_ k: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        keysLitLevel = min(max(opt(.keysLitLevel) ?? 0.5, 0.2), 0.8)
        pressGlow = opt(.pressGlow) ?? .typingEffects
        pressColor = opt(.pressColor) ?? .lightest
        pressCustomColor = opt(.pressCustomColor) ?? RGB(hex: 0xffffff)
        pressHalo = min(max(opt(.pressHalo) ?? 1, 0), 2)
        pressFade = min(max(opt(.pressFade) ?? 0.45, 0.15), 2)
        dimAfterMinutes = max(opt(.dimAfterMinutes) ?? 0, 0)
        darkWhenLocked = opt(.darkWhenLocked) ?? true
        showInDock = opt(.showInDock) ?? true
        musicAtLaunch = opt(.musicAtLaunch) ?? false
        // A file saved before the welcome screen existed belongs to someone
        // who has already set the app up.
        welcomeDone = opt(.welcomeDone) ?? true
        schedule = (try? c.decodeLenientArray(ScheduleEntry.self, forKey: .schedule)) ?? []
        alertColor = opt(.alertColor) ?? RGB(hex: 0xffb300)
        alertFlashes = min(max(opt(.alertFlashes) ?? 3, 1), 6)
        mailAlerts = opt(.mailAlerts) ?? false
        stripAlerts = opt(.stripAlerts) ?? true
        stripAlertColor = min(max(opt(.stripAlertColor) ?? 4, 0), F99.colors.count - 1)
        // No longer offered in Settings, so it stays off even in older files.
        nowPlayingBar = false
        nowPlayingColor = opt(.nowPlayingColor) ?? RGB(hex: 0xffffff)
        appearance = opt(.appearance) ?? .system
        keySounds = opt(.keySounds) ?? false
        keySound = opt(.keySound) ?? .tactile
        keySoundVolume = min(max(opt(.keySoundVolume) ?? 0.5, 0), 1)
        keySoundFile = opt(.keySoundFile)
        if let colors = try c.decodeIfPresent([RGB].self, forKey: .customColors), !colors.isEmpty {
            customColors = colors
        }
        if c.contains(.musicHotkey) {
            musicHotkey = try? c.decodeIfPresent(Hotkey.self, forKey: .musicHotkey)
        }
    }

    static func mood(_ name: String, _ emoji: String, _ effect: Int, _ b: Int, _ s: Int, _ c: Int,
                     key: UInt32? = nil) -> Mood {
        Mood(name: name, emoji: emoji,
             lighting: .init(effect: effect, brightness: b, speed: s, color: c),
             hotkey: key.map { Hotkey(keyCode: $0, modifiers: Hotkey.control | Hotkey.option) })
    }

    /// The built-in moods. Most use the keyboard's own animated effects (the
    /// ones Fn + \ cycles through). Shortcuts are ⌃⌥1 to ⌃⌥9, and ⌃⌥0 for
    /// lights out.
    static let builtInMoods: [Mood] = [
        //    name             emoji  effect                 bright speed colour
        mood("Focus",          "🎯", 1,  /* Fixed on */      2, 0, 6, key: 18),
        mood("Gaming",         "🎮", 12, /* Reaction */      4, 2, 0, key: 5), // ⌃⌥G
        mood("Starry Night",   "✨", 8,  /* Stars twinkle */ 2, 1, 6, key: 20),
        mood("Ocean Waves",    "🌊", 13, /* Sine wave */     3, 1, 5, key: 21),
        mood("Rainbow",        "🌈", 11, /* Neon stream */   4, 2, 7, key: 22),
        mood("Pastel Rain",    "🌧️", 5,  /* Raindrops */     4, 3, 7, key: 23), // ⌃⌥5
    ] + liveMoods

    /// Moods with live effects, in the style of other brands' popular ones.
    /// Colour 7 ("colourful") uses each effect's own palette.
    static let liveMoods: [Mood] = [
        //   name              emoji  effect                    bright speed colour
        live("Neon Cascade",   "🌠", .cascade,                 4, 1, 7),
        electricRipples,
        live("Matrix",         "🟩", .matrix,                  4, 2, 7),
        live("Campfire",       "🔥", .fire,                    4, 2, 7),
        live("Aurora",         "🌌", .aurora,                  3, 1, 7),
        live("Typing Heatmap", "🌡️", .typingHeatmap,           4, 2, 7),
        wasd,
        pastelRipples,
    ]

    /// Pastel rings from each key you press, over a soft pastel glow (the
    /// keyboard's own Ripples effect fades every other key to black).
    static let pastelRipples: Mood = {
        var m = live("Pastel Ripples", "🫧", .typingRipples, 4, 2, 7)
        m.paletteName = MusicPalette.pastel.name
        m.hotkey = Hotkey(keyCode: 19, modifiers: Hotkey.control | Hotkey.option) // ⌃⌥2
        return m
    }()

    /// Soft rings spreading from the centre in the Electric colours.
    static let electricRipples: Mood = {
        var m = live("Electric Ripples", "", .ripples, 4, 2, 7)
        m.paletteName = MusicPalette.electric.name
        return m
    }()

    /// Built-in moods that moved the same way as another one, with only the
    /// colours changed (Remix does that now). Taken out of settings on
    /// upgrade unless you changed their effect.
    static let retiredMoods: [(name: String, effect: Int, live: LiveEffect?)] = [
        ("Rainy Day", 5, nil), ("Blossom", 17, nil), ("Windmill", 15, nil), ("Typing Glow", 12, nil),
        ("Starlight", 1, .starlight), ("Visor", 1, .visor), ("Plasma", 1, .plasma),
        ("Galaxy", 1, .galaxy), ("Spiral", 1, .spiral), ("Candlelight", 1, .candle),
        // Version 8: one mood per kind of movement, so each grid fits in two rows.
        ("Neon Night", 11, nil), ("Retro Arcade", 10, nil), ("Scanner", 14, nil),
        ("Storm", 18, nil), ("Waterfall", 16, nil), ("Sparkle Ripples", 7, nil),
        ("Comet", 1, .comet), ("Lava Lamp", 1, .lavaLamp), ("Heartbeat", 1, .heartbeat),
        ("Typing Ripples", 1, .typingRipples),
    ]

    /// A painted example: WASD and the arrows bright on a dim violet board.
    static let wasd: Mood = {
        var m = live("WASD", "🎮", .painted, 4, 0, 7)
        m.paintBase = RGB(hex: 0x1a0640)
        for name in ["W", "A", "S", "D"] { if let k = F99.keys.first(where: { $0.name == name }) { m.paint["\(k.led)"] = RGB(hex: 0x00e5ff) } }
        for name in ["Up", "Down", "Left", "Right"] { if let k = F99.keys.first(where: { $0.name == name }) { m.paint["\(k.led)"] = RGB(hex: 0xff2bd6) } }
        for name in ["Space", "LShift", "LCtrl", "Esc"] { if let k = F99.keys.first(where: { $0.name == name }) { m.paint["\(k.led)"] = RGB(hex: 0x7c4dff) } }
        return m
    }()

    static func live(_ name: String, _ emoji: String, _ effect: LiveEffect, _ b: Int, _ s: Int, _ c: Int) -> Mood {
        Mood(name: name, emoji: emoji, lighting: .init(effect: 1, brightness: b, speed: s, color: c),
             hotkey: nil, live: effect)
    }

    /// The first set of built-in moods, so an unedited copy can be swapped
    /// for the new set (see `upgradeMoods`).
    static let firstMoods: [(String, ConfigPage.Lighting)] = [
        ("Calm", .init(effect: 2, brightness: 2, speed: 1, color: 5)),
        ("Cozy", .init(effect: 2, brightness: 1, speed: 0, color: 3)),
        ("Energized", .init(effect: 7, brightness: 4, speed: 3, color: 7)),
        ("Party", .init(effect: 3, brightness: 4, speed: 4, color: 7)),
        ("Gaming", .init(effect: 12, brightness: 4, speed: 2, color: 0)),
    ]
    /// 2: the effect-based set. 3: Gaming is back. 4: live effects.
    /// 5: Neon Cascade. 6: WASD (painted keys). 7: Electric Ripples, and
    /// look-alike moods retired. 8: more look-alikes retired. 10: Rainbow
    /// Wheel becomes Rainbow on Neon stream (effect 6 leaves an F99's keys
    /// dark), Pastel Ripples, and Lights out gives way to the Off button.
    /// 11: Pastel Rain.
    static let moodsVersion = 11

    /// What a new user starts with: the built-in moods, no macros, and the
    /// keyboard left on its own lighting until they pick a mood. Your own
    /// choices live in your settings file, never in the app.
    static let defaults: AppSettings = {
        // One example macro, so the Macros page shows what they do.
        let openMusic = Macro(name: "Open Music", hotkey: Hotkey(keyCode: 46, modifiers: Hotkey.control | Hotkey.option), // ⌃⌥M
                              action: .open, value: "Music", moodID: nil)
        var s = AppSettings(moods: builtInMoods, macros: [openMusic], activeMoodID: nil)
        s.moodsVersion = moodsVersion
        // Examples to switch on: a warm glow at night, Focus on weekday mornings.
        func sample(_ hour: Int, _ days: Set<Int>, _ mood: String) -> ScheduleEntry? {
            guard let id = s.moods.first(where: { $0.name == mood })?.id else { return nil }
            var e = ScheduleEntry(hour: hour, minute: 0, days: days, moodID: id)
            e.enabled = false
            return e
        }
        s.schedule = [sample(22, Set(1...7), "Campfire"), sample(9, Set(2...6), "Focus")].compactMap { $0 }
        return s
    }()

    /// Bring moods saved by an older version up to date: drop the old
    /// built-in moods you haven't changed, keep everything you made or
    /// edited, and add the new built-in moods you don't have yet.
    mutating func upgradeMoods() {
        guard moodsVersion < Self.moodsVersion else { return }
        moods.removeAll { m in
            Self.firstMoods.contains { $0.0 == m.name && $0.1 == m.lighting }
                && !Self.builtInMoods.contains { $0.name == m.name }
        }
        if moodsVersion < 8 {
            for r in Self.retiredMoods {
                for m in moods where m.name == r.name && m.lighting.effect == r.effect && m.live == r.live
                    && m.id != startupMoodID && !schedule.contains(where: { $0.moodID == m.id }) {
                    deleteMood(m.id)
                }
            }
        }
        if moodsVersion < 10 {
            // Effect 6 shows nothing on a real F99. Neon stream (11) is the
            // rainbow that fills the board (3 turns it all one colour).
            for i in moods.indices where moods[i].lighting.effect == 6
                || (moods[i].name == "Rainbow" && moods[i].lighting.effect == 3) {
                moods[i].lighting.effect = 11
                if moods[i].name == "Rainbow Wheel" { moods[i].name = "Rainbow" }
            }
            // The Off button replaces Lights out.
            for m in moods where m.name == "Lights out" && m.live == nil && m.lighting.brightness == 0
                && m.id != startupMoodID && !schedule.contains(where: { $0.moodID == m.id }) {
                deleteMood(m.id)
            }
        }
        addMissingBuiltInMoods()
        if let id = activeMoodID, !moods.contains(where: { $0.id == id }) { activeMoodID = nil }
        moodsVersion = Self.moodsVersion
    }

    /// Put back any built-in mood that isn't in the list (by name), leaving
    /// the rest alone. Returns how many were added.
    @discardableResult
    mutating func addMissingBuiltInMoods() -> Int {
        var taken = Set(moods.compactMap(\.hotkey) + macros.compactMap(\.hotkey) + [musicHotkey].compactMap { $0 })
        var added = 0
        // Add each missing built-in mood after the one before it in the
        // built-in list (so Gaming lands after Focus), else at the end.
        for (i, var mood) in Self.builtInMoods.enumerated() where !moods.contains(where: { $0.name == mood.name }) {
            if let key = mood.hotkey, taken.contains(key) { mood.hotkey = nil }
            if let key = mood.hotkey { taken.insert(key) }
            let previous = i > 0 ? moods.firstIndex { $0.name == Self.builtInMoods[i - 1].name } : nil
            let at = previous.map { $0 + 1 } ?? moods.count
            moods.insert(mood, at: at)
            added += 1
        }
        return added
    }

    /// Add moods from a shared file: new ids, no shortcuts or apps (they're
    /// someone else's), and "(2)" after a name that's already taken.
    @discardableResult
    mutating func importMoods(_ incoming: [Mood]) -> [Mood] {
        var added: [Mood] = []
        for m in incoming {
            var name = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = "Imported mood" }
            let base = name
            var n = 2
            while moods.contains(where: { $0.name == name }) { name = "\(base) (\(n))"; n += 1 }
            let copy = m.copy(named: name)
            moods.append(copy)
            added.append(copy)
        }
        return added
    }

    /// Every shortcut used more than once: by moods, macros or music.
    var duplicateHotkeys: Set<Hotkey> {
        var seen = Set<Hotkey>(), dupes = Set<Hotkey>()
        for key in moods.compactMap(\.hotkey) + macros.compactMap(\.hotkey) + [musicHotkey].compactMap({ $0 }) {
            if !seen.insert(key).inserted { dupes.insert(key) }
        }
        return dupes
    }

    /// The first ⌃⌥ shortcut nobody uses yet, for a newly switched-on one.
    var freeHotkey: Hotkey {
        let used = Set(moods.compactMap(\.hotkey) + macros.compactMap(\.hotkey) + [musicHotkey].compactMap { $0 })
        for k in Keys.all {
            let h = Hotkey(keyCode: k.code, modifiers: Hotkey.control | Hotkey.option)
            if !used.contains(h) { return h }
        }
        return Hotkey(keyCode: 18, modifiers: Hotkey.control | Hotkey.option | Hotkey.shift)
    }

    /// Remove a mood and everything pointing at it.
    mutating func deleteMood(_ id: UUID) {
        moods.removeAll { $0.id == id }
        if activeMoodID == id { activeMoodID = nil }
        if startupMoodID == id { startupMoodID = nil }
        for i in schedule.indices where schedule[i].moodID == id { schedule[i].moodID = nil }
        for i in macros.indices where macros[i].moodID == id { macros[i].moodID = nil }
    }
}

/// A file of moods to share: what "Export moods…" writes and "Import" reads.
struct MoodFile: Codable {
    var app = "F99 Mood"
    var version = 1
    var moods: [Mood]

    init(moods: [Mood]) { self.moods = moods }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moods = try c.decodeLenientArray(Mood.self, forKey: .moods)
    }
}

/// Settings live in ~/Library/Application Support/F99 Mood/.
enum Storage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("F99 Mood", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let settingsURL = directory.appendingPathComponent("settings.json")
    /// The settings page as it was the first time the app saw the keyboard.
    static let backupURL = directory.appendingPathComponent("original-settings.bin")

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return .defaults }
        guard var s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            // Don't overwrite a file we can't read: keep it next to the new one.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.moveItem(at: settingsURL,
                                              to: directory.appendingPathComponent("settings-unreadable-\(stamp).json"))
            return .defaults
        }
        if s.moodsVersion < AppSettings.moodsVersion {
            s.upgradeMoods()
            save(s)
        }
        return s
    }

    static func save(_ s: AppSettings) {
        try? encode(s).write(to: settingsURL, options: .atomic)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(value)
    }

    /// The lighting from before a live effect or music switched the keyboard
    /// to per-key mode. That switch is saved on the keyboard, so if the app
    /// can't switch it back (unplugged, crash, Force Quit), this file lets it
    /// put things right the next time it connects.
    static let streamBackupURL = directory.appendingPathComponent("before-stream.bin")

    static func saveStreamBackup(_ page: ConfigPage) {
        try? Data(page.bytes).write(to: streamBackupURL, options: .atomic)
    }

    static func loadStreamBackup() -> ConfigPage? {
        guard let data = try? Data(contentsOf: streamBackupURL) else { return nil }
        return ConfigPage([UInt8](data))
    }

    static func clearStreamBackup() { try? FileManager.default.removeItem(at: streamBackupURL) }

    static func saveBackupIfMissing(_ page: ConfigPage) {
        // A page stuck in per-key mode isn't anyone's "original" lighting.
        guard !page.isStreamMode, !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try? Data(page.bytes).write(to: backupURL, options: .atomic)
    }

    static func loadBackup() -> ConfigPage? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return ConfigPage([UInt8](data))
    }
}
