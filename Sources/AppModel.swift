import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case searching
        case connected(String)
        case readOnly(String)
        case unavailable(String)
    }

    @Published var settings: AppSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    /// Typing effects are on but macOS hasn't allowed Accessibility yet.
    @Published var needsAccessibility = false
    /// The screen is locked or asleep, so the lights are off.
    @Published var darkened = false
    /// No typing or mouse for a while, so live effects and music are dimmed.
    @Published var idleDimmed = false
    @Published private(set) var status: Status = .searching
    @Published private(set) var busy = false
    @Published var musicOn = false
    /// The colours music mode is painting right now (R, G, B per LED slot),
    /// for the on-screen keyboard. Nil when music is off.
    /// Not @Published on purpose: it changes 20 times a second, and
    /// publishing it would redraw every view in the app each time. The
    /// on-screen keyboard redraws by itself and reads it then.
    var streamFrame: [UInt8]?
    /// The music level and tempo, watched only by the meter.
    let meter = MusicMeter()
    /// True when the app has heard nothing at all for a while: either nothing
    /// is playing, or macOS hasn't allowed audio recording.
    @Published var hearingNothing = false
    /// Music mode has heard exact silence for a few seconds.
    var silentNow = false
    /// A mood picked while music plays: the music takes its colours.
    @Published var musicMood: Mood?
    /// The live effect mood running now, if any.
    @Published var liveMood: Mood?
    /// Whether the running live effect is going to the keyboard (or only the
    /// on-screen preview, when it started without one).
    var liveSessionToKeyboard = false
    nonisolated(unsafe) let liveRenderer = LiveRenderer()
    var liveTimer: DispatchSourceTimer?
    var keyMonitors: [Any] = []
    /// The last mood picked, shown on screen even without the keyboard.
    @Published private(set) var previewLighting: ConfigPage.Lighting?
    /// Keyboard jobs queued or running; `busy` while any are.
    var pending = 0 { didSet { busy = pending > 0 } }
    @Published var lastError: String?
    @Published var page: ConfigPage?
    @Published private(set) var refusedHotkeys: [Hotkey] = []
    @Published private(set) var identity = ""

    /// All HID traffic happens on this queue, one transfer at a time.
    let queue = DispatchQueue(label: "f99.hid")
    /// Only touched on `queue`.
    nonisolated(unsafe) var keyboard: Keyboard?
    private var timer: Timer?
    private var wasPresent = false

    // Music mode. The analyzer, renderer and saved page are only touched on `queue`.
    var audio: AudioSource?
    nonisolated(unsafe) let samples = SampleBuffer() // thread-safe
    /// Beat detection runs 40 times a second on its own queue so beats land
    /// within 25 ms; the lights still update 20 times a second.
    let analysisQueue = DispatchQueue(label: "f99.analysis", qos: .userInitiated)
    nonisolated static let analysisHop = 0.025
    nonisolated(unsafe) var analyzer = MusicAnalyzer(hop: Float(AppModel.analysisHop))
    var analysisTimer: DispatchSourceTimer?
    /// The analysis since the last light frame, with any beat in between kept.
    /// Guarded by `snapshotLock`.
    nonisolated(unsafe) var pendingSnapshot: MusicSnapshot?
    let snapshotLock = NSLock()
    /// Seconds of exact digital silence, to spot missing audio permission.
    nonisolated(unsafe) var silentSeconds = 0.0
    nonisolated(unsafe) var colorCorrection = true
    nonisolated(unsafe) let renderer = MusicRenderer()
    nonisolated(unsafe) var pageBeforeMusic: ConfigPage?
    nonisolated(unsafe) var streamFailures = 0
    var frameTimer: DispatchSourceTimer?
    /// Drawn on top of streamed frames. Only touched on `queue`.
    nonisolated(unsafe) var overlays = Overlays()
    let nowPlaying = NowPlayingWatcher()
    let keySounds = KeySoundPlayer()
    let mail = MailWatcher()
    let badges = BadgeWatcher()
    /// When Messages or Slack last blinked the strip.
    private var lastChatBlink: Date?
    /// An alert waiting on the light strip ("Standup at 10:00", "New mail").
    @Published var stripAlert: String?
    @Published private(set) var mailNotAllowed = false
    var stripAlertUntil: Date?
    var stripAlertIsMail = false
    var stripBeforeAlert: ConfigPage.Strip?
    /// A mood the editor should open (set by "New mood").
    @Published var editMoodRequest: UUID?
    /// The pane showing in the main window's sidebar.
    @Published var pane: EditorView.Pane = .home
    /// The page the first-run tour is showing, if it's running.
    @Published var tourStep: Int? {
        didSet { if let step = tourStep { pane = Tour.stops[step].pane } }
    }
    /// Why the typing sound can't play, if it can't.
    @Published var keySoundError: String?
    /// A song is playing in Spotify or Music (for the now-playing bar).
    @Published private(set) var songPlaying = false
    @Published private(set) var nowPlayingNotAllowed = false
    /// Moods as they were before "Remix" changed them this session.
    @Published var remixOriginals: [UUID: Mood] = [:]
    /// What the side panel on Home is showing, if it's open.
    @Published var inspecting: Inspecting?
    /// Keys picked on the keyboard picture (LED numbers).
    @Published var selectedKeys: Set<Int> = []

    enum Inspecting: Equatable { case mood, keys, light }

    init() {
        settings = Storage.load()
        registerHotkeys()
        wasPresent = Keyboard.isPresent
        connect()
        // Without a keyboard, still show the start-up mood on screen.
        if !wasPresent { DispatchQueue.main.async { [weak self] in self?.applyStartupMood() } }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyDockSetting()
            self.applyAppearance()
            // With the keyboard plugged in, start once it has connected.
            if self.settings.musicAtLaunch {
                if self.wasPresent { self.resumeMusicAfterConnect = true } else { self.startMusic() }
            }
        }
        // Once a second: idle dimming and the Accessibility check. Every third
        // tick, notice the cable being plugged in or pulled out (this only
        // checks whether the USB device exists; it sends nothing).
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        watchSystem()
        nowPlaying.onChange = { [weak self] state in
            guard let self else { return }
            // Only publish real changes: every publish redraws the windows,
            // and this runs every 2 seconds.
            if self.songPlaying != (state != nil) { self.songPlaying = state != nil }
            if self.nowPlayingNotAllowed != self.nowPlaying.notAllowed { self.nowPlayingNotAllowed = self.nowPlaying.notAllowed }
            let progress = state.map { ($0.position, $0.duration, $0.at) }
            let color = self.settings.nowPlayingColor
            self.queue.async {
                self.nowPlayingState = progress
                self.overlays.progressColor = color
            }
        }
        mail.onNewMail = { [weak self] n in
            guard let self, self.settings.mailAlerts, !self.darkened else { return }
            self.raiseAlert(n == 1 ? "New mail" : "\(n) new emails", until: nil, mail: true)
        }
        badges.onNewMessages = { [weak self] app, n in
            guard let self, self.settings.mailAlerts, !self.darkened else { return }
            // Each blink saves the strip twice (on, then back), so a busy
            // chat blinks at most once a minute.
            if let last = self.lastChatBlink, Date().timeIntervalSince(last) < 60 { return }
            self.lastChatBlink = Date()
            self.raiseAlert(n == 1 ? "New message in \(app)" : "\(n) new messages in \(app)",
                            until: Date().addingTimeInterval(4), mail: false, flashKeys: false)
        }
        updateExtras()
        // Put the lighting back if the app quits mid-song.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveNow()
                self?.stopMusicBeforeQuit()
            }
        }
    }

    var activeMood: Mood? { settings.moods.first { $0.id == settings.activeMoodID } }
    var canWrite: Bool { if case .connected = status { return true } else { return false } }

    private var ticks = 0

    private func tick() {
        ticks += 1
        // The on-screen picture only animates while F99 Mood is in front.
        let visible = (NSApp?.isActive ?? true)
            && (NSApp?.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) } ?? true)
        queue.async { [weak self] in self?.windowVisible = visible }
        if ticks % 3 == 0 { poll() }
        if musicOn, silentNow, ticks % 2 == 0 { updateHearingNothing() }
        checkIdle()
        checkSchedule()
        if let until = stripAlertUntil, Date() >= until { clearAlert() }
        if ticks % 30 == 0, mailNotAllowed != mail.notAllowed { mailNotAllowed = mail.notAllowed }
        if needsAccessibility, AXIsProcessTrusted() {
            needsAccessibility = false
            updateKeyMonitor() // the old monitors were added before access
        }
    }

    private func poll() {
        let present = Keyboard.isPresent
        defer { wasPresent = present }
        if !present, wasPresent {
            disconnect(reason: KeyboardError.notFound.localizedDescription)
        } else if present, !wasPresent, !busy {
            // Only try when the cable has just been plugged in, so a failure
            // (say, missing permission) doesn't repeat every few seconds.
            connect()
        }
    }

    private func disconnect(reason: String) {
        if musicOn { stopMusic() }
        // Remember a running live mood so it carries on once replugged.
        if liveMood != nil { stopLive() }
        queue.async { [weak self] in self?.keyboard = nil }
        page = nil
        status = .unavailable(reason)
    }

    func connect() {
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> (Keyboard, ConfigPage) in
                self.keyboard = nil
                let kb = try Keyboard.connect()
                let page = try kb.readSettings()
                self.keyboard = kb
                return (kb, page)
            }
            DispatchQueue.main.async {
                self.pending -= 1
                self.scheduleWaitsForKeyboard = false
                switch result {
                case .success(let (kb, page)):
                    self.page = page
                    self.identity = kb.identityHex
                    self.lastError = nil
                    if let name = kb.modelName {
                        Storage.saveBackupIfMissing(page)
                        self.status = .connected(name)
                        // Left in per-key mode by a session that never ended
                        // (unplugged, crash): put the lighting back first.
                        if page.isStreamMode && !self.musicOn && self.liveMood == nil { self.recoverFromStreamMode() }
                        self.resumeAfterConnect()
                        if self.resumeMusicAfterConnect {
                            self.resumeMusicAfterConnect = false
                            self.startMusic()
                        }
                    } else {
                        self.status = .readOnly(KeyboardError.unknownModel(kb.identityHex).localizedDescription)
                    }
                case .failure(let error):
                    self.page = nil
                    self.status = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    /// Run `work` against the keyboard off the main thread, then publish the
    /// page it returns.
    func perform(_ work: @escaping (Keyboard) throws -> ConfigPage, then: (() -> Void)? = nil) {
        pending += 1
        lastError = nil
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage in
                guard let kb = self.keyboard else { throw KeyboardError.notFound }
                return try work(kb)
            }
            DispatchQueue.main.async {
                self.pending -= 1
                switch result {
                case .success(let page):
                    self.page = page
                    then?()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    if case KeyboardError.io = error { self.connect() }
                }
            }
        }
    }

    /// Lights off, from the Off button. Not a mood in the list.
    private static let offMood = Mood(name: "Off", emoji: "", lighting: .init(effect: 1, brightness: 0, speed: 0, color: 6),
                                      hotkey: nil)
    func turnOff() { apply(Self.offMood) }
    var isOff: Bool { settings.activeMoodID == Self.offMood.id }

    /// `preview`: the mood editor showing changes as you make them, which
    /// doesn't count as using the mood.
    func apply(_ mood: Mood, preview: Bool = false) {
        if !preview, settings.moods.contains(where: { $0.id == mood.id }) { settings.moodUses[mood.id.uuidString, default: 0] += 1 }
        if mood.live != nil {
            startLive(mood)
            return
        }
        if liveMood != nil { stopLive() }
        // While music plays, a mood keeps the music going in that mood's
        // colours and brightness. Only "lights off" moods stop it.
        if musicOn && mood.lighting.brightness > 0 {
            musicMood = mood
            settings.activeMoodID = mood.id
            let palette = MusicPalette.forMood(mood)
            let scale = max(0.25, Double(mood.lighting.brightness) / 4)
            queue.async { [weak self] in
                self?.renderer.palette = palette
                self?.renderer.brightnessScale = scale
            }
            setStrip(strip(for: mood))
            return
        }
        if musicOn { stopMusic() }
        let lighting = mood.lighting
        guard canWrite else {
            // No keyboard: still show the mood on screen and switch macros.
            previewLighting = lighting
            settings.activeMoodID = mood.id
            return
        }
        let strip = strip(for: mood)
        perform({ try $0.apply(lighting, strip: strip) }) { [weak self] in
            self?.previewLighting = lighting
            self?.settings.activeMoodID = mood.id
        }
    }

    private var startedUp = false
    var lastAutoReconnect = Date.distantPast
    /// Music was on when the Mac went to sleep.
    var resumeMusicAfterConnect = false

    /// The keyboard is in per-key mode with nothing streaming: restore the
    /// lighting saved before the stream, else the original lighting, else a
    /// plain white.
    private func recoverFromStreamMode() {
        let saved = [Storage.loadStreamBackup(), Storage.loadBackup()].compactMap { $0 }.first { !$0.isStreamMode }
        perform { kb in
            let page = if let saved { try kb.restoreLighting(from: saved) }
                       else { try kb.apply(.init(effect: 1, brightness: 3, speed: 0, color: 6)) }
            Storage.clearStreamBackup()
            return page
        }
    }

    /// Switch to the start-up mood, unless music is playing. Runs once per
    /// launch: when the keyboard first connects, or at launch for the
    /// on-screen preview if there's no keyboard.
    func applyStartupMood() {
        startedUp = true
        // A schedule decides what's on now; otherwise the start-up mood.
        let scheduled = Schedule.current(settings.schedule, at: Date())?.moodID
        guard !musicOn, let id = scheduled ?? settings.startupMoodID,
              let mood = settings.moods.first(where: { $0.id == id }) else { return }
        if liveMood != nil { stopLive() }
        apply(mood)
    }

    /// After the keyboard (re)connects: the first time, the start-up mood;
    /// after that, carry on with the current live mood, which needs the Mac
    /// to keep streaming. Keyboard-effect moods are saved on the keyboard.
    private func resumeAfterConnect() {
        guard startedUp else { applyStartupMood(); return }
        guard !musicOn, let mood = activeMood, mood.live != nil,
              !(liveMood?.id == mood.id && liveSessionToKeyboard) else { return }
        if liveMood != nil { stopLive() }
        apply(mood)
    }

    func setStartupMood(_ id: UUID?) { settings.startupMoodID = id }

    /// The lighting for while F99 Mood isn't running, if a keyboard-effect
    /// mood is picked for it. Live moods can't run without the app.
    var awayLighting: ConfigPage.Lighting? {
        guard let id = settings.awayMoodID,
              let mood = settings.moods.first(where: { $0.id == id }), mood.live == nil else { return nil }
        return mood.lighting
    }

    func setKeepKeysLit(_ on: Bool) {
        settings.keepKeysLit = on
        pushFloor()
    }

    private func pushFloor() {
        let floor = keysLitFloor
        queue.async { [weak self] in
            self?.liveRenderer.minimumBrightness = floor
            self?.renderer.minimumBrightness = floor
        }
    }

    /// About half brightness by default: readable letters, room for effects.
    var keysLitFloor: Double { settings.keepKeysLit ? settings.keysLitLevel : 0 }

    /// The strip for a mood: steady in its colour if it has one fixed colour,
    /// off for a mood with the lights off, else the strip's own gradient.
    func strip(for mood: Mood) -> ConfigPage.Strip? {
        // An alert is showing on the strip: leave it until it's cleared.
        guard stripAlert == nil else { return nil }
        if let chosen = chosenStrip { return chosen }
        let fixed = (0..<F99.colorful).contains(mood.lighting.color)
        if let live = mood.live, !fixed { return live.palette.strip }
        var lighting = mood.lighting
        if mood.live != nil { lighting.brightness = max(lighting.brightness, 1) } // live moods are never dark
        return Self.strip(for: lighting)
    }

    /// The light bar the user picked when it doesn't match the keys.
    var chosenStrip: ConfigPage.Strip? {
        switch settings.stripStyle {
        case .match: nil
        case .color: .steady(settings.stripColor)
        case .off: .off
        }
    }

    /// The strip for music or a theme, or nil while an alert is showing.
    func strip(for palette: MusicPalette) -> ConfigPage.Strip? {
        guard stripAlert == nil else { return nil }
        return chosenStrip ?? palette.strip
    }

    /// The strip that matches what the keys show by themselves.
    nonisolated static func strip(for lighting: ConfigPage.Lighting) -> ConfigPage.Strip {
        if lighting.brightness == 0 { return .off }
        let fixed = (0..<F99.colorful).contains(lighting.color)
        guard F99.effect(lighting.effect)?.hasColor != false, fixed else { return .gradient }
        return .steady(lighting.color)
    }

    /// Change just the strip (a saved setting, so only on changes).
    func setStrip(_ strip: ConfigPage.Strip?) {
        guard let strip, canWrite, page?.shows(strip) != true else { return }
        perform { try $0.setStrip(strip) }
    }

    /// What the on-screen keyboard should show when music is off.
    var shownLighting: ConfigPage.Lighting? {
        if let current = page?.current, F99.effect(current.effect) != nil { return current }
        return previewLighting ?? activeMood?.lighting
    }

    func preview(_ lighting: ConfigPage.Lighting) {
        if musicOn { stopMusic() }
        perform { try $0.apply(lighting) }
    }

    var hasBackup: Bool { Storage.loadBackup() != nil }

    func restoreOriginal() {
        guard let saved = Storage.loadBackup() else { return }
        if musicOn { stopMusic() }
        perform({ try $0.restoreLighting(from: saved) }) { [weak self] in
            self?.settings.activeMoodID = nil
        }
    }

    // Stored state for the features in the AppModel+*.swift files.

    /// Bumped by every start and stop, so a start that finishes after it was
    /// cancelled doesn't leave a timer running.
    var streamSession = 0
    /// Runs on `queue`, 20 times a second.
    /// F99 Mood is in front with a window on screen (updated once a second).
    nonisolated(unsafe) var windowVisible = true
    var saveWork: DispatchWorkItem?
    var reapplyWork: DispatchWorkItem?
    /// 0...1, how bright frames go out (dim when idle, 0 when locked).
    /// Only touched on `queue`; eases towards `dimTarget`.
    nonisolated(unsafe) var dimLevel = 1.0
    nonisolated(unsafe) var dimTarget = 1.0
    /// The keyboard-effect lighting to put back after the lock screen.
    var lightingBeforeDark: ConfigPage.Lighting?
    /// The mood to go back to when leaving an app that switched moods.
    var moodBeforeApp: UUID??
    var appMoodID: UUID?
    var lastScheduleMinute = -1
    /// When the schedule was last checked. Entries that started since then
    /// still switch, so one due while the Mac slept isn't skipped.
    var scheduleCheckedAt: Date?
    /// Set while the Mac sleeps, until the keyboard has had a chance to come
    /// back, so a missed entry is applied to the keyboard and not to a dead
    /// connection.
    var scheduleWaitsForKeyboard = false
    /// (position, duration, when read), for the bar. Only touched on `queue`.
    nonisolated(unsafe) var nowPlayingState: (Double, Double, Date)?
    /// A mood being made in the editor. It's only added to the moods when
    /// you press Create; Cancel throws it away.
    @Published var newMood: Mood?
    var moodBeforeNew: UUID?

    // MARK: Shortcuts

    func registerHotkeys() {
        var bindings: [(Hotkey, () -> Void)] = []
        for mood in settings.moods {
            guard let key = mood.hotkey else { continue }
            let id = mood.id
            bindings.append((key, { [weak self] in
                guard let self, let m = self.settings.moods.first(where: { $0.id == id }) else { return }
                self.apply(m)
            }))
        }
        if let key = settings.musicHotkey {
            bindings.append((key, { [weak self] in self?.toggleMusic() }))
        }
        for macro in settings.macros {
            guard let key = macro.hotkey, !macro.value.isEmpty,
                  macro.moodID == nil || macro.moodID == settings.activeMoodID else { continue }
            let id = macro.id
            bindings.append((key, { [weak self] in
                // The macro as it is now, not as it was when registered.
                if let m = self?.settings.macros.first(where: { $0.id == id }) { MacroRunner.run(m) }
            }))
        }
        refusedHotkeys = HotkeyCenter.shared.register(bindings) + Array(settings.duplicateHotkeys)
    }
}

/// Music level and tempo for the meter, kept apart from `AppModel` so a
/// change redraws only the meter.
@MainActor
final class MusicMeter: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var bpm: Float = 0

    func update(level: Float, bpm: Float) {
        // Ignore tiny changes; the meter can't show them anyway.
        if abs(level - self.level) > 0.02 || (level == 0) != (self.level == 0) { self.level = level }
        let rounded = bpm.rounded()
        if rounded != self.bpm { self.bpm = rounded }
    }
}

extension Keyboard {
    /// Is a wired F99-family keyboard plugged in? Reads USB properties only.
    static var isPresent: Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: F99.vendorID,
            kIOHIDProductIDKey: F99.productID,
        ] as CFDictionary)
        return ((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0) > 0
    }
}
