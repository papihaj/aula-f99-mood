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
    @Published private(set) var needsAccessibility = false
    /// The screen is locked or asleep, so the lights are off.
    @Published private(set) var darkened = false
    /// No typing or mouse for a while, so live effects and music are dimmed.
    @Published private(set) var idleDimmed = false
    @Published private(set) var status: Status = .searching
    @Published private(set) var busy = false
    @Published private(set) var musicOn = false
    /// The colours music mode is painting right now (R, G, B per LED slot),
    /// for the on-screen keyboard. Nil when music is off.
    /// Not @Published on purpose: it changes 20 times a second, and
    /// publishing it would redraw every view in the app each time. The
    /// on-screen keyboard redraws by itself and reads it then.
    private(set) var streamFrame: [UInt8]?
    /// The music level and tempo, watched only by the meter.
    let meter = MusicMeter()
    /// True when the app has heard nothing at all for a while: either nothing
    /// is playing, or macOS hasn't allowed audio recording.
    @Published private(set) var hearingNothing = false
    /// A mood picked while music plays: the music takes its colours.
    @Published private(set) var musicMood: Mood?
    /// The live effect mood running now, if any.
    @Published private(set) var liveMood: Mood?
    /// Whether the running live effect is going to the keyboard (or only the
    /// on-screen preview, when it started without one).
    private var liveSessionToKeyboard = false
    nonisolated(unsafe) private let liveRenderer = LiveRenderer()
    private var liveTimer: DispatchSourceTimer?
    private var keyMonitors: [Any] = []
    /// The last mood picked, shown on screen even without the keyboard.
    @Published private(set) var previewLighting: ConfigPage.Lighting?
    /// Keyboard jobs queued or running; `busy` while any are.
    private var pending = 0 { didSet { busy = pending > 0 } }
    @Published private(set) var lastError: String?
    @Published private(set) var page: ConfigPage?
    @Published private(set) var refusedHotkeys: [Hotkey] = []
    @Published private(set) var identity = ""

    /// All HID traffic happens on this queue, one transfer at a time.
    private let queue = DispatchQueue(label: "f99.hid")
    /// Only touched on `queue`.
    nonisolated(unsafe) private var keyboard: Keyboard?
    private var timer: Timer?
    private var wasPresent = false

    // Music mode. The analyzer, renderer and saved page are only touched on `queue`.
    private var audio: AudioSource?
    nonisolated(unsafe) private let samples = SampleBuffer() // thread-safe
    /// Beat detection runs ~80 times a second on its own queue so beats land
    /// within ~12 ms; the lights still update 20 times a second.
    private let analysisQueue = DispatchQueue(label: "f99.analysis", qos: .userInitiated)
    nonisolated private static let analysisHop = 0.012
    nonisolated(unsafe) private var analyzer = MusicAnalyzer(hop: Float(AppModel.analysisHop))
    private var analysisTimer: DispatchSourceTimer?
    /// The analysis since the last light frame, with any beat in between kept.
    /// Guarded by `snapshotLock`.
    nonisolated(unsafe) private var pendingSnapshot: MusicSnapshot?
    private let snapshotLock = NSLock()
    /// Seconds of exact digital silence, to spot missing audio permission.
    nonisolated(unsafe) private var silentSeconds = 0.0
    nonisolated(unsafe) private var colorCorrection = true
    nonisolated(unsafe) private let renderer = MusicRenderer()
    nonisolated(unsafe) private var pageBeforeMusic: ConfigPage?
    nonisolated(unsafe) private var lastFrame: [UInt8] = []
    nonisolated(unsafe) private var lastSent = Date.distantPast
    nonisolated(unsafe) private var streamFailures = 0
    private var frameTimer: DispatchSourceTimer?

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
        let visible = NSApp?.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) } ?? true
        queue.async { [weak self] in self?.windowVisible = visible }
        if ticks % 3 == 0 { poll() }
        checkIdle()
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
    private func perform(_ work: @escaping (Keyboard) throws -> ConfigPage, then: (() -> Void)? = nil) {
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

    func apply(_ mood: Mood) {
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
            setStrip(stripColor(for: mood))
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
        let strip = stripColor(for: mood)
        perform({ try $0.apply(lighting, stripColor: strip) }) { [weak self] in
            self?.previewLighting = lighting
            self?.settings.activeMoodID = mood.id
        }
    }

    private var startedUp = false
    private var lastAutoReconnect = Date.distantPast
    /// Music was on when the Mac went to sleep.
    private var resumeMusicAfterConnect = false

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
        guard !musicOn, let id = settings.startupMoodID,
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

    func setKeepKeysLit(_ on: Bool) {
        settings.keepKeysLit = on
        pushFloor()
    }

    func setKeysLitLevel(_ level: Double) {
        settings.keysLitLevel = min(max(level, 0.2), 0.8)
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
    private var keysLitFloor: Double { settings.keepKeysLit ? settings.keysLitLevel : 0 }

    /// The strip colour for a mood: its colour, if it has one of the fixed
    /// colours. Colourful moods leave the strip as it is.
    private func stripColor(for mood: Mood) -> Int? {
        guard settings.stripFollowsColors else { return nil }
        if let live = mood.live, !(0..<F99.colorful).contains(mood.lighting.color) {
            return live.palette.stripColor
        }
        let effect = F99.effect(mood.lighting.effect)
        guard effect?.hasColor != false, (0..<F99.colorful).contains(mood.lighting.color) else { return nil }
        return mood.lighting.color
    }

    /// Set just the strip's colour (a saved setting, so only on changes).
    private func setStrip(_ color: Int?) {
        guard let color, canWrite, page?.stripColor != color else { return }
        perform { try $0.setStripColor(color) }
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

    func refresh() {
        perform { try $0.readSettings() }
    }

    var hasBackup: Bool { Storage.loadBackup() != nil }

    func restoreOriginal() {
        guard let saved = Storage.loadBackup() else { return }
        if musicOn { stopMusic() }
        perform({ try $0.restoreLighting(from: saved) }) { [weak self] in
            self?.settings.activeMoodID = nil
        }
    }

    // MARK: Music

    func toggleMusic() { musicOn ? stopMusic() : startMusic() }

    func setMusicStyle(_ style: MusicStyle) {
        settings.musicStyle = style
        queue.async { [weak self] in self?.renderer.style = style }
    }

    /// Pick a preset palette by name, or "Custom".
    func setMusicPalette(_ name: String) {
        settings.musicPaletteName = name
        pushPalette()
    }

    func setCustomColors(_ colors: [RGB]) {
        settings.customColors = colors
        pushPalette()
    }

    func setReducedFlashing(_ on: Bool) {
        settings.reducedFlashing = on
        queue.async { [weak self] in self?.renderer.reducedFlashing = on }
    }

    private func pushPalette() {
        let palette = settings.musicPalette
        musicMood = nil
        if musicOn, settings.stripFollowsColors { setStrip(palette.stripColor) }
        queue.async { [weak self] in
            self?.renderer.palette = palette
            self?.renderer.brightnessScale = 1
        }
    }

    func setStripFollowsColors(_ on: Bool) {
        settings.stripFollowsColors = on
    }

    func setColorCorrection(_ on: Bool) {
        settings.ledColorCorrection = on
        queue.async { [weak self] in self?.colorCorrection = on }
    }

    func setMusicInput(_ input: MusicInput) {
        settings.musicInput = input
        if musicOn { stopMusic(); startMusic() }
    }

    /// Starts music mode. Without a keyboard it still runs, so the on-screen
    /// keyboard can show what it would do.
    func startMusic() {
        guard !musicOn else { return }
        if liveMood != nil { stopLive() }
        // The first time, ask for the microphone and start once it's allowed.
        if settings.musicInput == .microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.startMusic() } else { self?.lastError = AudioError.microphoneDenied.localizedDescription }
                }
            }
            return
        }
        let toKeyboard = canWrite
        lastError = nil
        guard let source = startAudioSource() else { return }
        audio = source
        musicOn = true
        let style = settings.musicStyle
        let palette = settings.musicPalette
        let reduced = settings.reducedFlashing
        let floor = keysLitFloor
        let correction = settings.ledColorCorrection
        let strip = settings.stripFollowsColors ? palette.stripColor : nil
        musicMood = nil
        hearingNothing = false
        streamSession += 1
        let session = streamSession
        let dim = currentDimLevel

        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage? in
                guard toKeyboard else { return nil }
                guard let kb = self.keyboard else { throw KeyboardError.notFound }
                return try self.beginStream(kb, strip: strip)
            }
            if case .success(let before) = result {
                self.pageBeforeMusic = before
                self.dimLevel = dim; self.dimTarget = dim
                self.renderer.style = style
                self.renderer.palette = palette
                self.renderer.reducedFlashing = reduced
                self.renderer.brightnessScale = 1
                self.renderer.minimumBrightness = floor
                self.colorCorrection = correction
                self.lastFrame = []
                self.streamFailures = 0
            }
            DispatchQueue.main.async {
                self.pending -= 1
                switch result {
                case .success:
                    // Stopped while the keyboard was switching: the stop
                    // already queued the restore; don't start the timers.
                    guard session == self.streamSession, self.musicOn else { return }
                    self.startFrameTimer()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.stopAudio()
                }
            }
        }
    }

    /// Bumped by every start and stop, so a start that finishes after it was
    /// cancelled doesn't leave a timer running.
    private var streamSession = 0

    /// Switch the keyboard to per-key mode and remember the lighting from
    /// before, on disk too. Runs on `queue`.
    nonisolated private func beginStream(_ kb: Keyboard, strip: Int?) throws -> ConfigPage {
        var before = try kb.enterStreamMode(stripColor: strip)
        if before.isStreamMode {
            // Already per-key (say, a live mood resuming after a replug):
            // the lighting to go back to is the one saved earlier.
            before = [Storage.loadStreamBackup(), Storage.loadBackup()].compactMap { $0 }.first { !$0.isStreamMode }
                ?? before
        } else {
            Storage.saveStreamBackup(before)
        }
        return before
    }

    /// Put back the lighting from before the stream. Runs on `queue`. The
    /// saved copy is only dropped once the keyboard has it back.
    nonisolated private func endStream() throws -> ConfigPage? {
        guard let kb = keyboard, let before = pageBeforeMusic else { return nil }
        let page = try kb.restoreLighting(from: before)
        pageBeforeMusic = nil
        Storage.clearStreamBackup()
        return page
    }

    /// Start listening; nil (with the error shown) if it couldn't.
    private func startAudioSource() -> AudioSource? {
        let source: AudioSource = settings.musicInput == .system ? SystemAudioSource() : MicrophoneSource()
        do {
            try source.start(into: samples)
        } catch {
            source.stop()
            lastError = error.localizedDescription
            return nil
        }
        // The sound moved to another device (AirPods, a display): listen there.
        source.onDeviceChange = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.musicOn else { return }
                self.audio?.stop()
                self.audio = nil
                // Core Audio needs a moment to finish switching.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard self.musicOn, self.audio == nil else { return }
                    if let fresh = self.startAudioSource() { self.audio = fresh } else { self.stopMusic() }
                }
            }
        }
        return source
    }

    /// About 20 frames a second. The keyboard's own software never goes
    /// faster than one frame per 46 ms, and faster writes make it drop keys.
    private func startFrameTimer() {
        // Exact silence means no permission for either source (macOS sends
        // zeros rather than an error), or nothing playing.
        let isSystem = true
        analysisQueue.sync {
            analyzer = MusicAnalyzer(hop: Float(Self.analysisHop))
            silentSeconds = 0
        }
        snapshotLock.lock(); pendingSnapshot = nil; snapshotLock.unlock()
        let a = DispatchSource.makeTimerSource(queue: analysisQueue)
        a.schedule(deadline: .now(), repeating: .milliseconds(Int(Self.analysisHop * 1000)), leeway: .milliseconds(2))
        a.setEventHandler { [weak self] in self?.analyzeOnce(watchForSilence: isSystem) }
        analysisTimer = a
        a.resume()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.sendFrame() }
        frameTimer = t
        t.resume()
    }

    /// Runs on `queue`.
    /// Runs on `analysisQueue`, ~80 times a second.
    nonisolated private func analyzeOnce(watchForSilence: Bool) {
        let samples = self.samples.latest(2048)
        var snap = analyzer.analyze(samples, sampleRate: self.samples.sampleRate,
                                    time: ProcessInfo.processInfo.systemUptime)

        // Exact zeros for a while means either nothing is playing or macOS is
        // withholding the audio (it sends silence rather than an error).
        if watchForSilence {
            let wasSilent = silentSeconds >= 3
            silentSeconds = samples.contains { $0 != 0 } ? 0 : silentSeconds + Self.analysisHop
            let isSilent = silentSeconds >= 3
            if isSilent != wasSilent {
                DispatchQueue.main.async { [weak self] in self?.hearingNothing = isSilent }
            }
        }

        snapshotLock.lock()
        if let previous = pendingSnapshot, previous.beat {
            // Keep a beat that hasn't been drawn yet.
            snap.beat = true
            snap.strength = max(snap.strength, previous.strength)
            snap.barBeat = previous.barBeat
        }
        pendingSnapshot = snap
        snapshotLock.unlock()
    }

    /// LED brightness isn't seen linearly: half power looks much brighter
    /// than half. A 2.2 curve makes the keyboard match what's on screen.
    nonisolated private static let gamma: [UInt8] = (0..<256).map { UInt8((pow(Double($0) / 255, 2.2) * 255).rounded()) }

    nonisolated private func sendFrame() {
        snapshotLock.lock()
        let snapshot = pendingSnapshot
        pendingSnapshot = nil
        snapshotLock.unlock()
        guard let snapshot else { return }
        let frame = renderer.render(snapshot)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.musicOn else { return }
            self.streamFrame = frame
            self.meter.update(level: snapshot.level, bpm: snapshot.bpm)
        }
        push(frame, failureMessage: "Lost the keyboard while playing music.")
    }

    /// Send a frame to the keyboard, if a stream session switched it into
    /// per-key mode. Runs on `queue`.
    nonisolated private func push(_ frame: [UInt8], failureMessage: String) {
        guard let kb = keyboard, pageBeforeMusic != nil else { return }
        // Skip frames that didn't change, but resend every 2 s in case the
        // keyboard repainted by itself.
        // Ease towards the dim level, over about half a second.
        if dimLevel != dimTarget {
            dimLevel = dimTarget > dimLevel ? min(dimTarget, dimLevel + 0.1) : max(dimTarget, dimLevel - 0.1)
        }
        var frame = frame
        if dimLevel < 1 { frame = frame.map { UInt8(Double($0) * dimLevel) } }
        let now = Date()
        guard frame != lastFrame || now.timeIntervalSince(lastSent) > 2 else { return }
        do {
            try kb.stream(colorCorrection ? frame.map { Self.gamma[Int($0)] } : frame)
            lastFrame = frame
            lastSent = now
            streamFailures = 0
        } catch {
            streamFailures += 1
            if streamFailures == 5 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.stopMusic()
                    self.stopLive()
                    self.lastError = failureMessage
                    // The USB handle may be stale (say, after sleep): a fresh
                    // connection puts the lighting back and resumes live moods.
                    // At most once a minute, so a faulty keyboard can't loop.
                    if Keyboard.isPresent, Date().timeIntervalSince(self.lastAutoReconnect) > 60 {
                        self.lastAutoReconnect = Date()
                        self.connect()
                    }
                }
            }
        }
    }

    private func stopAudio() {
        frameTimer?.cancel()
        frameTimer = nil
        analysisTimer?.cancel()
        analysisTimer = nil
        hearingNothing = false
        meter.update(level: 0, bpm: 0)
        audio?.stop()
        audio = nil
        musicOn = false
        streamFrame = nil
    }

    /// Stop the music lights and put back the lighting from before.
    func stopMusic() {
        guard musicOn else { return }
        // A mood picked during the music stays on afterwards.
        let moodAfter = musicMood
        musicMood = nil
        stopAudio()
        streamSession += 1
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.endStream() }
            DispatchQueue.main.async {
                self.pending -= 1
                switch result {
                case .success(let page):
                    if let page { self.page = page }
                    if let moodAfter { self.apply(moodAfter) }
                case .failure(let error): self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Always waits for the keyboard queue: a stop pressed just before
    /// quitting may still have its restore queued.
    private func stopMusicBeforeQuit() {
        stopAudio()
        liveTimer?.cancel()
        liveTimer = nil
        let dark = lightingBeforeDark
        queue.sync {
            _ = try? endStream()
            if let dark, let kb = keyboard { _ = try? kb.apply(dark) }
        }
    }

    // MARK: Live effects

    private func livePalette(_ mood: Mood) -> MusicPalette {
        guard let live = mood.live else { return settings.musicPalette }
        if let name = mood.paletteName {
            if name == MusicPalette.customName { return MusicPalette(name: name, colors: settings.customColors) }
            if let preset = MusicPalette.presets.first(where: { $0.name == name }) { return preset }
        }
        return (0..<F99.colorful).contains(mood.lighting.color) ? MusicPalette.forMood(mood) : live.palette
    }

    /// Whether pressed keys glow in this effect, from the setting.
    private func glows(_ effect: LiveEffect) -> Bool {
        switch settings.pressGlow {
        case .off: return false
        case .typingEffects: return effect.pressGlow
        case .allLive: return !effect.drawsPresses
        }
    }

    private func listensForKeys(_ effect: LiveEffect) -> Bool { effect.drawsPresses || glows(effect) }

    /// Push the press-glow settings to the live renderer.
    func updatePressGlow() {
        guard let effect = liveMood?.live else { return }
        let on = glows(effect)
        let color: RGB? = switch settings.pressColor {
        case .lightest: nil
        case .white: RGB(1, 1, 1)
        case .custom: settings.pressCustomColor
        }
        let halo = settings.pressHalo, fade = settings.pressFade
        queue.async { [weak self] in
            guard let r = self?.liveRenderer else { return }
            r.pressGlow = on; r.pressColor = color; r.haloSize = halo; r.pressFade = fade
        }
        updateKeyMonitor()
    }

    /// Start (or switch to) a live effect mood. Without a keyboard it still
    /// runs, on the on-screen keyboard.
    private func startLive(_ mood: Mood) {
        guard let effect = mood.live else { return }
        if musicOn {
            musicMood = nil // don't re-apply a music mood once the music stops
            stopMusic()
        }
        settings.activeMoodID = mood.id
        let palette = livePalette(mood)
        let scale = Double(mood.lighting.brightness) / 4
        let speed = mood.lighting.speed
        let floor = keysLitFloor
        let glow = glows(effect)
        let pressColor: RGB? = switch settings.pressColor {
        case .lightest: nil
        case .white: RGB(1, 1, 1)
        case .custom: settings.pressCustomColor
        }
        let halo = settings.pressHalo, fade = settings.pressFade
        let configure: (LiveRenderer) -> Void = { r in
            r.effect = effect
            r.palette = palette
            r.brightnessScale = scale
            r.speed = speed
            r.minimumBrightness = floor
            r.pressGlow = glow
            r.pressColor = pressColor
            r.haloSize = halo
            r.pressFade = fade
        }

        if liveMood != nil {
            // Already streaming: just switch effect.
            liveMood = mood
            queue.async { [weak self] in if let self { configure(self.liveRenderer) } }
            setStrip(stripColor(for: mood))
            updateKeyMonitor()
            return
        }

        liveMood = mood
        lastError = nil
        let toKeyboard = canWrite
        liveSessionToKeyboard = toKeyboard
        let strip = stripColor(for: mood)
        let correction = settings.ledColorCorrection
        streamSession += 1
        let session = streamSession
        let dim = currentDimLevel
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage? in
                guard toKeyboard else { return nil }
                guard let kb = self.keyboard else { throw KeyboardError.notFound }
                return try self.beginStream(kb, strip: strip)
            }
            if case .success(let before) = result {
                self.pageBeforeMusic = before
                self.dimLevel = dim; self.dimTarget = dim
                configure(self.liveRenderer)
                self.colorCorrection = correction
                self.lastFrame = []
                self.streamFailures = 0
            }
            DispatchQueue.main.async {
                self.pending -= 1
                switch result {
                case .success:
                    guard session == self.streamSession, self.liveMood != nil else { return }
                    let t = DispatchSource.makeTimerSource(queue: self.queue)
                    t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
                    t.setEventHandler { [weak self] in self?.sendLiveFrame() }
                    self.liveTimer = t
                    t.resume()
                    self.updateKeyMonitor()
                case .failure(let error):
                    guard session == self.streamSession else { return }
                    self.lastError = error.localizedDescription
                    self.liveMood = nil
                }
            }
        }
    }

    /// Runs on `queue`, 20 times a second.
    /// Some F99 Mood window is on screen (updated once a second).
    nonisolated(unsafe) private var windowVisible = true

    nonisolated private func sendLiveFrame() {
        // Without a keyboard the frames are only for the on-screen picture.
        guard pageBeforeMusic != nil || windowVisible else { return }
        let frame = liveRenderer.render()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.liveMood != nil else { return }
            self.streamFrame = frame
        }
        push(frame, failureMessage: "Lost the keyboard while showing a live effect.")
    }

    /// Stop the live effect and put back the lighting from before it.
    func stopLive() {
        guard liveMood != nil else { return }
        liveTimer?.cancel()
        liveTimer = nil
        liveMood = nil
        streamFrame = nil
        updateKeyMonitor()
        streamSession += 1
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.endStream() }
            DispatchQueue.main.async {
                self.pending -= 1
                switch result {
                case .success(let page): if let page { self.page = page }
                case .failure(let error): self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Typing effects listen for key presses: only which key, to light it,
    /// and only while a typing effect is on. Nothing is stored.
    private var askedForAccessibility = false

    private func updateKeyMonitor() {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors = []
        guard let effect = liveMood?.live, listensForKeys(effect) else {
            needsAccessibility = false
            return
        }
        if !AXIsProcessTrusted() {
            needsAccessibility = true
            // Ask once per launch; after that the banner explains it.
            if !askedForAccessibility {
                askedForAccessibility = true
                MacroRunner.askForAccessibility()
            }
        }
        let renderer = liveRenderer
        let queue = self.queue
        let handler: (NSEvent) -> Void = { event in
            if event.type == .flagsChanged && !KeyMap.isPress(event) { return }
            guard let led = KeyMap.led(forKeyCode: event.keyCode) else { return }
            let now = Date()
            queue.async { renderer.keyPressed(led: led, at: now) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handler) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: { handler($0); return $0 }) {
            keyMonitors.append(local)
        }
    }

    // MARK: Settings changes

    private var saveWork: DispatchWorkItem?
    private var reapplyWork: DispatchWorkItem?

    private func settingsChanged(from old: AppSettings) {
        // Typing in a name field changes settings on every key: save once
        // things settle, and only re-register shortcuts when they changed.
        saveWork?.cancel()
        let snapshot = settings
        let work = DispatchWorkItem { Storage.save(snapshot) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)

        if Self.hotkeySignature(old) != Self.hotkeySignature(settings) { registerHotkeys() }

        // The running live mood was deleted: stop it.
        if let live = liveMood, !settings.moods.contains(where: { $0.id == live.id }) {
            stopLive()
        }
        // The mood that's on was edited: show the change right away.
        if let id = settings.activeMoodID, old.activeMoodID == id,
           let now = settings.moods.first(where: { $0.id == id }),
           let before = old.moods.first(where: { $0.id == id }),
           now.lighting != before.lighting || now.live != before.live || now.paletteName != before.paletteName {
            reapplyWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.settings.activeMoodID == id,
                      let mood = self.settings.moods.first(where: { $0.id == id }) else { return }
                if self.musicOn && self.musicMood?.id != id { return }
                self.apply(mood)
            }
            reapplyWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        if old.customColors != settings.customColors, let mood = liveMood, mood.paletteName == MusicPalette.customName {
            let palette = livePalette(mood)
            queue.async { [weak self] in self?.liveRenderer.palette = palette }
        }
    }

    /// Save now (on quit).
    func saveNow() {
        saveWork?.cancel()
        Storage.save(settings)
    }

    private static func hotkeySignature(_ s: AppSettings) -> [String] {
        s.moods.map { "m\($0.id)\(String(describing: $0.hotkey))" }
            + s.macros.map { "k\($0.id)\(String(describing: $0.hotkey))\(String(describing: $0.moodID))\($0.value.isEmpty)" }
            + ["music\(String(describing: s.musicHotkey))", "active\(String(describing: s.activeMoodID))"]
    }

    // MARK: Moods: delete, duplicate, import, export

    func deleteMood(_ id: UUID) {
        if liveMood?.id == id { stopLive() }
        settings.deleteMood(id)
    }

    @discardableResult
    func duplicateMood(_ id: UUID) -> Mood? {
        guard let i = settings.moods.firstIndex(where: { $0.id == id }) else { return nil }
        let copy = settings.moods[i].copy(named: settings.moods[i].name + " copy")
        settings.moods.insert(copy, at: i + 1)
        return copy
    }

    /// Put back the built-in moods that were deleted. Returns how many.
    func restoreBuiltInMoods() -> Int {
        var s = settings
        let n = s.addMissingBuiltInMoods()
        if n > 0 { settings = s }
        return n
    }

    func exportMoods(_ moods: [Mood], to url: URL) throws {
        // Shortcuts and apps are personal; leave them out of a shared file.
        let shared = moods.map { m -> Mood in var c = m; c.hotkey = nil; c.apps = []; return c }
        try Storage.encode(MoodFile(moods: shared)).write(to: url, options: .atomic)
    }

    func importMoods(from url: URL) throws -> Int {
        let file = try JSONDecoder().decode(MoodFile.self, from: Data(contentsOf: url))
        guard !file.moods.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        var s = settings
        let added = s.importMoods(file.moods)
        settings = s
        return added.count
    }

    /// Back to how the app is for a new user. Your keyboard's saved original
    /// lighting backup is kept.
    func resetAllSettings() {
        if musicOn { stopMusic() }
        if liveMood != nil { stopLive() }
        var fresh = AppSettings.defaults
        fresh.welcomeDone = true
        settings = fresh
        applyDockSetting()
    }

    // MARK: App-wide options

    func setShowInDock(_ on: Bool) {
        settings.showInDock = on
        applyDockSetting()
    }

    private func applyDockSetting() {
        NSApp?.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message if macOS refused.
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
            return nil
        } catch {
            objectWillChange.send()
            return "macOS didn't allow it: \(error.localizedDescription). Move F99 Mood to Applications and try again, or add it under System Settings → General → Login Items."
        }
    }

    // MARK: Lock, sleep, idle and app switching

    /// 0...1, how bright frames go out (dim when idle, 0 when locked).
    /// Only touched on `queue`; eases towards `dimTarget`.
    nonisolated(unsafe) private var dimLevel = 1.0
    nonisolated(unsafe) private var dimTarget = 1.0
    /// The keyboard-effect lighting to put back after the lock screen.
    private var lightingBeforeDark: ConfigPage.Lighting?
    /// The mood to go back to when leaving an app that switched moods.
    private var moodBeforeApp: UUID??
    private var appMoodID: UUID?

    private func watchSystem() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDark(true) }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDark(false) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDark(true) }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Waking the screen may still show the lock screen; wait for the
            // unlock in that case.
            MainActor.assumeIsolated { if !Self.screenLocked { self?.setDark(false) } }
        }
        // Sleep cuts the USB connection: end the stream first so the keyboard
        // isn't left in per-key mode, and pick it up again after waking.
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.resumeMusicAfterConnect = self.musicOn
                if self.musicOn { self.stopMusic() }
                if self.liveMood != nil { self.stopLive() }
                self.queue.sync {} // let the restore finish before sleeping
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Give USB a moment to come back, then start afresh.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, Keyboard.isPresent else { return }
                self.connect()
            }
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontAppChanged(id) }
        }
    }

    private static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private var currentDimLevel: Double { darkened ? 0 : idleDimmed ? Self.idleLevel : 1 }

    private func setDark(_ dark: Bool) {
        guard dark != darkened else { return }
        if dark && !settings.darkWhenLocked { return }
        darkened = dark
        let target = currentDimLevel
        queue.async { [weak self] in self?.dimTarget = target; if dark { self?.dimLevel = 0 } }
        if musicOn || liveMood != nil { return }
        // A keyboard effect: switch its lights off, and back on afterwards.
        guard canWrite else { return }
        if dark {
            guard let current = page?.current, current.brightness > 0 else { return }
            lightingBeforeDark = current
            var off = current
            off.brightness = 0
            perform { try $0.apply(off) }
        } else if let before = lightingBeforeDark {
            lightingBeforeDark = nil
            perform { try $0.apply(before) }
        }
    }

    static let idleLevel = 0.25

    private func checkIdle() {
        guard settings.dimAfterMinutes > 0, musicOn || liveMood != nil else {
            if idleDimmed { setIdle(false) }
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        setIdle(idle >= Double(settings.dimAfterMinutes) * 60)
    }

    private func setIdle(_ on: Bool) {
        guard on != idleDimmed else { return }
        idleDimmed = on
        let target = currentDimLevel
        queue.async { [weak self] in self?.dimTarget = target }
    }

    private func frontAppChanged(_ bundleID: String?) {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
        if let mood = settings.moods.first(where: { $0.apps.contains(bundleID) }) {
            guard appMoodID != mood.id else { return }
            if appMoodID == nil { moodBeforeApp = .some(settings.activeMoodID) }
            appMoodID = mood.id
            if settings.activeMoodID != mood.id || (mood.live != nil && liveMood?.id != mood.id) { apply(mood) }
        } else if appMoodID != nil {
            // Back from the app: the mood from before it.
            appMoodID = nil
            if case .some(let previous) = moodBeforeApp, let id = previous,
               let mood = settings.moods.first(where: { $0.id == id }) {
                apply(mood)
            }
            moodBeforeApp = nil
        }
    }

    // MARK: Shortcuts

    private func registerHotkeys() {
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
