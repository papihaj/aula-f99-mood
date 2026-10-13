import Accelerate
import Foundation

// Design notes. The approach follows what established music-light projects do:
// - WLED sound reactive (github.com/wled/WLED, usermods/audioreactive): pink-noise
//   tilt so treble shows up, a squelch gate that freezes auto-gain in silence.
// - scottlawsonbc/audio-reactive-led-strip and LedFx: separate rise/fall
//   smoothing, a dark floor so peaks read as peaks, "scroll" (Wave) effect.
// - Onset detection by spectral flux (Bello et al.; Dixon, "Onset Detection
//   Revisited"), which catches soft onsets that a bass-energy ratio misses.
// - Nanoleaf Rhythm "Fireworks"; stage lighting practice of keeping big moments
//   for drops.
// - WCAG 2.3.1: no more than three flashes in any one second.
// - Oklab (bottosson.github.io/posts/oklab) for even-looking colour blends.

enum MusicStyle: String, Codable, CaseIterable, Identifiable {
    case spectrum = "Spectrum"
    case pulse = "Pulse"
    case ripples = "Ripples"
    case wave = "Wave"
    case fireworks = "Fireworks"
    var id: String { rawValue }

    var summary: String {
        switch self {
        case .spectrum: return "Bass on the left, treble on the right, bouncing like an equaliser"
        case .pulse: return "The whole keyboard breathes with the bass and sparks on big beats"
        case .ripples: return "Each beat sends a soft ring of colour across the keys"
        case .wave: return "Colour flows outward from the middle of the keyboard, in time with the music"
        case .fireworks: return "Keys pop and fade on the beat; the treble adds sparkles"
        }
    }
}

enum MusicInput: String, Codable, CaseIterable, Identifiable {
    case system = "Sound playing on this Mac"
    case microphone = "Microphone"
    var id: String { rawValue }
}

/// What the music is doing right now. Values are 0...1 unless noted.
struct MusicSnapshot {
    /// 16 bands, bass first, already compressed for display.
    var bands: [Float]
    /// Overall loudness.
    var level: Float
    /// Smoothed bass, for brightness.
    var bass: Float
    /// A new beat or hit started this frame.
    var beat: Bool
    /// How strong that hit was.
    var strength: Float = 1
    /// How loud this moment is compared with the last ~10 s: around 0.5 is
    /// normal, near 1 is a drop or chorus, near 0 is a quiet passage.
    var intensity: Float = 0.5
    /// No music playing (below the noise gate).
    var silent: Bool = false
    /// Balance of the sound: 0 bass-heavy, 1 bright and trebly.
    var brightness: Float = 0.5
    /// Estimated tempo, or 0 while it's still unsure.
    var bpm: Float = 0
    /// Where we are between beats, 0 at a beat rising to 1 just before the
    /// next. Keeps ticking in time between detected beats once the tempo is known.
    var beatPhase: Float = 0
    /// Which beat of a four-beat bar this is (0-3).
    var barBeat: Int = 0
}

/// Turns raw samples into frequency bands, loudness and beats.
final class MusicAnalyzer {
    static let bandCount = 16
    private let size = 2048
    private let log2n: vDSP_Length = 11
    private let fft: FFTSetup
    private let window: [Float]
    /// Seconds since the previous call.
    private var dt: Float
    /// The analyzer's own clock, in seconds.
    private var clock: Double = 0
    private var lastTime: Double = 0

    private var smoothed = [Float](repeating: 0, count: bandCount)
    private var previousDB = [Float](repeating: -120, count: bandCount)
    private var peakDB: Float = -30
    /// The loudest the music has been for a while; caps how far the
    /// automatic gain can turn quiet music up.
    private var longPeakDB: Float = -30
    private var fluxHistory: [Float] = []
    private var lastBeat: Double = -1
    private var beatTimes: [Double] = []
    private var period: Double = 0.5
    private var tempoKnown = false
    private var beatPhase: Double = 0
    private var beatCount = 0
    private var levelPeak: Float = 0.05
    private var bassEnv: Float = 0
    private var shortDB: Float = -60
    private var longDB: Float = -60
    private var gateOpen = false

    /// Below this RMS level the music counts as silence (noise gate).
    private let squelch: Float = 0.0015

    /// `hop` is the time between calls. The app calls about 80 times a second
    /// so beats land within ~12 ms, while the lights update 20 times a second.
    init(hop: Float = 0.05) {
        dt = hop
        fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
    }

    deinit { vDSP_destroy_fftsetup(fft) }

    /// Exponential smoothing factor for a time constant of `tau` seconds.
    private func keep(_ tau: Float) -> Float { exp(-dt / tau) }

    private var historyLength: Int { max(8, Int(1.5 / dt)) }

    /// `time` is a real clock reading in seconds (the app passes the system
    /// uptime). Without it, each call counts as exactly one hop, which is what
    /// the tests use.
    func analyze(_ samples: [Float], sampleRate: Double, time: Double? = nil) -> MusicSnapshot {
        if let time {
            if lastTime > 0 { dt = Float(min(max(time - lastTime, 0.002), 0.1)) }
            lastTime = time
        }
        clock += Double(dt)
        advanceTempo()
        guard samples.count == size else {
            return MusicSnapshot(bands: smoothed, level: 0, bass: 0, beat: false, silent: true)
        }
        let rms = sqrt(vDSP.meanSquare(samples))

        // Noise gate with a little hysteresis, so it doesn't chatter.
        gateOpen = gateOpen ? rms > squelch * 0.7 : rms > squelch
        guard gateOpen else {
            // Silence: let everything fade over a second or so, and freeze the
            // automatic gain so it doesn't crank up the background hiss.
            for b in 0..<Self.bandCount { smoothed[b] *= keep(0.6) }
            bassEnv *= keep(0.6)
            // Silence has no onsets; and when the music comes back, its first
            // hit should count as one.
            fluxHistory.append(0)
            if fluxHistory.count > historyLength { fluxHistory.removeFirst() }
            previousDB = [Float](repeating: -120, count: Self.bandCount)
            return MusicSnapshot(bands: smoothed, level: 0, bass: bassEnv, beat: false,
                                 strength: 0, intensity: 0.3, silent: true,
                                 bpm: tempoKnown ? Float(60 / period) : 0, beatPhase: Float(beatPhase), barBeat: beatCount % 4)
        }

        let mags = spectrum(samples)

        // 16 bands spaced evenly in pitch from 40 Hz to 12 kHz, tilted up
        // 3 dB per octave so the treble isn't drowned out by the bass
        // (music, like pink noise, has much less energy up there).
        // A source that reports no sample rate would divide by zero below.
        let binHz = Float(sampleRate > 0 ? sampleRate : 48_000) / Float(size)
        var db = [Float](repeating: -120, count: Self.bandCount)
        var weightedSum: Float = 0, total: Float = 0
        for b in 0..<Self.bandCount {
            let lo = 40 * pow(300, Float(b) / Float(Self.bandCount))
            let hi = 40 * pow(300, Float(b + 1) / Float(Self.bandCount))
            let first = max(1, Int(lo / binHz))
            let last = min(mags.count - 1, max(first, Int(hi / binHz)))
            let energy = mags[first...last].reduce(0, +) / Float(last - first + 1)
            let tilt = 10 * log10(sqrt(lo * hi) / 40) // +3 dB per octave
            db[b] = 10 * log10(energy + 1e-12) + tilt
            // For the treble/bass balance, weight each band by its tilted energy.
            let tilted = energy * sqrt(lo * hi) / 40
            weightedSum += Float(b) * tilted
            total += tilted
        }


        // Automatic gain against a slowly falling peak, but never more than
        // 24 dB above the loudest the song has been lately, so quiet parts
        // stay quiet instead of being blown up to full brightness.
        let loudest = db.max() ?? -120
        longPeakDB = max(loudest, longPeakDB - 0.4 * dt)   // falls 0.4 dB a second
        peakDB = max(loudest, peakDB - 3 * dt, longPeakDB - 24) // falls 3 dB a second
        // Onset strength: how much the bass and low-mid bands jumped since the
        // last call (half-wave rectified spectral flux). Each band is floored
        // 30 dB below the current peak, so a big relative jump in a nearly
        // silent band (a hi-hat's faint low end, background noise) doesn't
        // count. Higher bands count only a little, so hi-hats and cymbals
        // don't register as beats; they show in the treble bars instead.
        let floored = db.map { max($0, peakDB - 30) }
        var flux: Float = 0
        for b in 0..<Self.bandCount {
            let rise = max(0, floored[b] - previousDB[b])
            flux += b < 6 ? rise : rise * 0.05
        }
        previousDB = floored

        let range: Float = 36
        for b in 0..<Self.bandCount {
            var x = min(max((db[b] - (peakDB - range)) / range, 0), 1)
            x = x * x * 0.4 + x * 0.6 // a touch of contrast so bars don't all sit high
            // Jump up at once, fall back over about a quarter of a second.
            smoothed[b] = x > smoothed[b] ? x : smoothed[b] * keep(0.25) + x * (1 - keep(0.25))
        }

        levelPeak = max(rms, levelPeak * keep(10), 0.01)
        let level = min(rms / levelPeak, 1)

        // Short-term (0.5 s) against long-term (10 s) loudness: is this a quiet
        // passage, a normal one, or a drop?
        let nowDB = 20 * log10(rms + 1e-9)
        shortDB = shortDB * keep(0.5) + nowDB * (1 - keep(0.5))
        longDB = longDB * keep(10) + nowDB * (1 - keep(10))
        let intensity = min(max(0.5 + (shortDB - longDB) / 12, 0), 1)

        // Beat: flux clearly above its recent typical value (median plus
        // spread over the last ~1.5 s), at most one every 0.22 s.
        fluxHistory.append(flux)
        if fluxHistory.count > historyLength { fluxHistory.removeFirst() }
        let sorted = fluxHistory.sorted()
        let median = sorted[sorted.count / 2]
        let spread = sorted.map { abs($0 - median) }.reduce(0, +) / Float(sorted.count)
        // Shorter hops see smaller jumps per call, so the fixed margin scales with the hop.
        let threshold = median + 1.5 * spread + 3 * dt / 0.05
        let beat = fluxHistory.count > 4 && flux > threshold && (lastBeat < 0 || clock - lastBeat > 0.22)
        if beat { registerBeat() }
        let strength = beat ? min((flux - threshold) / (threshold + 1) + 0.4, 1) : 0

        let bass = max(smoothed[0], smoothed[1], smoothed[2])
        bassEnv = bass > bassEnv ? bass : bassEnv * keep(0.4) + bass * (1 - keep(0.4))

        return MusicSnapshot(bands: smoothed, level: level, bass: bassEnv, beat: beat,
                             strength: strength, intensity: intensity, silent: false,
                             brightness: total > 0 ? min(weightedSum / total / Float(Self.bandCount - 1), 1) : 0.5,
                             bpm: tempoKnown ? Float(60 / period) : 0, beatPhase: Float(beatPhase), barBeat: beatCount % 4)
    }

    // MARK: Tempo

    /// Tick the beat clock forward. Between detected beats it keeps time on
    /// its own, so motion can stay on the beat through quieter bars.
    private func advanceTempo() {
        beatPhase += Double(dt) / period
        if beatPhase >= 1 {
            beatPhase -= 1
            beatCount += 1
        }
    }

    /// A beat was detected: update the tempo estimate and pull the beat clock
    /// towards it (a simple phase-locked loop).
    private func registerBeat() {
        lastBeat = clock
        beatTimes.append(clock)
        beatTimes.removeAll { clock - $0 > 8 }

        // Tempo: the typical gap between beats over the last 8 s, folded into
        // 70-180 BPM so half- and double-time hits agree.
        let gaps = zip(beatTimes.dropFirst(), beatTimes).map { $0 - $1 }.filter { $0 > 0.2 && $0 < 2 }
        if gaps.count >= 4 {
            var g = gaps.sorted()[gaps.count / 2]
            while g < 60.0 / 180 { g *= 2 }
            while g > 60.0 / 70 { g /= 2 }
            period = tempoKnown ? period * 0.8 + g * 0.2 : g
            tempoKnown = true
        }

        if tempoKnown {
            // How far off the clock was: nudge it halfway to the beat. A
            // beat near the end of a cycle counts as the next one arriving early.
            let error = beatPhase > 0.5 ? beatPhase - 1 : beatPhase
            if error < 0 { beatCount += 1 }
            beatPhase = max(0, beatPhase - error * 0.5 - (error < 0 ? -1 : 0)).truncatingRemainder(dividingBy: 1)
        } else {
            beatPhase = 0
            beatCount += 1
        }
    }

    private func spectrum(_ samples: [Float]) -> [Float] {
        let windowed = vDSP.multiply(samples, window)
        var mags = [Float](repeating: 0, count: size / 2)
        var real = [Float](repeating: 0, count: size / 2)
        var imag = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(size / 2))
            }
        }
        return mags
    }
}

/// A colour, 0...1 per channel (sRGB).
struct RGB: Codable, Hashable {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) {
        self.init(Double(hex >> 16 & 0xff) / 255, Double(hex >> 8 & 0xff) / 255, Double(hex & 0xff) / 255)
    }

    /// Blend towards `o`. Done in Oklab, where equal steps look equal, so a
    /// blue-to-white blend doesn't drift purple and midpoints don't go muddy.
    func mixed(with o: RGB, _ t: Double) -> RGB {
        if t <= 0 { return self }
        if t >= 1 { return o }
        let a = oklab, b = o.oklab
        return RGB(oklab: (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t))
    }

    private static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    private static func toSRGB(_ c: Double) -> Double {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }

    var oklab: (Double, Double, Double) {
        let r = Self.toLinear(self.r), g = Self.toLinear(self.g), b = Self.toLinear(self.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    init(oklab lab: (Double, Double, Double)) {
        let l = pow(lab.0 + 0.3963377774 * lab.1 + 0.2158037573 * lab.2, 3)
        let m = pow(lab.0 - 0.1055613458 * lab.1 - 0.0638541728 * lab.2, 3)
        let s = pow(lab.0 - 0.0894841775 * lab.1 - 1.2914855480 * lab.2, 3)
        self.init(Self.toSRGB(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                  Self.toSRGB(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                  Self.toSRGB(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    /// The same hue, scaled up so its strongest channel is at least `peak`.
    /// Used by "Keep every key lit" so a near-black colour (Matrix's dark
    /// green) still shows as a readable green rather than staying dark.
    func atLeast(peak: Double) -> RGB {
        let m = max(r, g, b)
        guard m > 0.001, m < peak else { return self }
        return RGB(r * peak / m, g * peak / m, b * peak / m)
    }

    /// Weighted brightness, 0...1, as the eye sees it.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// The same lightness and strength, turned round the colour wheel by
    /// `turn` (0...1 is a full circle).
    func hueRotated(_ turn: Double) -> RGB {
        let (l, a, b) = oklab
        let angle = turn * 2 * .pi
        return RGB(oklab: (l, a * cos(angle) - b * sin(angle), a * sin(angle) + b * cos(angle)))
    }
}

/// The colours music mode paints with.
struct MusicPalette: Codable, Hashable, Identifiable {
    var name: String
    var colors: [RGB]
    var id: String { name }

    /// Electric, arranged the way the research suggests: deep blue and violet
    /// as the body, cyan for highs and hits, magenta as the accent for drops.
    static let electric = MusicPalette(name: "Electric", colors: [
        RGB(hex: 0x2962ff), RGB(hex: 0x7c4dff), RGB(hex: 0x00e5ff), RGB(hex: 0xd500f9)])
    static let presets: [MusicPalette] = [
        electric,
        MusicPalette(name: "Neon", colors: [RGB(hex: 0xff2bd6), RGB(hex: 0x39ff14), RGB(hex: 0x00f0ff)]),
        neonElectric,
        MusicPalette(name: "Fire", colors: [RGB(hex: 0xff1100), RGB(hex: 0xff6a00), RGB(hex: 0xffd000)]),
        MusicPalette(name: "Ocean", colors: [RGB(hex: 0x0033ff), RGB(hex: 0x00a6ff), RGB(hex: 0x00ffc8)]),
        MusicPalette(name: "Sunset", colors: [RGB(hex: 0x7a00ff), RGB(hex: 0xff2d75), RGB(hex: 0xff9a00)]),
        MusicPalette(name: "Classic", colors: [RGB(hex: 0x00ff00), RGB(hex: 0xffff00), RGB(hex: 0xff0000)]),
        MusicPalette(name: "Rainbow", colors: [RGB(hex: 0xff0000), RGB(hex: 0xffff00), RGB(hex: 0x00ff00),
                                               RGB(hex: 0x00ffff), RGB(hex: 0x0000ff), RGB(hex: 0xff00ff)]),
    ]
    static let customName = "Custom"

    /// Electric and Neon together, ordered so they flow into each other:
    /// cyan, blue, violet, magenta, hot pink, neon green.
    static let neonElectric = MusicPalette(name: "Neon Electric", colors: [
        RGB(hex: 0x00e5ff), RGB(hex: 0x2962ff), RGB(hex: 0x7c4dff), RGB(hex: 0xd500f9),
        RGB(hex: 0xff2bd6), RGB(hex: 0x39ff14)])

    /// A point along the palette. `t` 0 is the first colour and 1 the last.
    /// With `wrap`, it loops back round to the first colour instead.
    func sample(_ t: Double, wrap: Bool) -> RGB {
        guard colors.count > 1 else { return colors.first ?? RGB(1, 1, 1) }
        if wrap {
            let u = (t.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * Double(colors.count)
            let i = Int(u) % colors.count
            return colors[i].mixed(with: colors[(i + 1) % colors.count], u - floor(u))
        }
        let u = min(max(t, 0), 1) * Double(colors.count - 1)
        let i = min(Int(u), colors.count - 2)
        return colors[i].mixed(with: colors[i + 1], u - Double(i))
    }

    /// Colours for music mode that match a mood: shades of the mood's colour,
    /// or the rainbow for colourful moods and effects that pick their own.
    static func forMood(_ mood: Mood) -> MusicPalette {
        let effect = F99.effect(mood.lighting.effect)
        guard effect?.hasColor != false, let c = F99.colors.first(where: { $0.id == mood.lighting.color }) else {
            return MusicPalette(name: mood.name, colors: presets.first { $0.name == "Rainbow" }!.colors)
        }
        let base = RGB(c.rgb.0, c.rgb.1, c.rgb.2)
        let deep = RGB(oklab: { let l = base.oklab; return (l.0 * 0.55, l.1, l.2) }())
        return MusicPalette(name: mood.name, colors: [deep, base, base.mixed(with: RGB(1, 1, 1), 0.5)])
    }

    /// The light strip's colour for this palette: the firmware colour nearest
    /// its main (first) colour.
    var stripColor: Int { F99.nearestColor(colors.first ?? RGB(1, 1, 1)) }
    /// One colour: the strip in that colour. Several: the strip's own gradient.
    var strip: ConfigPage.Strip { colors.count > 1 ? .gradient : .steady(stripColor) }

    /// The palette's last colour: kept back as the accent for big moments.
    var accent: RGB { colors.last ?? RGB(1, 1, 1) }
}

/// Paints one frame of key colours from the music.
final class MusicRenderer {
    var style: MusicStyle = .spectrum
    var palette: MusicPalette = .electric
    /// Fewer, gentler flashes: no white strikes, softer beats, slower changes.
    var reducedFlashing = false
    /// The dimmest any key may get ("Keep every key lit").
    var minimumBrightness = 0.0
    /// Overall brightness, 0...1. A mood picked while music plays sets this
    /// (Cozy dances dim, Party at full).
    var brightnessScale = 1.0

    /// Keys never go above this (the keyboard sits in front of your eyes for
    /// hours, so full power is tiring).
    static let maxBrightness = 0.8
    /// WCAG 2.3.1: no more than three flashes in any one second.
    static let minFlashGap: TimeInterval = 0.34

    /// Where in the palette the board is; drifts slowly, steps on beats.
    private var phase: Double = Double.random(in: 0..<1)
    private var flash: Double = 0
    private var lastBigFlash = Date.distantPast
    /// White strikes so far (for tests).
    private(set) var bigFlashCount = 0
    private var whiteStrike: Double = 0
    private var idle: Double = 1
    private var ripples: [(x: Double, y: Double, born: Date, phase: Double, strength: Double)] = []
    private var sparks: [(x: Double, y: Double, born: Date, color: RGB, strength: Double, life: Double)] = []
    /// Wave: colours injected at the centre, newest first.
    private var wave: [(RGB, Double)] = []
    private var previous: [Double] = []

    /// R, G, B for every LED slot, ready for `Keyboard.stream`.
    func render(_ m: MusicSnapshot, now: Date = Date()) -> [UInt8] {
        step(m, now)
        var values = [Double](repeating: 0, count: Keyboard.streamSlots * 3)
        for key in F99.keys where key.led < Keyboard.streamSlots {
            var (c, v) = color(for: key, m, now)
            // In silence, fade into a dim, slowly breathing palette glow.
            if idle > 0 {
                let breathe = 0.06 + 0.03 * sin(now.timeIntervalSinceReferenceDate * 1.1 + key.x * 2)
                let idleColor = palette.sample(key.x * 0.6 + phase, wrap: true)
                c = c.mixed(with: idleColor, idle)
                v = v * (1 - idle) + breathe * idle
            }
            // A short white strike on top, only at drops.
            if whiteStrike > 0.01 { c = c.mixed(with: RGB(1, 1, 1), whiteStrike * 0.6) }
            if minimumBrightness > 0 { c = c.atLeast(peak: 0.7) }
            v = minimumBrightness + (1 - minimumBrightness) * min(max(v, 0), 1)
            let level = v * Self.maxBrightness * brightnessScale
            values[key.led * 3] = c.r * level
            values[key.led * 3 + 1] = c.g * level
            values[key.led * 3 + 2] = c.b * level
        }
        limitBoardSwing(&values)
        return values.map { UInt8(min(max($0, 0), 1) * 255) }
    }

    /// Advance all the timers and envelopes by one frame.
    private func step(_ m: MusicSnapshot, _ now: Date) {
        let silent = m.silent
        idle = silent ? min(idle + 0.05 / 1.5, 1) : max(idle - 0.05 / 0.3, 0)

        let calm = reducedFlashing ? 0.5 : 1.0
        // Colour moves a little on every beat and takes a bigger step at the
        // start of each four-beat bar, so changes land on the music's phrasing.
        let barStart = m.beat && m.barBeat == 0 && m.bpm > 0
        let step = m.beat ? (barStart ? 0.12 : 0.03) * Double(m.strength) * calm : 0
        phase = (phase + 0.0015 + step).truncatingRemainder(dividingBy: 1)
        // Beat flash falls away fast (about 0.1 s).
        flash = m.beat ? max(flash, Double(m.strength) * calm) : flash * 0.6

        // White strikes: only on strong hits during a drop, and never more
        // than three big flashes a second.
        let drop = m.intensity > 0.72
        if !reducedFlashing, m.beat, drop, m.strength > 0.6, now.timeIntervalSince(lastBigFlash) >= Self.minFlashGap {
            whiteStrike = 1
            lastBigFlash = now
            bigFlashCount += 1
        } else {
            whiteStrike *= 0.5
        }

        if m.beat && style == .ripples {
            let key = F99.keys.randomElement()!
            ripples.append((key.x, key.y, now, phase, Double(m.strength)))
            if ripples.count > 4 { ripples.removeFirst() }
        }
        ripples.removeAll { now.timeIntervalSince($0.born) > 1.4 }

        if style == .fireworks {
            if m.beat {
                // Busier sections get more fireworks per beat.
                let count = 1 + Int(Double(m.strength) * (2 + 4 * Double(m.intensity)))
                for _ in 0..<count {
                    let key = F99.keys.randomElement()!
                    sparks.append((key.x, key.y, now, palette.sample(Double.random(in: 0..<1), wrap: true),
                                   Double(m.strength), 0.7))
                }
            }
            // Treble sparkles: tiny short-lived pops, more when it's bright.
            let highs = Double(m.bands[11...].max() ?? 0)
            if !m.silent, Double.random(in: 0..<1) < highs * 0.6 {
                let key = F99.keys.randomElement()!
                sparks.append((key.x, key.y, now, palette.sample(0.66, wrap: false), 0.35, 0.3))
            }
            sparks.removeAll { now.timeIntervalSince($0.born) > $0.life * 2.5 }
            if sparks.count > 40 { sparks.removeFirst(sparks.count - 40) }
        }

        if style == .wave {
            // Inject a colour picked by how bright the sound is, with a
            // brightness from the bass and the hits, then let it travel out.
            let c = palette.sample(Double(m.brightness) * 0.8 + phase * 0.3, wrap: true)
            // A small push on every beat of the tempo keeps the flow moving in
            // time, even through softer bars.
            let tick = m.bpm > 0 ? pow(1 - Double(m.beatPhase), 4) * 0.2 : 0
            let v = m.silent ? 0 : 0.12 + 0.55 * Double(m.bass) + 0.4 * flash + tick
            wave.insert((c, v), at: 0)
            if wave.count > 24 { wave.removeLast() }
        }
    }

    private func color(for key: F99.Key, _ m: MusicSnapshot, _ now: Date) -> (RGB, Double) {
        switch style {
        case .spectrum:
            let band = min(Int(key.x * Double(MusicAnalyzer.bandCount)), MusicAnalyzer.bandCount - 1)
            let height = 1 - key.y // 0 = bottom row, 1 = top row
            let level = Double(m.bands[band])
            let lit = min(max((level * 1.1 - height) * 4, 0), 1)
            // Palette from the bottom row to the top, like a level meter, on a
            // dark floor so the peaks stand out.
            return (palette.sample(height, wrap: false), 0.03 + 0.97 * lit)

        case .pulse:
            // Brightness follows the bass; colour drifts slowly across the board.
            let quiet = Double(1 - m.intensity)
            // Once the tempo is known, the gentle background wave rolls across
            // the board once per beat, so it moves in time even between hits.
            let t = m.bpm > 0 ? Double(m.beatPhase) * 2 * .pi : now.timeIntervalSinceReferenceDate * 2
            let wave = 0.5 + 0.5 * sin(t - key.x * 5)
            let v = 0.08 + 0.6 * Double(m.bass) + 0.35 * flash + 0.12 * wave * quiet
            var c = palette.sample(phase + key.x * 0.2, wrap: true)
            if flash > 0.5 { c = c.mixed(with: palette.accent, (flash - 0.5) * 0.8) }
            return (c, v)

        case .ripples:
            // Background glows a little on each beat of the tempo.
            let tick = m.bpm > 0 ? pow(1 - Double(m.beatPhase), 3) * 0.08 : 0
            var v = 0.04 + 0.12 * Double(m.bass) + tick
            var c = palette.sample(phase, wrap: true)
            for r in ripples {
                let age = now.timeIntervalSince(r.born)
                let radius = age * (0.8 + 0.6 * r.strength)
                // The board is about three times wider than tall.
                let dist = sqrt(pow(key.x - r.x, 2) + pow((key.y - r.y) * 0.33, 2))
                let ring = exp(-pow(dist - radius, 2) / 0.008) * max(0, 1 - age / 1.4) * (0.5 + 0.5 * r.strength)
                if ring > v { v = ring; c = palette.sample(r.phase + 0.4, wrap: true) }
            }
            return (c, v)

        case .wave:
            // Distance from the middle column: the centre shows the newest
            // colour, the edges show older ones that have travelled out.
            guard !wave.isEmpty else { return (palette.sample(phase, wrap: true), 0.04) }
            let d = abs(key.x - 0.5) * 2
            let index = min(Int(d * Double(wave.count - 1)), wave.count - 1)
            let (c, v) = wave[index]
            return (c, v * pow(0.96, Double(index)) + 0.03)

        case .fireworks:
            var v = 0.03 + 0.05 * Double(m.bass)
            var c = palette.sample(phase, wrap: true)
            for s in sparks {
                let age = now.timeIntervalSince(s.born)
                let dist = sqrt(pow(key.x - s.x, 2) + pow((key.y - s.y) * 0.33, 2))
                // A bright core that blooms out a little and fades.
                let size = 0.02 + 0.05 * min(age / s.life, 1)
                let glow = exp(-pow(dist, 2) / (size * size)) * exp(-age / s.life) * s.strength
                if glow > v { v = glow; c = s.color }
            }
            return (c, v)
        }
    }

    /// Keep the whole board from jumping too far in brightness from one
    /// frame to the next, so big changes can't strobe.
    private func limitBoardSwing(_ values: inout [Double]) {
        defer { previous = values }
        guard previous.count == values.count else { return }
        let mean = values.reduce(0, +) / Double(values.count)
        let before = previous.reduce(0, +) / Double(values.count)
        let maxStep = reducedFlashing ? 0.04 : 0.12
        let delta = mean - before
        guard abs(delta) > maxStep else { return }
        let keep = maxStep / abs(delta)
        for i in values.indices { values[i] = previous[i] + (values[i] - previous[i]) * keep }
    }
}
