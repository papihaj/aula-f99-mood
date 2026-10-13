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
    var musicInput: MusicInput = .system
    /// "Electric", "Fire", … or "Custom".
    var musicPaletteName = MusicPalette.electric.name
    var customColors = [RGB(hex: 0xff00aa), RGB(hex: 0x00e5ff), RGB(hex: 0xffffff)]
    var reducedFlashing = false
    /// Adjust streamed colours for how LEDs look (gamma 2.2).
    var ledColorCorrection = true
    /// Change the light strip's colour to match moods and music themes.
    var stripFollowsColors = true
    /// In live effects and music, no key goes below about half brightness,
    /// so the letters stay readable (the F99's keycaps aren't see-through).
    var keepKeysLit = true
    /// The mood switched on whenever the app starts or the keyboard connects.
    var startupMoodID: UUID?
    /// Which set of built-in moods this file was last updated to.
    var moodsVersion = 1
    var musicHotkey: Hotkey? = Hotkey(keyCode: 2, modifiers: Hotkey.control | Hotkey.option) // ⌃⌥D

    init(moods: [Mood], macros: [Macro], activeMoodID: UUID?) {
        self.moods = moods
        self.macros = macros
        self.activeMoodID = activeMoodID
    }

    // Settings saved by an older version lack the music fields; keep the
    // defaults for those instead of throwing the whole file away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moods = try c.decode([Mood].self, forKey: .moods)
        macros = try c.decode([Macro].self, forKey: .macros)
        activeMoodID = try c.decodeIfPresent(UUID.self, forKey: .activeMoodID)
        musicStyle = try c.decodeIfPresent(MusicStyle.self, forKey: .musicStyle) ?? .spectrum
        musicInput = try c.decodeIfPresent(MusicInput.self, forKey: .musicInput) ?? .system
        musicPaletteName = try c.decodeIfPresent(String.self, forKey: .musicPaletteName) ?? MusicPalette.electric.name
        reducedFlashing = try c.decodeIfPresent(Bool.self, forKey: .reducedFlashing) ?? false
        ledColorCorrection = try c.decodeIfPresent(Bool.self, forKey: .ledColorCorrection) ?? true
        stripFollowsColors = try c.decodeIfPresent(Bool.self, forKey: .stripFollowsColors) ?? true
        moodsVersion = try c.decodeIfPresent(Int.self, forKey: .moodsVersion) ?? 1
        keepKeysLit = try c.decodeIfPresent(Bool.self, forKey: .keepKeysLit) ?? true
        startupMoodID = try c.decodeIfPresent(UUID.self, forKey: .startupMoodID)
        if let colors = try c.decodeIfPresent([RGB].self, forKey: .customColors), !colors.isEmpty {
            customColors = colors
        }
        if c.contains(.musicHotkey) {
            musicHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .musicHotkey)
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
        mood("Rainy Day",      "🌧️", 5,  /* Raindrops */     3, 1, 2, key: 19),
        mood("Starry Night",   "✨", 8,  /* Stars twinkle */ 2, 1, 6, key: 20),
        mood("Ocean Waves",    "🌊", 13, /* Sine wave */     3, 1, 5, key: 21),
        mood("Neon Night",     "💜", 11, /* Neon stream */   4, 2, 4, key: 23),
        mood("Rainbow Wheel",  "🌈", 6,  /* Rainbow wheel */ 4, 2, 7, key: 22),
        mood("Retro Arcade",   "🕹️", 10, /* Retro snake */   4, 3, 1, key: 26),
        mood("Blossom",        "🌸", 17, /* Blossoming */    3, 1, 7, key: 28),
        mood("Storm",          "🌀", 18, /* Rotating storm */4, 3, 7, key: 25),
        mood("Waterfall",      "💧", 16, /* Colorful waterfall */ 3, 2, 7),
        mood("Windmill",       "🎡", 15, /* Rotating windmill */  3, 2, 7),
        mood("Scanner",        "📡", 14, /* Retinue scanning */   3, 2, 0),
        mood("Sparkle Ripples","💫", 7,  /* Ripples shining */    3, 2, 7),
        mood("Typing Glow",    "⌨️", 12, /* Reaction */           4, 2, 5),
        mood("Lights out",     "🌙", 1,  /* Fixed on, off */      0, 0, 6, key: 29),
    ] + liveMoods

    /// Moods with live effects, in the style of other brands' popular ones.
    /// Colour 7 ("colourful") uses each effect's own palette.
    static let liveMoods: [Mood] = [
        //   name              emoji  effect                    bright speed colour
        live("Neon Cascade",   "🌠", .cascade,                 4, 1, 7),
        live("Matrix",         "🟩", .matrix,                  4, 2, 7),
        live("Campfire",       "🔥", .fire,                    4, 2, 7),
        live("Aurora",         "🌌", .aurora,                  3, 1, 7),
        live("Starlight",      "⭐️", .starlight,               3, 1, 7),
        live("Comet",          "☄️", .comet,                   4, 2, 7),
        live("Visor",          "🚨", .visor,                   4, 2, 7),
        live("Lava Lamp",      "🫠", .lavaLamp,                3, 1, 7),
        live("Plasma",         "🔮", .plasma,                  3, 2, 7),
        live("Heartbeat",      "❤️", .heartbeat,               3, 1, 7),
        live("Galaxy",         "🪐", .galaxy,                  3, 1, 7),
        live("Spiral",         "🍥", .spiral,                  3, 2, 7),
        live("Candlelight",    "🕯️", .candle,                  3, 1, 7),
        live("Typing Ripples", "💦", .typingRipples,           4, 2, 7),
        live("Typing Heatmap", "🌡️", .typingHeatmap,           4, 2, 7),
    ]

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
    /// 5: Neon Cascade, the start-up mood.
    static let moodsVersion = 5

    static let defaults: AppSettings = {
        let focus = builtInMoods[0]
        var s = AppSettings(
            moods: builtInMoods,
            macros: [
                Macro(name: "Email signature", hotkey: Hotkey(keyCode: 1, modifiers: Hotkey.control | Hotkey.option),
                      action: .typeText, value: "Best,\nYour Name", moodID: nil),
                Macro(name: "Focus music", hotkey: Hotkey(keyCode: 46, modifiers: Hotkey.control | Hotkey.option),
                      action: .open, value: "https://www.youtube.com/results?search_query=lofi+focus", moodID: focus.id),
            ],
            activeMoodID: nil)
        s.moodsVersion = moodsVersion
        s.startupMoodID = s.moods.first { $0.name == "Neon Cascade" }?.id
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
        var taken = Set(moods.compactMap(\.hotkey) + macros.compactMap(\.hotkey))
        // Add each missing built-in mood after the one before it in the
        // built-in list (so Gaming lands after Focus), else before Lights out.
        for (i, var mood) in Self.builtInMoods.enumerated() where !moods.contains(where: { $0.name == mood.name }) {
            if let key = mood.hotkey, taken.contains(key) { mood.hotkey = nil }
            if let key = mood.hotkey { taken.insert(key) }
            let previous = i > 0 ? moods.firstIndex { $0.name == Self.builtInMoods[i - 1].name } : nil
            let at = previous.map { $0 + 1 } ?? moods.firstIndex { $0.name == "Lights out" } ?? moods.count
            moods.insert(mood, at: at)
        }
        if let id = activeMoodID, !moods.contains(where: { $0.id == id }) { activeMoodID = nil }
        if moodsVersion < 5 { startupMoodID = moods.first { $0.name == "Neon Cascade" }?.id }
        moodsVersion = Self.moodsVersion
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
        guard let data = try? Data(contentsOf: settingsURL),
              var s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return .defaults }
        if s.moodsVersion < AppSettings.moodsVersion {
            s.upgradeMoods()
            save(s)
        }
        return s
    }

    static func save(_ s: AppSettings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(s).write(to: settingsURL, options: .atomic)
    }

    static func saveBackupIfMissing(_ page: ConfigPage) {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try? Data(page.bytes).write(to: backupURL, options: .atomic)
    }

    static func loadBackup() -> ConfigPage? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return ConfigPage([UInt8](data))
    }
}
