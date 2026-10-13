import Foundation

// Checks for the settings-page logic, run by build.sh. The sample page is a real
// one read off an AULA F75 (same firmware family as the F99), published by the
// AulaSofwareLinux project.

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

let f75: [UInt8] = [
    0x00, 0x03, 0x03, 0x01, 0x00, 0x00, 0x04, 0x04, 0x07, 0x00, 0x01, 0x20, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x01, 0x00, 0xff, 0x0a, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x09, 0x40,
    0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09,
    0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47, 0x09, 0x47,
    0x09, 0x37, 0x09, 0x37, 0x09, 0x37, 0x09, 0x37, 0x07, 0x47, 0x07, 0x47, 0x07, 0x44, 0x07,
    0x44, 0x07, 0x44, 0x07, 0x44, 0x07, 0x44, 0x07, 0x44, 0x07, 0x44, 0x04, 0x09, 0x04, 0x04,
    0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x5a, 0xa5,
]

// A real page parses; its live effect is "Fixed on" with slot 0 = 09 40.
let page = ConfigPage(f75)!
check(page.effect == 1, "effect byte")
check(page.current == .init(effect: 1, brightness: 9, speed: 4, color: 0), "current settings")
check(page.settings(for: 2) == .init(effect: 2, brightness: 9, speed: 4, color: 7), "slot 1")

// Busy / truncated reads are refused, so they can never be written back.
var corrupt = f75; corrupt[127] = 0
check(ConfigPage(corrupt) == nil, "missing end marker rejected")
check(ConfigPage(Array(f75.prefix(100))) == nil, "short read rejected")
check(ConfigPage([UInt8](repeating: 0, count: 128)) == nil, "all-zero page rejected")

// Pressing Fn+Tab on an F75 (colour red -> green on the live effect) moved
// exactly byte 0x3b from 40 to 41. Applying the same change here must too.
var green = page
try! green.apply(.init(effect: 1, brightness: 4, speed: 4, color: 1))
check(green.diff(page) == [0x3a, 0x3b], "brightness + colour only touch slot 0")
check(green.bytes[0x3b] == 0x41, "colour nibble")

// Switching effect touches only the effect byte and that effect's slot.
var breathing = page
try! breathing.apply(.init(effect: 2, brightness: 2, speed: 1, color: 5))
check(breathing.diff(page) == [0x0a, 0x3c, 0x3d], "effect change footprint: \(breathing.diff(page))")
check(breathing.bytes[0x3d] == 0x15, "speed/colour packing")
check(breathing.bytes[126...] == [0x5a, 0xa5], "end marker kept")

// Out-of-range values are refused rather than written.
for bad in [ConfigPage.Lighting(effect: 0, brightness: 1, speed: 1, color: 1),
            .init(effect: 19, brightness: 1, speed: 1, color: 1),
            .init(effect: 21, brightness: 1, speed: 1, color: 1),
            .init(effect: 1, brightness: 5, speed: 1, color: 1),
            .init(effect: 1, brightness: 1, speed: 5, color: 1),
            .init(effect: 1, brightness: 1, speed: 1, color: 8)] {
    var p = page
    do { try p.apply(bad); check(false, "accepted \(bad)") } catch {}
    check(p == page, "page untouched after refusal")
}

// Every F99 effect's slot lies before the end marker.
for e in F99.effects {
    var p = page
    try! p.apply(.init(effect: e.id, brightness: 1, speed: 1, color: 1))
    check(p.diff(page).allSatisfy { $0 < 126 }, "effect \(e.id) stays clear of the marker")
}

// Restoring copies only the lighting bytes.
var other = breathing
var restored = page
restored.copyLighting(from: other)
check(restored == breathing, "restore lighting")
other = ConfigPage({ var b = f75; b[0x18] = 0x14; b[0x0a] = 3; return b }())!
restored = page
restored.copyLighting(from: other)
check(restored.bytes[0x18] == 0x0a && restored.effect == 3, "restore leaves sleep timer alone")

// Music mode: switching in sets exactly the three per-key bytes, and the
// "restore" afterwards undoes all of them.
var streaming = page
streaming.setStreamMode()
check(streaming.diff(page) == [0x09, 0x0a, 0x3b], "stream mode footprint: \(streaming.diff(page))")
check(streaming.isStreamMode && !page.isStreamMode, "stream mode detected")
var back = streaming
back.copyLighting(from: page)
check(back == page, "restore after music")

// A mood applied while still in stream mode clears the stream flag.
var mood = streaming
try! mood.apply(.init(effect: 2, brightness: 3, speed: 2, color: 1))
check(!mood.isStreamMode && mood.bytes[0x09] == 0, "mood leaves stream mode")

// Every F99 key has its own LED slot inside one streamed frame.
let leds = F99.keys.map(\.led)
check(F99.keys.count == 99, "99 keys")
check(Set(leds).count == leds.count, "no shared LEDs")
check(leds.allSatisfy { $0 >= 0 && $0 < 126 }, "LEDs fit a 126-slot frame")
check(F99.keys.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "positions normalised")

// Renderer: right size, and silence keeps the board dim but not black.
let renderer = MusicRenderer()
let silent = MusicSnapshot(bands: Array(repeating: 0, count: 16), level: 0, bass: 0, beat: false)
for style in MusicStyle.allCases {
    renderer.style = style
    let frame = renderer.render(silent)
    check(frame.count == 378, "\(style) frame size")
    check(frame.max()! < 80, "\(style) is dim when silent")
}
// Spectrum: loud bass lights the left side higher than the right.
renderer.style = .spectrum
var bassy = silent
bassy.bands = (0..<16).map { $0 < 4 ? 1 : 0 }
let frame = renderer.render(bassy)
func brightness(_ name: String) -> Int {
    let led = F99.keys.first { $0.name == name }!.led
    return Int(frame[led * 3]) + Int(frame[led * 3 + 1]) + Int(frame[led * 3 + 2])
}
check(brightness("Q") > brightness("Num7"), "bass lights the left")

// Analyzer: a 60 Hz tone reads as bass, and pulsed bass registers beats.
let analyzer = MusicAnalyzer()
let tone = (0..<2048).map { Float(sin(2 * Double.pi * 60 * Double($0) / 48_000)) * 0.5 }
var m = analyzer.analyze(tone, sampleRate: 48_000)
for _ in 0..<5 { m = analyzer.analyze(tone, sampleRate: 48_000) }
check(m.bands[1] > 0.8 && m.bands[14] < 0.3, "60 Hz is bass: \(m.bands)")
let quiet = [Float](repeating: 0.001, count: 2048)
let pulse = MusicAnalyzer()
var beats = 0
for i in 0..<60 {
    if i % 10 == 0 { usleep(250_000) } // beats can't be closer than 0.22 s
    if pulse.analyze(i % 10 == 0 ? tone : quiet, sampleRate: 48_000).beat { beats += 1 }
}
check(beats >= 4, "pulsed bass gives beats (\(beats))")

// Palettes: ends land on the first and last colours, wrapping loops back.
let fire = MusicPalette.presets.first { $0.name == "Fire" }!
check(fire.sample(0, wrap: false) == fire.colors.first!, "palette start")
check(fire.sample(1, wrap: false) == fire.colors.last!, "palette end")
check(fire.sample(1, wrap: true) == fire.colors.first!, "palette wraps")
// Every style painted with Fire stays red/orange/yellow: no blue.
let fiery = MusicRenderer()
fiery.palette = fire
var loud = MusicSnapshot(bands: Array(repeating: 1, count: 16), level: 1, bass: 1, beat: true)
for style in [MusicStyle.spectrum, .ripples] {
    fiery.style = style
    let f = fiery.render(loud)
    check(stride(from: 2, to: f.count, by: 3).allSatisfy { f[$0] < 20 }, "\(style) with Fire has no blue")
}
loud.beat = false

// Flash safety: even with a strong hit every frame during a drop, white
// strikes stay at three a second or fewer, and none with Reduced flashing.
for reduced in [false, true] {
    let r = MusicRenderer()
    r.style = .pulse
    r.reducedFlashing = reduced
    let hit = MusicSnapshot(bands: Array(repeating: 1, count: 16), level: 1, bass: 1, beat: true,
                            strength: 1, intensity: 1)
    let start = Date()
    var lastMean = -1.0, biggestJump = 0.0
    for frame in 0..<200 { // 10 seconds at 20 frames a second
        let f = r.render(hit, now: start.addingTimeInterval(Double(frame) * 0.05))
        let mean = Double(f.reduce(0) { $0 + Int($1) }) / Double(f.count) / 255
        if lastMean >= 0 { biggestJump = max(biggestJump, abs(mean - lastMean)) }
        lastMean = mean
        check(f.max()! <= 205, "brightness capped at 80%")
    }
    if reduced {
        check(r.bigFlashCount == 0, "no white strikes with Reduced flashing")
        check(biggestJump <= 0.041, "gentle changes with Reduced flashing: \(biggestJump)")
    } else {
        check(r.bigFlashCount > 0 && r.bigFlashCount <= 30, "at most 3 white strikes a second: \(r.bigFlashCount) in 10 s")
        check(biggestJump <= 0.121, "board brightness can't jump too far in one frame: \(biggestJump)")
    }
}

// No white strikes in a normal (non-drop) section.
let calm = MusicRenderer()
calm.style = .pulse
for frame in 0..<100 {
    _ = calm.render(MusicSnapshot(bands: Array(repeating: 0.6, count: 16), level: 0.6, bass: 0.6, beat: frame % 10 == 0,
                                  strength: 1, intensity: 0.5), now: Date().addingTimeInterval(Double(frame) * 0.05))
}
check(calm.bigFlashCount == 0, "white strikes are saved for drops")

// Silence fades to a dim glow, in every style.
for style in MusicStyle.allCases {
    let r = MusicRenderer()
    r.style = style
    var f: [UInt8] = []
    for _ in 0..<40 { f = r.render(MusicSnapshot(bands: Array(repeating: 0, count: 16), level: 0, bass: 0, beat: false, silent: true)) }
    check(f.max()! > 0 && f.max()! < 40, "\(style) idles dim but not black: \(f.max()!)")
}

// Oklab blends: the ends are exact and a blend lands between them.
let blue = RGB(0, 0, 1), white = RGB(1, 1, 1)
check(blue.mixed(with: white, 0) == blue && blue.mixed(with: white, 1) == white, "blend ends")
let mid = blue.mixed(with: white, 0.5)
check(mid.luminance > blue.luminance && mid.luminance < white.luminance, "blend in between")
check(mid.b >= mid.r, "blue-to-white doesn't drift purple: \(mid)")

// Tempo: kicks every 0.5 s, analysed every 12 ms like the app, lock to 120 BPM.
let tempo = MusicAnalyzer(hop: 0.012)
let kick = (0..<2048).map { Float(sin(2 * Double.pi * 60 * Double($0) / 48_000)) * 0.6 }
let hush = (0..<2048).map { Float(sin(2 * Double.pi * 3000 * Double($0) / 48_000)) * 0.003 }
var last = MusicSnapshot(bands: [], level: 0, bass: 0, beat: false)
var tempoBeats = 0
let callsPerKick = Int((0.5 / 0.012).rounded())
for call in 0..<(callsPerKick * 20) { // 10 seconds
    // A kick lasts ~0.1 s.
    last = tempo.analyze(call % callsPerKick < 8 ? kick : hush, sampleRate: 48_000)
    if last.beat { tempoBeats += 1 }
}
check(tempoBeats >= 16 && tempoBeats <= 22, "one beat per kick: \(tempoBeats)")
check(abs(last.bpm - 120) < 6, "tempo locks to 120 BPM: \(last.bpm)")

// Moods while dancing: a coloured mood gives shades of its colour, a
// colourful one gives the rainbow.
let calmMood = AppSettings.defaults.moods.first { $0.name == "Ocean Waves" }!   // cyan sine wave
let calmPalette = MusicPalette.forMood(calmMood)
check(calmPalette.colors.allSatisfy { $0.r < 0.75 && $0.b > 0.3 && $0.b >= $0.r }, "Calm dances in cyan shades: \(calmPalette.colors)")
let partyMood = AppSettings.defaults.moods.first { $0.name == "Rainbow Wheel" }!  // colourful
check(MusicPalette.forMood(partyMood).colors.count == 6, "Rainbow Wheel dances in rainbow")

// A dim mood dims the music.
let dim = MusicRenderer(), full = MusicRenderer()
dim.brightnessScale = 0.25
let busy = MusicSnapshot(bands: Array(repeating: 0.9, count: 16), level: 0.9, bass: 0.9, beat: false)
var dimFrame: [UInt8] = [], fullFrame: [UInt8] = []
for i in 0..<30 {
    let t = Date().addingTimeInterval(Double(i) * 0.05)
    dimFrame = dim.render(busy, now: t); fullFrame = full.render(busy, now: t)
}
check(Int(dimFrame.max()!) * 3 < Int(fullFrame.max()!), "dim mood dims the music")

// Strip colour: only byte 0x1d changes, the mode is left alone, and only the
// fixed colours are accepted.
var stripPage = page
try! stripPage.setStripColor(5)
check(stripPage.diff(page) == [0x1d], "strip colour touches only 0x1d")
check((try? stripPage.setStripColor(7)) == nil && (try? stripPage.setStripColor(-1)) == nil, "strip colour range")
check((try? stripPage.setStripByte(0x20, 1)) == nil, "only strip bytes can be set")
// Theme to strip colour: the nearest of the keyboard's colours.
check(MusicPalette.electric.stripColor == 2, "Electric strip is blue")
check(MusicPalette.presets.first { $0.name == "Fire" }!.stripColor == 0, "Fire strip is red")
check(F99.nearestColor(RGB(0, 0.9, 0.95)) == 5, "cyan-ish is cyan")

// Built-in moods: every effect is real, values in range, no two share a
// shortcut, and each uses an effect the editor offers.
let built = AppSettings.builtInMoods
check(built.allSatisfy { F99.effect($0.lighting.effect) != nil && F99.brightnessLevels.contains($0.lighting.brightness)
    && F99.speedLevels.contains($0.lighting.speed) && (0...F99.colorful).contains($0.lighting.color) }, "moods valid")
let keys = built.compactMap(\.hotkey)
check(Set(keys).count == keys.count, "mood shortcuts unique")
check(built.allSatisfy { $0.live.map(LiveEffect.offered.contains) ?? F99.offeredEffects.contains($0.lighting.effect) },
      "moods use offered effects")
// Each grid fits in two rows of four, counting the "New mood" tile.
check(built.filter { $0.live == nil }.count <= 7 && built.filter { $0.live != nil }.count <= 7, "short mood grids")

// Upgrading saved moods: unedited old ones go, edited and custom ones stay,
// new ones arrive, and nothing ends up with a clashing shortcut.
var old = AppSettings(moods: [
    AppSettings.mood("Focus", "🎯", 1, 2, 0, 6, key: 18),
    AppSettings.mood("Calm", "🌊", 2, 2, 1, 5, key: 19),          // unedited: removed
    AppSettings.mood("Cozy", "🕯️", 2, 3, 0, 3, key: 20),          // edited: kept
    AppSettings.mood("Mine", "🧪", 4, 2, 2, 1, key: 21),          // custom: kept
    AppSettings.mood("Lights out", "🌙", 1, 0, 0, 6, key: 29),
], macros: [], activeMoodID: nil)
old.upgradeMoods()
let names = old.moods.map(\.name)
check(!names.contains("Calm") && names.contains("Cozy") && names.contains("Mine"), "upgrade keeps your moods: \(names)")
check(names.contains("Ocean Waves") && names.firstIndex(of: "Ocean Waves")! < names.firstIndex(of: "Lights out")!,
      "upgrade adds new keyboard moods before Lights out")
check(names.contains("Matrix") && names.contains("Typing Heatmap"), "upgrade adds live moods")
let upgradedKeys = old.moods.compactMap(\.hotkey)
check(Set(upgradedKeys).count == upgradedKeys.count, "no clashing shortcuts after upgrade")
check(names.filter { $0 == "Focus" }.count == 1, "no duplicates")

// Settings already on the effect-based set get Gaming back, right after Focus,
// with its shortcut unless something already uses ⌃⌥G.
var v2 = AppSettings(moods: AppSettings.builtInMoods.filter { $0.name != "Gaming" }, macros: [], activeMoodID: nil)
v2.moodsVersion = 2
v2.upgradeMoods()
check(v2.moods.map(\.name).prefix(2) == ["Focus", "Gaming"], "Gaming back after Focus: \(v2.moods.map(\.name))")
check(v2.moods.first { $0.name == "Gaming" }?.lighting == .init(effect: 12, brightness: 4, speed: 2, color: 0), "Gaming is red Reaction")
check(v2.moods.first { $0.name == "Gaming" }?.hotkey?.display == "⌃⌥G", "Gaming shortcut")

// Live effects: every one renders a full frame within the brightness cap,
// moves over time, and never swings the whole board too far in one frame.
for effect in LiveEffect.allCases {
    let r = LiveRenderer()
    r.effect = effect
    r.palette = effect.palette
    let start = Date()
    var frames: [[UInt8]] = []
    var biggest = 0.0, lastMean = -1.0
    for i in 0..<60 {
        if effect.reactsToTyping && i % 5 == 0 {
            r.keyPressed(led: F99.keys.randomElement()!.led, at: start.addingTimeInterval(Double(i) * 0.05))
        }
        let f = r.render(now: start.addingTimeInterval(Double(i) * 0.05))
        frames.append(f)
        let mean = Double(f.reduce(0) { $0 + Int($1) }) / Double(f.count) / 255
        if lastMean >= 0 { biggest = max(biggest, abs(mean - lastMean)) }
        lastMean = mean
    }
    check(frames.allSatisfy { $0.count == 378 }, "\(effect) frame size")
    check(frames.allSatisfy { $0.max()! <= 205 }, "\(effect) brightness cap")
    // Painted keys hold still and start with nothing painted.
    if effect != .painted { check(Set(frames.map { $0 }).count > 10, "\(effect) moves") }
    check(biggest <= 0.121, "\(effect) no big board swings: \(biggest)")
    if effect != .painted { check(frames.last!.contains { $0 > 20 }, "\(effect) visible") }
}

// Heartbeat stays at or under three pulses a second even at top speed.
let heart = LiveRenderer()
heart.effect = .heartbeat; heart.palette = LiveEffect.heartbeat.palette; heart.speed = 4
var peaks = 0, wasHigh = false
let hStart = Date()
for i in 0..<200 { // 10 seconds
    let f = heart.render(now: hStart.addingTimeInterval(Double(i) * 0.05))
    let mean = Double(f.reduce(0) { $0 + Int($1) }) / Double(f.count)
    let high = mean > 40
    if high && !wasHigh { peaks += 1 }
    wasHigh = high
}
check(peaks <= 30, "heartbeat ≤ 3 pulses a second: \(peaks) in 10 s")

// Typing: pressing a key lights it; macOS key codes map to the right keys.
let typing = LiveRenderer()
typing.effect = .typingRipples; typing.palette = LiveEffect.typingRipples.palette
let qLED = F99.keys.first { $0.name == "Q" }!.led
let tNow = Date()
_ = typing.render(now: tNow)
typing.keyPressed(led: qLED, at: tNow)
let lit = typing.render(now: tNow.addingTimeInterval(0.05))
check(Int(lit[qLED * 3]) + Int(lit[qLED * 3 + 1]) + Int(lit[qLED * 3 + 2]) > 100, "pressed key lights up")
check(KeyMap.led(forKeyCode: 12) == qLED, "key code 12 is Q")
check(KeyMap.led(forKeyCode: 49) == F99.keys.first { $0.name == "Space" }!.led, "space")
check(KeyMap.led(forKeyCode: 42) == F99.keys.first { $0.name == "\\" }!.led, "backslash")
check(KeyMap.led(forKeyCode: 76) == 112, "keypad Enter")

// Neon Cascade: every key bright at all times; a pressed key flashes towards
// the palette's lightest colour, with a halo around it.
let cascade = LiveRenderer()
cascade.effect = .cascade; cascade.palette = LiveEffect.cascade.palette; cascade.pressGlow = true
let cStart = Date()
var dimmest = 255
for i in 0..<100 {
    let f = cascade.render(now: cStart.addingTimeInterval(Double(i) * 0.05))
    for k in F99.keys { dimmest = min(dimmest, Int(f[k.led * 3...k.led * 3 + 2].max()!)) }
}
check(dimmest > 120, "every key bright in Neon Cascade: dimmest \(dimmest)")
let gLED = F99.keys.first { $0.name == "G" }!.led
let hLED = F99.keys.first { $0.name == "H" }!.led
let pressAt = cStart.addingTimeInterval(5.05)
let before = cascade.render(now: pressAt)
cascade.keyPressed(led: gLED, at: pressAt)
let after = cascade.render(now: pressAt.addingTimeInterval(0.05))
func whiteness(_ f: [UInt8], _ led: Int) -> Int { Int(f[led * 3...led * 3 + 2].min()!) }
check(whiteness(after, gLED) > whiteness(before, gLED) + 60, "pressed key lights up towards white")
check(whiteness(after, hLED) > whiteness(before, hLED), "halo around the pressed key")
check(LiveEffect.cascade.reactsToTyping && LiveEffect.cascade.pressGlow, "cascade listens for key presses")

// "Keep every key lit": a dark effect (Matrix) never lets a key go dark.
let floored = LiveRenderer()
floored.effect = .matrix; floored.palette = LiveEffect.matrix.palette; floored.minimumBrightness = 0.5
var litDimmest = 255
for i in 0..<60 {
    let f = floored.render(now: Date().addingTimeInterval(Double(i) * 0.05))
    for k in F99.keys { litDimmest = min(litDimmest, Int(f[k.led * 3...k.led * 3 + 2].max()!)) }
}
check(litDimmest >= 40, "keys stay lit with the floor on: \(litDimmest)")

// A new user gets no one else's choices: no start-up mood, no macros.
check(AppSettings.defaults.startupMoodID == nil && AppSettings.defaults.macros.isEmpty, "clean defaults")

// Settings from older and newer versions load without losing anything.
let oldJSON = """
{"moods":[{"id":"E13319A0-203E-4762-9B11-A39A5B513DD4","name":"Mine","emoji":"🌠","lighting":{"effect":1,"brightness":4,"speed":1,"color":7},"live":"Neon Cascade"},
          {"name":"Future","emoji":"🚀","lighting":{"effect":1,"brightness":4,"speed":1,"color":7},"live":"Some Effect From Version 9"}],
 "macros":[], "musicStyle":"Laser Show", "keepKeysLit":true, "moodsVersion":5}
"""
let saved = try! JSONDecoder().decode(AppSettings.self, from: Data(oldJSON.utf8))
check(saved.moods.count == 2 && saved.moods[0].live == .cascade && saved.moods[0].apps.isEmpty, "old moods load")
check(saved.moods[1].live == nil, "unknown live effect from a newer version is dropped, not fatal")
check(saved.musicStyle == .spectrum && saved.keepKeysLit && saved.welcomeDone, "unknown style falls back; existing user skips welcome")
check(saved.pressGlow == .typingEffects && saved.keysLitLevel == 0.5 && saved.darkWhenLocked, "new options get defaults")
let roundTrip = try! JSONDecoder().decode(AppSettings.self, from: Storage.encode(saved))
check(roundTrip.moods.map(\.id) == saved.moods.map(\.id), "settings round-trip")
check(!AppSettings.defaults.welcomeDone && !AppSettings.defaults.keepKeysLit, "new users see the welcome screen")

// Import: new ids, no shortcuts, names kept apart.
var shared = AppSettings.defaults
let focus = shared.moods.first { $0.name == "Focus" }!
let added = shared.importMoods([focus, Mood(name: "  ", emoji: "x", lighting: focus.lighting, hotkey: nil)])
check(added.count == 2 && added[0].name == "Focus (2)" && added[0].id != focus.id && added[0].hotkey == nil, "import renames and strips shortcuts")
check(added[1].name == "Imported mood", "blank names get one")
let file = try! JSONDecoder().decode(MoodFile.self, from: Storage.encode(MoodFile(moods: [focus])))
check(file.moods.first?.name == "Focus", "mood file round-trip")

// Delete clears everything pointing at the mood.
var del = AppSettings.defaults
let gone = del.moods[1].id
del.activeMoodID = gone; del.startupMoodID = gone
del.macros = [Macro(name: "m", hotkey: nil, action: .typeText, value: "hi", moodID: gone)]
del.deleteMood(gone)
check(del.activeMoodID == nil && del.startupMoodID == nil && del.macros[0].moodID == nil, "delete clears references")
check(del.addMissingBuiltInMoods() == 1 && del.moods.contains { $0.name == AppSettings.defaults.moods[1].name }, "restore built-in moods")

// Shortcuts: duplicates are found, and a new one is free.
var clash = AppSettings.defaults
check(clash.duplicateHotkeys.isEmpty, "built-in shortcuts don't clash")
let free = clash.freeHotkey
check(!clash.moods.contains { $0.hotkey == free } && clash.musicHotkey != free, "free shortcut is free")
clash.moods[2].hotkey = clash.moods[0].hotkey
check(clash.duplicateHotkeys.contains(clash.moods[0].hotkey!), "duplicate shortcut reported")

// Press glow on any effect, in any colour, with or without a halo.
let glow = LiveRenderer()
glow.effect = .aurora; glow.palette = LiveEffect.aurora.palette
glow.pressGlow = true; glow.pressColor = RGB(1, 0, 0); glow.haloSize = 0
let gAt = Date()
_ = glow.render(now: gAt)
glow.keyPressed(led: gLED, at: gAt)
let gFrame = glow.render(now: gAt.addingTimeInterval(0.05))
check(Int(gFrame[gLED * 3]) > Int(gFrame[gLED * 3 + 2]) + 40, "custom press colour (red)")
let gNext = glow.render(now: gAt.addingTimeInterval(0.1))
let noHalo = LiveRenderer(); noHalo.effect = .aurora; noHalo.palette = LiveEffect.aurora.palette
_ = noHalo.render(now: gAt); _ = noHalo.render(now: gAt.addingTimeInterval(0.05))
let hBase = noHalo.render(now: gAt.addingTimeInterval(0.1))
check(abs(Int(gNext[hLED * 3]) - Int(hBase[hLED * 3])) < 3, "halo size 0: neighbours untouched")
check(KeyMap.led(forKeyCode: 56) == F99.keys.first { $0.name == "LShift" }!.led, "modifiers light up too")

// Schedule: an entry is due only at its minute and on its days; "current"
// is the latest one that has started, carrying over from earlier days.
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
let moodA = UUID(), moodB = UUID()
let morning = ScheduleEntry(hour: 7, minute: 30, days: Set(2...6), moodID: moodA) // weekdays
let night = ScheduleEntry(hour: 22, minute: 0, moodID: moodB)
let plan = [morning, night]
// 2026-10-13 is a Tuesday.
check(Schedule.due(plan, at: at(2026, 10, 13, 7, 30), calendar: cal)?.moodID == moodA, "due at its minute")
check(Schedule.due(plan, at: at(2026, 10, 13, 7, 31), calendar: cal) == nil, "not due a minute later")
check(Schedule.due(plan, at: at(2026, 10, 18, 7, 30), calendar: cal) == nil, "weekday entry skips Sunday")
check(Schedule.current(plan, at: at(2026, 10, 13, 12, 0), calendar: cal)?.moodID == moodA, "current: morning until night")
check(Schedule.current(plan, at: at(2026, 10, 13, 23, 0), calendar: cal)?.moodID == moodB, "current: night after 22:00")
check(Schedule.current(plan, at: at(2026, 10, 13, 6, 0), calendar: cal)?.moodID == moodB, "current: carries over from last night")
var off = night; off.enabled = false
check(Schedule.current([off], at: at(2026, 10, 13, 23, 0), calendar: cal) == nil, "switched-off entry ignored")
check(ScheduleEntry(hour: 9, minute: 0, days: Set(2...6), moodID: nil).daysText == "Weekdays", "days text")

// New settings: an old file gets the defaults, and they fullTurn-trip.
let plain = try! JSONDecoder().decode(AppSettings.self, from: #"{"moods":[]}"#.data(using: .utf8)!)
check(plain.schedule.isEmpty && !plain.calendarAlerts && !plain.nowPlayingBar && !plain.keySounds, "extras off by default")
var extras = AppSettings.defaults
extras.schedule = plan; extras.keySounds = true; extras.keySound = .clicky; extras.alertFlashes = 4
let extrasBack = try! JSONDecoder().decode(AppSettings.self, from: Storage.encode(extras))
check(extrasBack.schedule == plan && extrasBack.keySound == .clicky && extrasBack.alertFlashes == 4, "extras fullTurn-trip")
let wild = try! JSONDecoder().decode(AppSettings.self, from: #"{"moods":[],"alertFlashes":99,"keySound":"Kazoo","keySoundVolume":7}"#.data(using: .utf8)!)
check(wild.alertFlashes == 6 && wild.keySound == .tactile && wild.keySoundVolume == 1, "odd values clamped or defaulted")

// Painted moods: the built-in WASD paints W and keeps its colours through
// a save; the renderer shows painted keys and the base colour.
let wasd = AppSettings.defaults.moods.first { $0.name == "WASD" }!
let wLED = F99.keys.first { $0.name == "W" }!.led
check(wasd.live == .painted && wasd.paintByLED[wLED] != nil, "WASD is painted")
let wasdBack = try! JSONDecoder().decode(Mood.self, from: Storage.encode(wasd))
check(wasdBack.paint == wasd.paint && wasdBack.paintBase == wasd.paintBase, "paint fullTurn-trips")
let painter = LiveRenderer()
painter.effect = .painted; painter.paint = [wLED: RGB(0, 0, 1)]; painter.paintBase = nil
let pFrame = painter.render()
let qKey = F99.keys.first { $0.name == "Q" }!.led
check(pFrame[wLED * 3 + 2] > 150 && pFrame[wLED * 3] < 10, "painted key is blue")
check(pFrame[qKey * 3] == 0 && pFrame[qKey * 3 + 2] == 0, "unpainted key is off")
check(AppSettings.moodsVersion == 8, "moods version bumped")
var oldUser = AppSettings.defaults
oldUser.moods.removeAll { $0.name == "WASD" }; oldUser.moodsVersion = 5
oldUser.upgradeMoods()
check(oldUser.moods.contains { $0.name == "WASD" }, "upgrade adds WASD")

// Overlays: the progress bar fills the column from the bottom; a flash
// covers the board and then clears itself.
var bar = Overlays(); bar.progress = 0.5; bar.progressColor = RGB(1, 1, 1)
let blank = [UInt8](repeating: 0, count: Keyboard.streamSlots * 3)
let barFrame = bar.apply(blank)
let col = Overlays.column
check(col.count == 6, "six keys in the column")
check(barFrame[col[0] * 3] > 150 && barFrame[col[2] * 3] > 150, "bottom half lit at 50%")
check(barFrame[col[5] * 3] < 40 && barFrame[col[5] * 3] > 0, "top key is a faint track")
var fl = Overlays()
let fStart = Date()
fl.flash = .init(start: fStart, color: RGB(1, 0.7, 0), count: 2)
let flashMid = fl.apply(blank, now: fStart.addingTimeInterval(Overlays.Flash.period / 2))
check(flashMid[0] > 150, "flash lights the board")
_ = fl.apply(blank, now: fStart.addingTimeInterval(5))
check(fl.flash == nil, "flash ends by itself")

// Hue rotation keeps a colour's lightness and comes extrasBack after a full turn.
let teal = RGB(hex: 0x00b3a4)
let fullTurn = teal.hueRotated(1)
check(abs(fullTurn.r - teal.r) < 0.01 && abs(fullTurn.g - teal.g) < 0.01 && abs(fullTurn.b - teal.b) < 0.01, "full turn is the same")
check(abs(teal.hueRotated(0.5).oklab.0 - teal.oklab.0) < 0.02, "same lightness")

// Look-alike built-in moods are retired on upgrade, unless they're the
// start-up mood or you changed their effect; Electric Ripples arrives.
var v6 = AppSettings.defaults
v6.moodsVersion = 6
var galaxy = AppSettings.mood("Galaxy", "", 1, 3, 1, 7); galaxy.live = .galaxy
var myBlossom = AppSettings.mood("Blossom", "", 2, 3, 1, 4) // effect changed: yours now
var startCandle = AppSettings.mood("Candlelight", "", 1, 3, 1, 7); startCandle.live = .candle
v6.moods += [galaxy, myBlossom, startCandle]
v6.moods.removeAll { $0.name == "Electric Ripples" }
v6.startupMoodID = startCandle.id
v6.macros = [Macro(name: "m", hotkey: nil, action: .typeText, value: "x", moodID: galaxy.id)]
v6.upgradeMoods()
let v6names = v6.moods.map(\.name)
check(!v6names.contains("Galaxy") && v6.macros[0].moodID == nil, "Galaxy retired, references cleared")
check(v6names.contains("Blossom") && v6names.contains("Candlelight"), "edited and start-up moods kept")
check(v6.moods.first { $0.name == "Electric Ripples" }?.paletteName == "Electric", "Electric Ripples added in Electric")
check(!AppSettings.defaults.moods.contains { m in AppSettings.retiredMoods.contains { $0.name == m.name } }, "new users don't get retired moods")

// Version 8 retires more look-alikes from an unedited version 7 list, but
// keeps one you edited and your start-up mood.
var v7 = AppSettings.defaults
v7.moodsVersion = 7
let scanner = AppSettings.mood("Scanner", "", 14, 3, 2, 0)
let myStorm = AppSettings.mood("Storm", "", 2, 4, 3, 7) // effect changed: yours now
var comet = AppSettings.mood("Comet", "", 1, 4, 2, 7); comet.live = .comet
v7.moods += [scanner, myStorm, comet]
v7.startupMoodID = comet.id
v7.activeMoodID = scanner.id
v7.upgradeMoods()
let v7names = v7.moods.map(\.name)
check(!v7names.contains("Scanner") && v7.activeMoodID == nil, "Scanner retired, active mood cleared")
check(v7names.contains("Storm") && v7names.contains("Comet"), "edited and start-up moods kept in v8")

if failures == 0 { print("All tests passed.") } else { print("\(failures) test(s) failed."); exit(1) }
