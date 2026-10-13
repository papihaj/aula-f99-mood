import AppKit
import IOKit.hid
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
        didSet {
            Storage.save(settings)
            registerHotkeys()
        }
    }
    @Published private(set) var status: Status = .searching
    @Published private(set) var busy = false
    @Published private(set) var musicOn = false
    /// The colours music mode is painting right now (R, G, B per LED slot),
    /// for the on-screen keyboard. Nil when music is off.
    @Published private(set) var streamFrame: [UInt8]?
    @Published private(set) var musicLevel: Float = 0
    @Published private(set) var musicBPM: Float = 0
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
        // Notice the cable being plugged in or pulled out. This only checks
        // whether the USB device exists; it sends nothing to the keyboard.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        // Put the lighting back if the app quits mid-song.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopMusicBeforeQuit() }
        }
    }

    var activeMood: Mood? { settings.moods.first { $0.id == settings.activeMoodID } }
    var canWrite: Bool { if case .connected = status { return true } else { return false } }

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
                        self.resumeAfterConnect()
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
        let floor = on ? Self.keysLitFloor : 0
        queue.async { [weak self] in
            self?.liveRenderer.minimumBrightness = floor
            self?.renderer.minimumBrightness = floor
        }
    }

    /// About half brightness: readable letters, room left for effects.
    static let keysLitFloor = 0.5

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
        let toKeyboard = canWrite
        lastError = nil
        let source: AudioSource = settings.musicInput == .system ? SystemAudioSource() : MicrophoneSource()
        do {
            try source.start(into: samples)
        } catch {
            source.stop()
            lastError = error.localizedDescription
            return
        }
        audio = source
        musicOn = true
        let style = settings.musicStyle
        let palette = settings.musicPalette
        let reduced = settings.reducedFlashing
        let floor = settings.keepKeysLit ? Self.keysLitFloor : 0
        let correction = settings.ledColorCorrection
        let strip = settings.stripFollowsColors ? palette.stripColor : nil
        musicMood = nil
        hearingNothing = false

        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage? in
                guard toKeyboard else { return nil }
                guard let kb = self.keyboard else { throw KeyboardError.notFound }
                return try kb.enterStreamMode(stripColor: strip)
            }
            if case .success(let before) = result {
                self.pageBeforeMusic = before
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
                case .success: self.startFrameTimer()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.stopAudio()
                }
            }
        }
    }

    /// About 20 frames a second. The keyboard's own software never goes
    /// faster than one frame per 46 ms, and faster writes make it drop keys.
    private func startFrameTimer() {
        let isSystem = settings.musicInput == .system
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
            self.musicLevel = snapshot.level
            self.musicBPM = snapshot.bpm
        }
        push(frame, failureMessage: "Lost the keyboard while playing music.")
    }

    /// Send a frame to the keyboard, if a stream session switched it into
    /// per-key mode. Runs on `queue`.
    nonisolated private func push(_ frame: [UInt8], failureMessage: String) {
        guard let kb = keyboard, pageBeforeMusic != nil else { return }
        // Skip frames that didn't change, but resend every 2 s in case the
        // keyboard repainted by itself.
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
                    self?.lastError = failureMessage
                    self?.stopMusic()
                    self?.stopLive()
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
        musicBPM = 0
        audio?.stop()
        audio = nil
        musicOn = false
        streamFrame = nil
        musicLevel = 0
    }

    /// Stop the music lights and put back the lighting from before.
    func stopMusic() {
        guard musicOn else { return }
        // A mood picked during the music stays on afterwards.
        let moodAfter = musicMood
        musicMood = nil
        stopAudio()
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage? in
                guard let kb = self.keyboard, let before = self.pageBeforeMusic else { return nil }
                return try kb.restoreLighting(from: before)
            }
            self.pageBeforeMusic = nil
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

    private func stopMusicBeforeQuit() {
        guard musicOn || liveMood != nil else { return }
        stopAudio()
        liveTimer?.cancel()
        queue.sync {
            if let kb = keyboard, let before = pageBeforeMusic {
                _ = try? kb.restoreLighting(from: before)
            }
        }
    }

    // MARK: Live effects

    private func livePalette(_ mood: Mood) -> MusicPalette {
        guard let live = mood.live else { return settings.musicPalette }
        return (0..<F99.colorful).contains(mood.lighting.color) ? MusicPalette.forMood(mood) : live.palette
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
        let floor = settings.keepKeysLit ? Self.keysLitFloor : 0
        let configure: (LiveRenderer) -> Void = { r in
            r.effect = effect
            r.palette = palette
            r.brightnessScale = scale
            r.speed = speed
            r.minimumBrightness = floor
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
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage? in
                guard toKeyboard else { return nil }
                guard let kb = self.keyboard else { throw KeyboardError.notFound }
                return try kb.enterStreamMode(stripColor: strip)
            }
            if case .success(let before) = result {
                self.pageBeforeMusic = before
                configure(self.liveRenderer)
                self.colorCorrection = correction
                self.lastFrame = []
                self.streamFailures = 0
            }
            DispatchQueue.main.async {
                self.pending -= 1
                switch result {
                case .success:
                    let t = DispatchSource.makeTimerSource(queue: self.queue)
                    t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
                    t.setEventHandler { [weak self] in self?.sendLiveFrame() }
                    self.liveTimer = t
                    t.resume()
                    self.updateKeyMonitor()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.liveMood = nil
                }
            }
        }
    }

    /// Runs on `queue`, 20 times a second.
    nonisolated private func sendLiveFrame() {
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
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> ConfigPage? in
                guard let kb = self.keyboard, let before = self.pageBeforeMusic else { return nil }
                return try kb.restoreLighting(from: before)
            }
            self.pageBeforeMusic = nil
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
    private func updateKeyMonitor() {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors = []
        guard let effect = liveMood?.live, effect.reactsToTyping else { return }
        if !AXIsProcessTrusted() {
            MacroRunner.askForAccessibility()
            lastError = "Typing effects need Accessibility permission to see key presses in other apps: turn on F99 Mood under Privacy & Security → Accessibility."
        }
        let renderer = liveRenderer
        let queue = self.queue
        let handler: (NSEvent) -> Void = { event in
            guard let led = KeyMap.led(forKeyCode: event.keyCode) else { return }
            let now = Date()
            queue.async { renderer.keyPressed(led: led, at: now) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { handler($0); return $0 }) {
            keyMonitors.append(local)
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
            guard let key = macro.hotkey,
                  macro.moodID == nil || macro.moodID == settings.activeMoodID else { continue }
            bindings.append((key, { MacroRunner.run(macro) }))
        }
        refusedHotkeys = HotkeyCenter.shared.register(bindings)
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
