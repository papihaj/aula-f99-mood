import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import EventKit
import SwiftUI

// Live effects: animated moods drawn on the Mac and streamed to the keys.
@MainActor
extension AppModel {
    // MARK: Live effects

    func livePalette(_ mood: Mood) -> MusicPalette {
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
    func startLive(_ mood: Mood) {
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
        let paint = mood.paintByLED, paintBase = mood.paintBase
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
            r.paint = paint
            r.paintBase = paintBase
        }

        if liveMood != nil {
            // Already streaming: just switch effect.
            liveMood = mood
            queue.async { [weak self] in if let self { configure(self.liveRenderer) } }
            setStrip(strip(for: mood))
            updateKeyMonitor()
            return
        }

        liveMood = mood
        lastError = nil
        let toKeyboard = canWrite
        liveSessionToKeyboard = toKeyboard
        let strip = strip(for: mood)
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

    nonisolated private func sendLiveFrame() {
        // Without a keyboard the frames are only for the on-screen picture.
        guard pageBeforeMusic != nil || windowVisible else { return }
        let frame = withOverlays(liveRenderer.render())
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
                case .success(let page):
                    if let page { self.page = page }
                    self.keepAlertStrip()
                case .failure(let error): self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Typing effects listen for key presses: only which key, to light it,
    /// and only while a typing effect is on. Nothing is stored.

    func updateKeyMonitor() {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors = []
        let lights = liveMood?.live.map(listensForKeys) ?? false
        let sounds = settings.keySounds && keySoundError == nil
        guard lights || sounds else {
            needsAccessibility = false
            return
        }
        // Never pop up macOS's prompt by itself: the banner explains, and
        // its button asks.
        needsAccessibility = !AXIsProcessTrusted()
        let renderer = liveRenderer
        let queue = self.queue
        let player = keySounds
        let handler: (NSEvent) -> Void = { event in
            if event.type == .flagsChanged && !KeyMap.isPress(event) { return }
            if sounds && event.type == .keyDown && !event.isARepeat {
                MainActor.assumeIsolated { player.play(keyCode: event.keyCode) }
            }
            guard lights, let led = KeyMap.led(forKeyCode: event.keyCode) else { return }
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
}
