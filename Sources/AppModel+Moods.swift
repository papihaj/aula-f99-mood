import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import SwiftUI

// Managing moods: new, remix, revert, delete, import and export.
@MainActor
extension AppModel {
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
        // Forget anything that points at the old moods.
        remixOriginals = [:]
        appMoodID = nil
        moodBeforeApp = nil
        var fresh = AppSettings.defaults
        fresh.welcomeDone = true
        settings = fresh
        applyDockSetting()
    }

    // MARK: New moods

    /// Start a new mood in the editor. Its effect can be a keyboard or a
    /// live one; you pick in the editor.
    func startNewMood() {
        var mood = Mood(name: "New mood", emoji: "", lighting: .init(effect: 2, brightness: 3, speed: 2, color: 5), hotkey: nil)
        var name = mood.name, n = 2
        while settings.moods.contains(where: { $0.name == name }) { name = "\(mood.name) \(n)"; n += 1 }
        mood.name = name
        moodBeforeNew = settings.activeMoodID
        newMood = mood
    }

    /// Keep the new mood, and show it.
    func createNewMood() {
        guard let mood = newMood else { return }
        newMood = nil
        settings.moods.append(mood)
        apply(mood)
    }

    /// Throw the new mood away. If you tried it on the keyboard, the mood
    /// from before comes back.
    func cancelNewMood() {
        guard let mood = newMood else { return }
        newMood = nil
        guard settings.activeMoodID == mood.id else { return }
        if let before = settings.moods.first(where: { $0.id == moodBeforeNew }) { apply(before) } else { turnOff() }
    }

    // MARK: Remix

    /// Change the colours of a mood that's on, keeping a copy to go back to.
    func remix(_ id: UUID, _ change: (inout Mood) -> Void) {
        guard let i = settings.moods.firstIndex(where: { $0.id == id }) else { return }
        if remixOriginals[id] == nil { remixOriginals[id] = settings.moods[i] }
        change(&settings.moods[i])
    }

    func revertRemix(_ id: UUID) {
        guard let original = remixOriginals[id], let i = settings.moods.firstIndex(where: { $0.id == id }) else { return }
        var m = settings.moods[i]
        m.lighting.color = original.lighting.color
        m.paletteName = original.paletteName
        m.paint = original.paint
        m.paintBase = original.paintBase
        settings.moods[i] = m
        remixOriginals[id] = nil
    }

    /// Whether a mood has something to undo: a remix, or changes to a
    /// built-in mood.
    func canRevert(_ mood: Mood) -> Bool { remixOriginals[mood.id] != nil || mood.changedFromBuiltIn }

    /// Undo changes to a mood: a built-in mood goes back to how it came,
    /// any other mood loses its remix.
    func revert(_ id: UUID) {
        guard let i = settings.moods.firstIndex(where: { $0.id == id }) else { return }
        if settings.moods[i].changedFromBuiltIn {
            remixOriginals[id] = nil
            settings.moods[i] = settings.moods[i].revertedToBuiltIn()
        } else {
            revertRemix(id)
        }
    }

    /// Move a mood one place earlier or later among the tiles of its kind.
    func moveMood(_ id: UUID, by step: Int) {
        let moods = settings.moods
        guard let i = moods.firstIndex(where: { $0.id == id }) else { return }
        let live = moods[i].live != nil
        var j = i + step
        while moods.indices.contains(j), (moods[j].live != nil) != live || moods[j].hidden { j += step }
        guard moods.indices.contains(j) else { return }
        settings.moods.swapAt(i, j)
    }

    /// Keep a remix: it stays, with nothing left to revert to.
    func keepRemix(_ id: UUID) { remixOriginals[id] = nil }

    /// Paint the picked keys (nil takes their paint off). Moods the keyboard
    /// draws itself can't light single keys, so painting one starts a
    /// painted mood in its colour.
    func paintSelectedKeys(_ color: RGB?) {
        guard !selectedKeys.isEmpty, !musicOn else { return }
        var target = liveMood ?? activeMood
        if target?.live == nil {
            guard color != nil else { return }
            var mood = Mood(name: "My keys", emoji: "", lighting: .init(effect: 1, brightness: 4, speed: 0, color: F99.colorful),
                            hotkey: nil, live: .painted)
            if let l = activeMood?.lighting, l.brightness > 0, F99.effect(l.effect)?.hasColor != false,
               let c = F99.colors.first(where: { $0.id == l.color }) {
                mood.paintBase = RGB(c.rgb.0 * 0.4, c.rgb.1 * 0.4, c.rgb.2 * 0.4)
            } else {
                mood.paintBase = RGB(hex: 0x1a0640)
            }
            var name = mood.name, n = 2
            while settings.moods.contains(where: { $0.name == name }) { name = "My keys \(n)"; n += 1 }
            mood.name = name
            settings.moods.append(mood)
            apply(mood)
            target = mood
        }
        guard let id = target?.id else { return }
        let keys = selectedKeys
        remix(id) { m in for led in keys { m.paint[String(led)] = color } }
    }

    /// Keep the remix as a new mood and put the original back as it was.
    @discardableResult
    func saveRemix(_ id: UUID) -> Mood? {
        guard let i = settings.moods.firstIndex(where: { $0.id == id }) else { return nil }
        var name = settings.moods[i].name + " Remix"
        var n = 2
        while settings.moods.contains(where: { $0.name == name }) { name = settings.moods[i].name + " Remix \(n)"; n += 1 }
        let copy = settings.moods[i].copy(named: name)
        var s = settings
        if let original = remixOriginals[id] { s.moods[i] = original }
        s.moods.insert(copy, at: i + 1)
        s.activeMoodID = copy.id
        remixOriginals[id] = nil
        settings = s
        apply(copy)
        return copy
    }
}
