import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import SwiftUI

// Saving settings, and app-wide options.
@MainActor
extension AppModel {
    // MARK: Settings changes

    func settingsChanged(from old: AppSettings) {
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
           now.lighting != before.lighting || now.live != before.live || now.paletteName != before.paletteName
            || now.paint != before.paint || now.paintBase != before.paintBase {
            // Painting shows at once, without waiting.
            if liveMood?.id == id, now.live != nil, now.lighting == before.lighting, now.live == before.live,
               now.paletteName == before.paletteName {
                let paint = now.paintByLED, base = now.paintBase
                queue.async { [weak self] in self?.liveRenderer.paint = paint; self?.liveRenderer.paintBase = base }
                liveMood = now
            }
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
        if old.nowPlayingBar != settings.nowPlayingBar || old.nowPlayingColor != settings.nowPlayingColor
            || old.keySounds != settings.keySounds || old.keySound != settings.keySound
            || old.keySoundFile != settings.keySoundFile || old.keySoundVolume != settings.keySoundVolume
            || old.mailAlerts != settings.mailAlerts {
            updateExtras()
        }
        if old.appearance != settings.appearance { applyAppearance() }
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

    /// Quit and open again, so macOS applies a permission just turned on.
    func relaunch() {
        saveNow()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    private static func hotkeySignature(_ s: AppSettings) -> [String] {
        s.moods.map { "m\($0.id)\(String(describing: $0.hotkey))" }
            + s.macros.map { "k\($0.id)\(String(describing: $0.hotkey))\(String(describing: $0.moodID))\($0.value.isEmpty)" }
            + ["music\(String(describing: s.musicHotkey))", "active\(String(describing: s.activeMoodID))"]
    }

    // MARK: App-wide options

    func setShowInDock(_ on: Bool) {
        settings.showInDock = on
        applyDockSetting()
    }

    /// Light, dark, or following the Mac. The colours in `Theme` change with it.
    func applyAppearance() {
        NSApp.appearance = switch settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func applyDockSetting() {
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
}
