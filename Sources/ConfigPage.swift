import Foundation

/// The keyboard's 128-byte lighting / settings page (read 0x84, write 0x04).
///
/// The page is never built from scratch: it is read from the keyboard, only the
/// bytes for the lighting fields are patched, and it is written back. Bytes the
/// app does not understand survive untouched.
///
/// ```text
/// 0x09          1 while the keyboard shows colours streamed from the Mac
/// 0x0a          live effect (1-based position in the effect list)
/// 0x3a + 2*n    effect n+1: brightness
/// 0x3b + 2*n    effect n+1: speed (high nibble) | colour (low nibble)
/// 0x7e 0x7f     5A A5 end marker
/// ```
struct ConfigPage: Equatable {
    static let length = 128
    static let streamFlagOffset = 0x09
    static let effectOffset = 0x0a
    /// Effect value for "colours come from the computer" (entry 21 in the F99's
    /// effect list; 0x15 in the F75 captures).
    static let streamEffect = 21
    static let tableOffset = 0x3a

    private(set) var bytes: [UInt8]

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= Self.length else { return nil }
        let page = Array(bytes.prefix(Self.length))
        // A busy keyboard answers with a truncated, mostly-zero buffer. Writing
        // that back would wipe its settings, so anything without the marker is
        // rejected here.
        guard page[Self.length - 2] == 0x5a, page[Self.length - 1] == 0xa5 else { return nil }
        self.bytes = page
    }

    struct Lighting: Hashable, Codable {
        var effect: Int
        var brightness: Int
        var speed: Int
        var color: Int
    }

    var effect: Int { Int(bytes[Self.effectOffset]) }

    /// Byte offset of the settings slot for `effect`, if it is a sane value.
    private static func slotOffset(_ effect: Int) -> Int? {
        guard effect >= 1 else { return nil }
        let at = tableOffset + (effect - 1) * 2
        return at + 2 <= length - 2 ? at : nil
    }

    func settings(for effect: Int) -> Lighting? {
        guard let at = Self.slotOffset(effect) else { return nil }
        let packed = bytes[at + 1]
        return Lighting(effect: effect, brightness: Int(bytes[at]),
                        speed: Int(packed >> 4), color: Int(packed & 0x0f))
    }

    var current: Lighting? { settings(for: effect) }

    /// Patch in `lighting`. Only the effect byte and that effect's two-byte
    /// slot can change.
    mutating func apply(_ l: Lighting) throws {
        guard F99.effect(l.effect) != nil,
              F99.brightnessLevels.contains(l.brightness),
              F99.speedLevels.contains(l.speed),
              (0...F99.colorful).contains(l.color),
              let at = Self.slotOffset(l.effect)
        else { throw KeyboardError.invalidSetting }
        if isStreamMode { bytes[Self.streamFlagOffset] = 0 }
        bytes[Self.effectOffset] = UInt8(l.effect)
        bytes[at] = UInt8(l.brightness)
        bytes[at + 1] = UInt8(l.speed << 4 | l.color)
    }

    var isStreamMode: Bool {
        bytes[Self.streamFlagOffset] == 1 && Int(bytes[Self.effectOffset]) == Self.streamEffect
    }

    /// Per-key mode, so the keyboard shows colours streamed from the Mac. All
    /// three bytes matter: on the F75, setting only the first two leaves the
    /// board dark. The third is effect 1's speed/colour byte.
    mutating func setStreamMode() {
        bytes[Self.streamFlagOffset] = 1
        bytes[Self.effectOffset] = UInt8(Self.streamEffect)
        bytes[Self.tableOffset + 1] = 0x47
    }

    /// The bytes that make up the lighting: the stream flag, the live effect
    /// and the per-effect table up to the end marker.
    static let lightingRanges = [streamFlagOffset..<effectOffset + 1, tableOffset..<length - 2]

    mutating func copyLighting(from other: ConfigPage) {
        for r in Self.lightingRanges { bytes.replaceSubrange(r, with: other.bytes[r]) }
    }

    /// The side light strip's settings, found on an F99 on 2026-10-12 and 13:
    /// - 0x1c mode (`StripMode`): 0 off, 1 and 2 colour-changing gradients,
    ///   3 steady, 4 blinking. Fn + Shift steps through them; 5 and up show
    ///   steady red, so they aren't used.
    /// - 0x1d colour, same numbering as the keys (0 red, 1 green, …): writing
    ///   1 turned the static red strip green.
    /// - 0x1e brightness (0 is off), 0x1f speed (0 slowest); never written by
    ///   the app. Neither limits the gradient's colours: it's always a rainbow.
    static let stripOffsets = 0x1c...0x1f
    static let stripModeOffset = 0x1c
    static let stripColorOffset = 0x1d

    var stripColor: Int { Int(bytes[Self.stripColorOffset]) }
    var stripMode: Int { Int(bytes[Self.stripModeOffset]) }

    enum StripMode: Int { case off = 0, gradient = 1, steady = 3, blinking = 4 }

    /// How the strip should look: a mode and, for steady or blinking, a colour.
    struct Strip: Equatable {
        var mode: StripMode
        var color: Int?
        static let off = Strip(mode: .off)
        static let gradient = Strip(mode: .gradient)
        static func steady(_ color: Int) -> Strip { Strip(mode: .steady, color: color) }
        static func blinking(_ color: Int) -> Strip { Strip(mode: .blinking, color: color) }
    }

    /// The strip already looks like `s` (its colour only matters when `s` has one).
    func shows(_ s: Strip) -> Bool {
        stripMode == s.mode.rawValue && (s.color == nil || stripColor == s.color)
    }

    var strip: Strip {
        Strip(mode: StripMode(rawValue: stripMode) ?? .steady, color: stripColor)
    }

    mutating func setStrip(_ s: Strip) throws {
        if let color = s.color {
            guard (0..<F99.colorful).contains(color) else { throw KeyboardError.invalidSetting }
            bytes[Self.stripColorOffset] = UInt8(color)
        }
        bytes[Self.stripModeOffset] = UInt8(s.mode.rawValue)
    }

    mutating func setStripByte(_ offset: Int, _ value: UInt8) throws {
        guard Self.stripOffsets.contains(offset) else { throw KeyboardError.invalidSetting }
        bytes[offset] = value
    }

    /// Offsets that differ from `other`.
    func diff(_ other: ConfigPage) -> [Int] {
        (0..<Self.length).filter { bytes[$0] != other.bytes[$0] }
    }

    var hexDump: String {
        stride(from: 0, to: Self.length, by: 16).map { row in
            String(format: "%04x  ", row) + bytes[row..<row + 16].map { String(format: "%02x", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

enum KeyboardError: LocalizedError {
    case notFound
    case wirelessOnly
    case permissionDenied
    case io(String)
    case badReply
    case unknownModel(String)
    case invalidSetting
    case verifyFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No F99 found. Plug it in with the USB-C cable and set it to wired mode."
        case .wirelessOnly:
            return "The F99 is connected through its 2.4 GHz receiver. Plug in the USB-C cable to change lighting."
        case .permissionDenied:
            return "macOS blocked access. Allow F99 Mood under System Settings → Privacy & Security → Input Monitoring, then reopen the app."
        case .io(let s):
            return "Keyboard communication failed: \(s)"
        case .badReply:
            return "The keyboard sent an unexpected reply. Try again in a moment."
        case .unknownModel(let id):
            return "This keyboard identifies as \(id), which is not an F99. Changes are disabled to keep it safe."
        case .invalidSetting:
            return "That lighting setting is out of range."
        case .verifyFailed:
            return "The keyboard didn't keep the change, so the previous settings were restored."
        }
    }
}
