import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import SwiftUI

// Reacting to the Mac: lock, sleep, idle and app switching.
@MainActor
extension AppModel {
    // MARK: Lock, sleep, idle and app switching

    func watchSystem() {
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
                self.scheduleWaitsForKeyboard = true
                self.resumeMusicAfterConnect = self.musicOn
                if self.musicOn { self.stopMusic() }
                if self.liveMood != nil { self.stopLive() }
                self.queue.sync {} // let the restore finish before sleeping
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Give USB a moment to come back, then start afresh.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self else { return }
                guard Keyboard.isPresent else { self.scheduleWaitsForKeyboard = false; return }
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

    var currentDimLevel: Double { darkened ? 0 : idleDimmed ? Self.idleLevel : 1 }

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

    func checkIdle() {
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
        if bundleID == "com.apple.mail", stripAlertIsMail { clearAlert() }
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
}
