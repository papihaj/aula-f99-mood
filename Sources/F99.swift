import Foundation

/// What the app knows about the AULA F99, taken from the vendor's own `KB.ini`
/// for the F99 (as published by the AulaSofwareLinux project).
enum F99 {
    /// Every keyboard in this AULA family shares these USB ids when wired.
    static let vendorID = 0x258a
    static let productID = 0x010c
    /// The 2.4 GHz receiver. It speaks a different protocol, and writing the
    /// wired settings block through it has bricked a keyboard before, so the
    /// app refuses to talk to it.
    static let receiverVendorID = 0x3554
    static let receiverProductID = 0xfa09

    /// The 6-byte identity the keyboard returns for command 0x82 / param 1.
    /// The F99 family shares its settings layout; anything else is read-only.
    static let identities: [[UInt8]: String] = [
        [0x03, 0x00, 0x00, 0x00, 0x00, 0xa4]: "AULA F99",
        [0x03, 0x00, 0x00, 0x00, 0x01, 0x58]: "AULA F99 Pro",
        [0x03, 0x00, 0x00, 0x00, 0x00, 0x9a]: "AULA F99 Wired",
    ]

    /// Brightness and speed levels, from `LightHW=` and `SpeedHW=`.
    static let brightnessLevels: ClosedRange<Int> = 0...4
    static let speedLevels: ClosedRange<Int> = 0...4

    struct Effect: Identifiable, Hashable {
        /// The value stored in the settings page, and (minus one) the slot that
        /// holds this effect's brightness / speed / colour.
        let id: Int
        let name: String
        let hasSpeed: Bool
        let hasColor: Bool
    }

    /// `LedOpt1..18` from the F99 `KB.ini`, named with the vendor's English
    /// strings. Entry 19 (value 21) is left out on purpose: the F75 work shows
    /// that value also selects per-key mode, so it is not a safe "off".
    static let effects: [Effect] = [
        Effect(id: 1, name: "Fixed on", hasSpeed: false, hasColor: true),
        Effect(id: 2, name: "Breathing", hasSpeed: true, hasColor: true),
        Effect(id: 3, name: "Rainbow", hasSpeed: true, hasColor: false),
        Effect(id: 4, name: "Flash away", hasSpeed: true, hasColor: true),
        Effect(id: 5, name: "Raindrops", hasSpeed: true, hasColor: true),
        Effect(id: 6, name: "Rainbow wheel", hasSpeed: true, hasColor: true),
        Effect(id: 7, name: "Ripples shining", hasSpeed: true, hasColor: true),
        Effect(id: 8, name: "Stars twinkle", hasSpeed: true, hasColor: true),
        Effect(id: 9, name: "Shadow disappear", hasSpeed: true, hasColor: true),
        Effect(id: 10, name: "Retro snake", hasSpeed: true, hasColor: true),
        Effect(id: 11, name: "Neon stream", hasSpeed: true, hasColor: true),
        Effect(id: 12, name: "Reaction", hasSpeed: true, hasColor: true),
        Effect(id: 13, name: "Sine wave", hasSpeed: true, hasColor: true),
        Effect(id: 14, name: "Retinue scanning", hasSpeed: true, hasColor: true),
        Effect(id: 15, name: "Rotating windmill", hasSpeed: true, hasColor: false),
        Effect(id: 16, name: "Colorful waterfall", hasSpeed: true, hasColor: false),
        Effect(id: 17, name: "Blossoming", hasSpeed: true, hasColor: false),
        Effect(id: 18, name: "Rotating storm", hasSpeed: true, hasColor: true),
    ]

    static func effect(_ id: Int) -> Effect? { effects.first { $0.id == id } }

    /// The effects the mood editor offers: one of each kind of movement
    /// (Fixed on, Breathing, Raindrops, Ripples shining, Stars twinkle, Neon
    /// stream, Reaction, Sine wave).
    /// The rest look like one of these, so they're left out to keep the list
    /// short; the keyboard still has them under Fn + \. Rainbow wheel (6)
    /// leaves the keys dark on a real F99, so it's never offered.
    static let offeredEffects = [1, 2, 5, 7, 8, 11, 12, 13]

    struct FirmwareColor: Identifiable, Hashable {
        let id: Int
        let name: String
        let rgb: (Double, Double, Double)
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    /// The firmware only knows these fixed colours (index 0-6), plus 7 which
    /// asks it to cycle through colours by itself.
    static let colors: [FirmwareColor] = [
        FirmwareColor(id: 0, name: "Red", rgb: (1, 0, 0)),
        FirmwareColor(id: 1, name: "Green", rgb: (0, 1, 0)),
        FirmwareColor(id: 2, name: "Blue", rgb: (0, 0, 1)),
        FirmwareColor(id: 3, name: "Yellow", rgb: (1, 1, 0)),
        FirmwareColor(id: 4, name: "Magenta", rgb: (1, 0, 1)),
        FirmwareColor(id: 5, name: "Cyan", rgb: (0, 1, 1)),
        FirmwareColor(id: 6, name: "White", rgb: (1, 1, 1)),
    ]
    static let colorful = 7
    /// Effects whose "colourful" setting is soft pastel on a real F99, not a
    /// full rainbow: Flash away, Raindrops, Ripples shining, Retro snake.
    static let pastelEffects: Set<Int> = [4, 5, 7, 10]

    /// The light strip between Backspace and Num Lock isn't part of the live
    /// colour frame (it stays put while every free slot is set) and AULA's own
    /// driver has no strip settings, but it does have saved settings in the
    /// settings page: see `ConfigPage.stripOffsets`.

    /// The firmware colour nearest to `rgb`, judged in Oklab so it matches
    /// what the eye sees (e.g. violet goes to blue or magenta, not white).
    static func nearestColor(_ rgb: RGB) -> Int {
        let target = rgb.oklab
        return colors.min { a, b in
            func d(_ c: FirmwareColor) -> Double {
                let o = RGB(c.rgb.0, c.rgb.1, c.rgb.2).oklab
                return pow(o.0 - target.0, 2) + pow(o.1 - target.1, 2) + pow(o.2 - target.2, 2)
            }
            return d(a) < d(b)
        }!.id
    }
}
