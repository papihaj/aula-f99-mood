import AppKit
import AVFoundation
import EventKit

// MARK: Now playing

/// Where the song is in Spotify or Music, asked once every couple of seconds
/// by AppleScript (macOS asks once to allow it). Only players that are
/// already running are asked, so it never opens an app.
@MainActor
final class NowPlayingWatcher {
    struct State {
        var position: Double // seconds
        var duration: Double
        var at: Date
        var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
        /// Progress now, carried on from the last reading.
        func progress(at now: Date) -> Double {
            duration > 0 ? min(max((position + now.timeIntervalSince(at)) / duration, 0), 1) : 0
        }
    }

    private(set) var state: State?
    /// Set when macOS refused (Privacy & Security → Automation).
    private(set) var notAllowed = false
    var onChange: ((State?) -> Void)?
    private var timer: Timer?

    private static let players: [(bundle: String, script: String)] = [
        ("com.spotify.client", """
        tell application id "com.spotify.client"
            if player state is playing then
                return ((round ((player position) * 1000)) as text) & "|" & ((duration of current track) as text)
            end if
        end tell
        return ""
        """),
        ("com.apple.Music", """
        tell application id "com.apple.Music"
            if player state is playing then
                return ((round ((player position) * 1000)) as text) & "|" & ((round ((duration of current track) * 1000)) as text)
            end if
        end tell
        return ""
        """),
    ]

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if state != nil { state = nil; onChange?(nil) }
    }

    private func poll() {
        var found: State?
        for player in Self.players where !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundle).isEmpty {
            var error: NSDictionary?
            let result = NSAppleScript(source: player.script)?.executeAndReturnError(&error)
            if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 { notAllowed = true; continue }
            guard let text = result?.stringValue, !text.isEmpty else { continue }
            let parts = text.split(separator: "|").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 {
                notAllowed = false
                found = State(position: parts[0] / 1000, duration: parts[1] / 1000, at: Date())
                break
            }
        }
        state = found
        onChange?(found)
    }
}

// MARK: Mail

/// How many unread messages Mail's inbox has, asked every 30 seconds by
/// AppleScript, only while Mail is open. Calls back when the number goes up.
@MainActor
final class MailWatcher {
    var onNewMail: ((Int) -> Void)?
    private(set) var notAllowed = false
    private var timer: Timer?
    private var lastCount: Int?

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastCount = nil
    }

    private func poll() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else { return }
        var error: NSDictionary?
        let result = NSAppleScript(source: #"tell application id "com.apple.mail" to return unread count of inbox"#)?
            .executeAndReturnError(&error)
        if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 { notAllowed = true; return }
        guard let count = result.map({ Int($0.int32Value) }) else { return }
        notAllowed = false
        if let last = lastCount, count > last { onNewMail?(count - last) }
        lastCount = count
    }
}

// MARK: Calendar

/// Finds calendar events that are about to start. Reads only start times,
/// on this Mac; nothing is stored or sent.
final class CalendarWatcher {
    private let store = EKEventStore()
    private var alerted = Set<String>()

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var allowed: Bool { status == .fullAccess }

    func requestAccess(_ done: @escaping @Sendable (Bool) -> Void) {
        store.requestFullAccessToEvents { ok, _ in DispatchQueue.main.async { done(ok) } }
    }

    /// Events that start within `minutesBefore` minutes (or started in the
    /// last minute) and haven't been alerted yet. Each is returned once.
    func due(minutesBefore: Int, now: Date = Date()) -> [EKEvent] {
        guard Self.allowed else { return [] }
        let lead = Double(minutesBefore) * 60
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60),
                                                 end: now.addingTimeInterval(lead + 1), calendars: nil)
        var fresh: [EKEvent] = []
        for event in store.events(matching: predicate) where !event.isAllDay {
            guard let start = event.startDate, start >= now.addingTimeInterval(-60), start <= now.addingTimeInterval(lead + 1)
            else { continue }
            let key = "\(event.eventIdentifier ?? event.title ?? "")@\(start.timeIntervalSince1970)"
            if alerted.insert(key).inserted { fresh.append(event) }
        }
        if alerted.count > 500 { alerted.removeAll() }
        return fresh
    }

    /// The next event today, for the settings screen.
    func nextEvent(now: Date = Date()) -> EKEvent? {
        guard Self.allowed else { return nil }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        return store.events(matching: predicate).filter { !$0.isAllDay && $0.startDate >= now }
            .min { $0.startDate < $1.startDate }
    }
}

// MARK: Typing sounds

/// Plays a short sound for each key press. The built-in sounds are made
/// here from sine waves and noise, so there are no recordings to license;
/// you can also pick your own sound file.
@MainActor
final class KeySoundPlayer {
    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var next = 0
    private var normal: [AVAudioPCMBuffer] = []
    private var big: [AVAudioPCMBuffer] = []
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private(set) var loadedSound: KeySound?
    private(set) var loadedFile: String?

    init() {
        for _ in 0..<8 {
            let v = AVAudioPlayerNode()
            engine.attach(v)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            voices.append(v)
        }
        // Headphones plugged in or out: the engine stops; start it again.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { try? self?.engine.start() }
        }
    }

    var volume: Double = 0.5 { didSet { engine.mainMixerNode.outputVolume = Float(volume) } }

    /// Load a sound. Throws if your own file can't be read.
    func load(_ sound: KeySound, file: String?) throws {
        guard sound != loadedSound || file != loadedFile else { return }
        if sound == .custom {
            guard let file else { throw CocoaError(.fileNoSuchFile) }
            let buffer = try Self.read(URL(fileURLWithPath: file), into: format)
            normal = [buffer]
            big = [buffer]
        } else {
            normal = [0.94, 0.98, 1.02, 1.06].enumerated().map { i, p in synth(sound, pitch: p, big: false, seed: i) }
            big = [0.97, 1.03].enumerated().map { i, p in synth(sound, pitch: p, big: true, seed: i + 10) }
        }
        loadedSound = sound
        loadedFile = file
    }

    /// `keyCode` picks a deeper sound for Space, Return and Delete.
    func play(keyCode: UInt16) {
        let isBig = [49, 36, 51, 76].contains(keyCode)
        let pool = isBig ? big : normal
        guard !pool.isEmpty else { return }
        if !engine.isRunning {
            engine.mainMixerNode.outputVolume = Float(volume)
            do { try engine.start() } catch { return }
        }
        let voice = voices[next]
        next = (next + 1) % voices.count
        voice.stop()
        voice.scheduleBuffer(pool.randomElement()!, at: nil, options: .interrupts)
        voice.play()
    }

    func stop() {
        voices.forEach { $0.stop() }
        engine.stop()
    }

    private static func read(_ url: URL, into format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(min(file.length, Int64(file.processingFormat.sampleRate))) // at most 1 s
        guard frames > 0, let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: source, frameCount: frames)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw CocoaError(.fileReadCorruptFile) }
        let capacity = AVAudioFrameCount(Double(frames) * format.sampleRate / file.processingFormat.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw CocoaError(.fileReadCorruptFile) }
        var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return source
        }
        if let error { throw error }
        return out
    }

    private func synth(_ sound: KeySound, pitch p: Double, big: Bool, seed: Int) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let length: Double = switch sound {
        case .thock: big ? 0.11 : 0.07
        case .click: big ? 0.06 : 0.04
        case .typewriter: big ? 0.8 : 0.12
        case .bubble: big ? 0.12 : 0.08
        case .custom: 0.05
        }
        let n = Int(length * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        let out = buffer.floatChannelData![0]
        var rng = UInt64(0x9e3779b97f4a7c15) &+ UInt64(seed) &* 0x2545f4914f6cdd1d
        func noise() -> Double {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return Double(rng % 20_000) / 10_000 - 1
        }
        let low = big ? 0.75 : 1.0
        var lp = 0.0, prev = 0.0, phase = 0.0
        var peak = 0.0
        var samples = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            var s = 0.0
            switch sound {
            case .thock:
                let r = noise()
                lp += (r - lp) * 0.12
                s = 0.6 * sin(2 * .pi * 150 * p * low * t) * exp(-t / 0.012)
                    + 0.5 * lp * exp(-t / 0.005)
                    + 0.2 * sin(2 * .pi * 420 * p * low * t) * exp(-t / 0.008)
            case .click:
                let r = noise()
                let hp = r - prev
                prev = r
                s = 0.6 * hp * exp(-t / 0.0025) + 0.3 * sin(2 * .pi * 3200 * p * t) * exp(-t / 0.003)
                // The key coming back up, a moment later.
                let u = t - 0.018
                if u > 0 { s += 0.25 * hp * exp(-u / 0.002) }
            case .typewriter:
                let r = noise()
                s = 0.7 * r * exp(-t / 0.002)
                    + 0.25 * (sin(2 * .pi * 1800 * p * t) + 0.5 * sin(2 * .pi * 2950 * p * t)) * exp(-t / 0.03)
                    + 0.4 * sin(2 * .pi * 220 * p * low * t) * exp(-t / 0.01)
                if big { // the bell at the end of the line
                    let u = max(0, t - 0.03)
                    s += 0.35 * (sin(2 * .pi * 2093 * u) + 0.4 * sin(2 * .pi * 4186 * u)) * exp(-u / 0.25) * (t > 0.03 ? 1 : 0)
                }
            case .bubble:
                let f = (500 + 600 * (t / length)) * p * low
                phase += 2 * .pi * f / rate
                s = sin(phase) * sin(.pi * t / length) * exp(-t / 0.04)
            case .custom:
                s = 0
            }
            samples[i] = s
            peak = max(peak, abs(s))
        }
        let gain = peak > 0 ? 0.8 / peak : 0
        for i in 0..<n {
            // Short fade-out so the end never clicks.
            let tail = min(1, Double(n - i) / (0.004 * rate))
            out[i] = Float(samples[i] * gain * tail)
        }
        return buffer
    }
}
