import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import SwiftUI

// Music mode: listening to audio and streaming frames to the keys.
@MainActor
extension AppModel {
    // MARK: Music

    func toggleMusic() { musicOn ? stopMusic() : startMusic() }

    /// Dance to music in a mood's colours: a named theme (Pastel, Electric…)
    /// becomes the music theme; other moods lend their colours for this song.
    func danceInColours(of mood: Mood) {
        let palette = livePalette(mood)
        let named = mood.live == nil ? nil : MusicPalette.presets.first { $0.name == palette.name }?.name
            ?? (palette.name == MusicPalette.customName ? palette.name : nil)
        if let named { setMusicPalette(named) }
        if liveMood != nil { stopLive() }
        startMusic()
        guard musicOn, named == nil else { return }
        if mood.live == nil { apply(mood); return } // music carries on in the mood's colours
        musicMood = mood
        settings.activeMoodID = mood.id
        queue.async { [weak self] in self?.renderer.palette = palette }
        setStrip(strip(for: palette))
    }

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
        if musicOn { setStrip(strip(for: palette)) }
        queue.async { [weak self] in
            self?.renderer.palette = palette
            self?.renderer.brightnessScale = 1
        }
    }

    /// Change what the light bar shows, and show it now.
    func setStrip(style: StripStyle, color: Int? = nil) {
        settings.stripStyle = style
        if let color { settings.stripColor = color }
        let wanted: ConfigPage.Strip?
        if musicOn {
            wanted = strip(for: musicMood.map(livePalette) ?? settings.musicPalette)
        } else if let mood = liveMood ?? activeMood {
            wanted = strip(for: mood)
        } else {
            wanted = stripAlert == nil ? chosenStrip : nil
        }
        setStrip(wanted)
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
        let strip = self.strip(for: palette)
        musicMood = nil
        hearingNothing = false
        silentNow = false
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

    /// Switch the keyboard to per-key mode and remember the lighting from
    /// before, on disk too. Runs on `queue`.
    nonisolated func beginStream(_ kb: Keyboard, strip: ConfigPage.Strip?) throws -> ConfigPage {
        var before = try kb.enterStreamMode(strip: strip)
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
    nonisolated func endStream() throws -> ConfigPage? {
        guard let kb = keyboard, let before = pageBeforeMusic else { return nil }
        let page = try kb.restoreLighting(from: before)
        pageBeforeMusic = nil
        Storage.clearStreamBackup()
        return page
    }

    /// Start listening; nil (with the error shown) if it couldn't.
    private func startAudioSource() -> AudioSource? {
        let source: AudioSource
        if settings.musicInput == .system, #available(macOS 14.2, *) { source = SystemAudioSource() } else { source = MicrophoneSource() }
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
    /// Warn about silence only while another app is playing sound: then
    /// macOS is withholding it. Nothing playing is just quiet.
    func updateHearingNothing() {
        let warn = musicOn && silentNow && settings.musicInput == .system && (PlaybackCheck.otherAppPlaying ?? true)
        if hearingNothing != warn { hearingNothing = warn }
    }

    /// Runs on `analysisQueue`, 40 times a second.
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
                DispatchQueue.main.async { [weak self] in
                    self?.silentNow = isSilent
                    self?.updateHearingNothing()
                }
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
        let frame = withOverlays(renderer.render(snapshot))
        // Redraw the on-screen keyboard only while someone can see it.
        if windowVisible {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.musicOn else { return }
                self.streamFrame = frame
                self.meter.update(level: snapshot.level, bpm: snapshot.bpm)
            }
        }
        push(frame, failureMessage: "Lost the keyboard while playing music.")
    }

    /// Send a frame to the keyboard, if a stream session switched it into
    /// per-key mode. Runs on `queue`.
    nonisolated func push(_ frame: [UInt8], failureMessage: String) {
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
        silentNow = false
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
                    self.keepAlertStrip()
                case .failure(let error): self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Always waits for the keyboard queue: a stop pressed just before
    /// quitting may still have its restore queued.
    func stopMusicBeforeQuit() {
        stopAudio()
        liveTimer?.cancel()
        liveTimer = nil
        let dark = lightingBeforeDark
        let matchStrip = settings.stripStyle == .match && stripAlert == nil
        queue.sync {
            _ = try? endStream()
            if let dark, let kb = keyboard { _ = try? kb.apply(dark) }
            // Music and live moods colour the strip, but the keys go back to
            // the keyboard's own lighting: leave the strip matching that.
            if matchStrip, let kb = keyboard, let page = try? kb.readSettings(), let lighting = page.current {
                let strip = Self.strip(for: lighting)
                if !page.shows(strip) { _ = try? kb.setStrip(strip) }
            }
        }
    }
}
