import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import EventKit
import SwiftUI

// Extras: the schedule, calendar and mail alerts, now playing and typing sounds.
@MainActor
extension AppModel {
    // MARK: Schedule, calendar alerts, now playing, typing sounds

    /// Once a minute: switch to a mood that's scheduled to have started since
    /// the last check.
    func checkSchedule() {
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        guard minute != lastScheduleMinute, !scheduleWaitsForKeyboard else { return }
        lastScheduleMinute = minute
        let since = scheduleCheckedAt ?? now.addingTimeInterval(-60)
        scheduleCheckedAt = now
        guard let entry = Schedule.latest(settings.schedule, after: since, through: now), let id = entry.moodID,
              let mood = settings.moods.first(where: { $0.id == id }) else { return }
        // Already on, or an app's own mood is in charge: leave it.
        if settings.activeMoodID == id && (mood.live == nil || liveMood?.id == id) { return }
        if appMoodID != nil { moodBeforeApp = .some(id); return }
        apply(mood)
    }

    func checkCalendar() {
        guard settings.calendarAlerts, !darkened else { return }
        let events = calendar.due(minutesBefore: settings.alertMinutesBefore)
        guard let first = events.min(by: { $0.startDate < $1.startDate }) else { return }
        let time = first.startDate.formatted(date: .omitted, time: .shortened)
        // The strip stays lit until the event starts (or for 2 minutes).
        let until = max(first.startDate, Date().addingTimeInterval(120))
        raiseAlert("\(first.title ?? "Event") at \(time)", until: until, mail: false)
    }

    /// Ask for calendar access; calls back with whether it was allowed.
    func requestCalendarAccess(_ done: @escaping (Bool) -> Void) {
        calendar.requestAccess { ok in
            DispatchQueue.main.async {
                self.objectWillChange.send()
                done(ok)
            }
        }
    }

    /// Put F99 Mood in the Calendars list and open it there.
    func turnOnCalendars() {
        PrivacyPane.turnOn(service: "Calendar", pane: "Privacy_Calendars") { requestCalendarAccess { _ in } }
    }

    /// Flash the whole keyboard a few times. On top of a live effect or the
    /// music; with a keyboard effect on, the keyboard is switched to per-key
    /// mode just for the flashes, then put back.
    func flash(color: RGB, times: Int) {
        let flash = Overlays.Flash(start: Date(), color: color, count: times)
        if musicOn || liveMood != nil {
            queue.async { [weak self] in self?.overlays.flash = flash }
            return
        }
        let toKeyboard = canWrite
        let total = Double(times) * Overlays.Flash.period
        let correction = settings.ledColorCorrection
        pending += 1
        queue.async { [weak self] in
            guard let self else { return }
            var before: ConfigPage?
            if toKeyboard, let kb = self.keyboard { before = try? self.beginStream(kb, strip: nil) }
            if before != nil { self.pageBeforeMusic = before; self.colorCorrection = correction; self.lastFrame = [] }
            var o = Overlays()
            o.flash = Overlays.Flash(start: Date(), color: color, count: times)
            let start = Date()
            let dark = [UInt8](repeating: 0, count: Keyboard.streamSlots * 3)
            while Date().timeIntervalSince(start) < total {
                let frame = o.apply(dark)
                DispatchQueue.main.async { if !self.musicOn && self.liveMood == nil { self.streamFrame = frame; self.objectWillChange.send() } }
                if before != nil { self.push(frame, failureMessage: "Lost the keyboard while flashing.") }
                Thread.sleep(forTimeInterval: 0.05)
            }
            let page = before != nil ? try? self.endStream() : nil
            DispatchQueue.main.async {
                self.pending -= 1
                if !self.musicOn && self.liveMood == nil { self.streamFrame = nil; self.objectWillChange.send() }
                if let page { self.page = page }
            }
        }
    }

    /// Runs on `queue`: the frame with the bar and any flash on top.
    nonisolated func withOverlays(_ frame: [UInt8]) -> [UInt8] {
        if let (position, duration, at) = nowPlayingState, duration > 0 {
            overlays.progress = min(max((position + Date().timeIntervalSince(at)) / duration, 0), 1)
        } else {
            overlays.progress = nil
        }
        return overlays.apply(frame)
    }

    /// Start or stop the watchers the settings ask for.
    func updateExtras() {
        if settings.nowPlayingBar { nowPlaying.start() } else { nowPlaying.stop() }
        if settings.mailAlerts { mail.start(); badges.start() } else { mail.stop(); badges.stop() }
        if settings.keySounds {
            do {
                try keySounds.load(settings.keySound, file: settings.keySoundFile)
                keySoundError = nil
            } catch {
                keySoundError = settings.keySound == .custom && settings.keySoundFile == nil
                    ? "Choose a sound file." : "Couldn't play that file. Try a .wav, .aiff, .m4a or .mp3."
            }
            keySounds.volume = settings.keySoundVolume
        } else {
            keySounds.stop()
        }
        updateKeyMonitor()
    }

    /// Hear the typing sound once, from the settings.
    func previewKeySound() {
        // Load the sound even while typing sounds are off, so you can hear
        // it before turning them on.
        guard (try? keySounds.load(settings.keySound, file: settings.keySoundFile)) != nil else { return }
        keySounds.volume = settings.keySoundVolume
        keySounds.play(keyCode: 0)
    }

    /// Flash the keyboard and, if allowed, turn the strip the alert colour
    /// until the alert is over or cleared.
    /// With `flashKeys` off only the strip blinks, unless strip alerts are
    /// off, when the keys flash instead.
    func raiseAlert(_ text: String, until: Date?, mail: Bool, flashKeys: Bool = true) {
        if flashKeys || !settings.stripAlerts { flash(color: settings.alertColor, times: settings.alertFlashes) }
        guard settings.stripAlerts else { return }
        if stripAlert == nil {
            stripBeforeAlert = page?.strip
            stripAlertUntil = until
            stripAlertIsMail = mail
            stripAlert = text
        } else {
            // One alert is already waiting: keep whichever lasts longer
            // (no end time means until it's cleared).
            let lastsLonger = until == nil || stripAlertUntil.map { until! >= $0 } == true
            if lastsLonger {
                stripAlert = text
                stripAlertUntil = until
            }
            stripAlertIsMail = stripAlertIsMail || mail
        }
        let alert = ConfigPage.Strip.blinking(settings.stripAlertColor)
        if canWrite, page?.shows(alert) != true { perform { try $0.setStrip(alert) } }
    }

    /// Put the strip back: the current mood's colour, else what it was.
    func clearAlert() {
        guard stripAlert != nil else { return }
        stripAlert = nil
        stripAlertUntil = nil
        let back = musicOn ? strip(for: settings.musicPalette)
            : (liveMood ?? activeMood).flatMap { strip(for: $0) }
        setStrip(back ?? stripBeforeAlert)
        stripBeforeAlert = nil
    }

    /// After a stream ends the keyboard gets its old page back, strip and
    /// all; keep a waiting alert showing.
    func keepAlertStrip() {
        let alert = ConfigPage.Strip.blinking(settings.stripAlertColor)
        guard stripAlert != nil, canWrite, page?.shows(alert) != true else { return }
        perform { try $0.setStrip(alert) }
    }
}
