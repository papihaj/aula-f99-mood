// Generated from the key table in AULA's F99 KB.ini (via AulaSofwareLinux).
// x and y are each key's centre, scaled to 0...1 (x: left to right, y: top to
// bottom), for lighting effects. led is the key's index in the keyboard's LED
// table. frame is the key's outline for drawing, in pixels. The vendor's own
// outlines were traced by hand and wobbled, so frames sit on a tidy grid of
// key units instead, laid out like the real F99 (dropped arrow cluster and
// all).

extension F99 {
    struct Key {
        let name: String
        let x: Double
        let y: Double
        let led: Int
        let frame: (x: Double, y: Double, w: Double, h: Double)
    }

    /// One key unit (a letter key plus the gap after it), in pixels.
    static let unit = 32.5
    /// The space between neighbouring keys, in pixels.
    static let keyGap = 4.0

    /// Bounds of all key frames, in the same pixels.
    static let boardSize = (w: 19.4 * unit - keyGap, h: 6.55 * unit - keyGap)

    /// A key's outline from its place on the grid: left edge and top in
    /// units, and its width and height in units.
    static func grid(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        (x * unit, y * unit, w * unit - keyGap, h * unit - keyGap)
    }

    static let keys: [Key] = [
        Key(name: "Esc", x: 0.000, y: 0.006, led: 0, frame: grid(0, 0, 1, 1)),
        Key(name: "F1", x: 0.070, y: 0.000, led: 6, frame: grid(1.25, 0, 1, 1)),
        Key(name: "F2", x: 0.124, y: 0.006, led: 12, frame: grid(2.25, 0, 1, 1)),
        Key(name: "F3", x: 0.176, y: 0.006, led: 18, frame: grid(3.25, 0, 1, 1)),
        Key(name: "F4", x: 0.231, y: 0.006, led: 24, frame: grid(4.25, 0, 1, 1)),
        Key(name: "F5", x: 0.296, y: 0.000, led: 30, frame: grid(5.5, 0, 1, 1)),
        Key(name: "F6", x: 0.353, y: 0.006, led: 36, frame: grid(6.5, 0, 1, 1)),
        Key(name: "F7", x: 0.406, y: 0.006, led: 42, frame: grid(7.5, 0, 1, 1)),
        Key(name: "F8", x: 0.462, y: 0.006, led: 48, frame: grid(8.5, 0, 1, 1)),
        Key(name: "F9", x: 0.528, y: 0.000, led: 54, frame: grid(9.75, 0, 1, 1)),
        Key(name: "F10", x: 0.584, y: 0.000, led: 60, frame: grid(10.75, 0, 1, 1)),
        Key(name: "F11", x: 0.639, y: 0.006, led: 66, frame: grid(11.75, 0, 1, 1)),
        Key(name: "F12", x: 0.692, y: 0.006, led: 72, frame: grid(12.75, 0, 1, 1)),
        Key(name: "`", x: 0.002, y: 0.244, led: 1, frame: grid(0, 1.35, 1, 1)),
        Key(name: "1", x: 0.055, y: 0.250, led: 7, frame: grid(1, 1.35, 1, 1)),
        Key(name: "2", x: 0.110, y: 0.250, led: 13, frame: grid(2, 1.35, 1, 1)),
        Key(name: "3", x: 0.164, y: 0.250, led: 19, frame: grid(3, 1.35, 1, 1)),
        Key(name: "4", x: 0.219, y: 0.250, led: 25, frame: grid(4, 1.35, 1, 1)),
        Key(name: "5", x: 0.273, y: 0.250, led: 31, frame: grid(5, 1.35, 1, 1)),
        Key(name: "6", x: 0.326, y: 0.250, led: 37, frame: grid(6, 1.35, 1, 1)),
        Key(name: "7", x: 0.381, y: 0.250, led: 43, frame: grid(7, 1.35, 1, 1)),
        Key(name: "8", x: 0.435, y: 0.250, led: 49, frame: grid(8, 1.35, 1, 1)),
        Key(name: "9", x: 0.490, y: 0.250, led: 55, frame: grid(9, 1.35, 1, 1)),
        Key(name: "0", x: 0.543, y: 0.250, led: 61, frame: grid(10, 1.35, 1, 1)),
        Key(name: "-", x: 0.597, y: 0.250, led: 67, frame: grid(11, 1.35, 1, 1)),
        Key(name: "=", x: 0.652, y: 0.250, led: 73, frame: grid(12, 1.35, 1, 1)),
        Key(name: "Backspace", x: 0.732, y: 0.250, led: 79, frame: grid(13, 1.35, 2, 1)),
        Key(name: "Delete", x: 0.759, y: 0.000, led: 78, frame: grid(14, 0, 1, 1)),
        Key(name: "Home", x: 0.839, y: 0.006, led: 90, frame: grid(15.4, 0, 1, 1)),
        Key(name: "NumLock", x: 0.838, y: 0.244, led: 91, frame: grid(15.4, 1.35, 1, 1)),
        Key(name: "Num /", x: 0.891, y: 0.244, led: 97, frame: grid(16.4, 1.35, 1, 1)),
        Key(name: "Num*", x: 0.946, y: 0.244, led: 103, frame: grid(17.4, 1.35, 1, 1)),
        Key(name: "Num-", x: 1.000, y: 0.244, led: 109, frame: grid(18.4, 1.35, 1, 1)),
        Key(name: "Tab", x: 0.015, y: 0.433, led: 2, frame: grid(0, 2.35, 1.5, 1)),
        Key(name: "Q", x: 0.082, y: 0.433, led: 8, frame: grid(1.5, 2.35, 1, 1)),
        Key(name: "W", x: 0.137, y: 0.433, led: 14, frame: grid(2.5, 2.35, 1, 1)),
        Key(name: "E", x: 0.189, y: 0.433, led: 20, frame: grid(3.5, 2.35, 1, 1)),
        Key(name: "R", x: 0.246, y: 0.433, led: 26, frame: grid(4.5, 2.35, 1, 1)),
        Key(name: "T", x: 0.301, y: 0.433, led: 32, frame: grid(5.5, 2.35, 1, 1)),
        Key(name: "Y", x: 0.355, y: 0.433, led: 38, frame: grid(6.5, 2.35, 1, 1)),
        Key(name: "U", x: 0.408, y: 0.433, led: 44, frame: grid(7.5, 2.35, 1, 1)),
        Key(name: "I", x: 0.462, y: 0.433, led: 50, frame: grid(8.5, 2.35, 1, 1)),
        Key(name: "O", x: 0.515, y: 0.433, led: 56, frame: grid(9.5, 2.35, 1, 1)),
        Key(name: "P", x: 0.570, y: 0.433, led: 62, frame: grid(10.5, 2.35, 1, 1)),
        Key(name: "[", x: 0.624, y: 0.433, led: 68, frame: grid(11.5, 2.35, 1, 1)),
        Key(name: "]", x: 0.679, y: 0.433, led: 74, frame: grid(12.5, 2.35, 1, 1)),
        Key(name: "\\", x: 0.746, y: 0.433, led: 80, frame: grid(13.5, 2.35, 1.5, 1)),
        Key(name: "End", x: 0.893, y: 0.006, led: 96, frame: grid(16.4, 0, 1, 1)),
        Key(name: "PgUp", x: 0.948, y: 0.006, led: 102, frame: grid(17.4, 0, 1, 1)),
        Key(name: "Num7", x: 0.838, y: 0.433, led: 92, frame: grid(15.4, 2.35, 1, 1)),
        Key(name: "Num8", x: 0.893, y: 0.433, led: 98, frame: grid(16.4, 2.35, 1, 1)),
        Key(name: "Num9", x: 0.946, y: 0.433, led: 104, frame: grid(17.4, 2.35, 1, 1)),
        Key(name: "Num+", x: 1.000, y: 0.522, led: 110, frame: grid(18.4, 2.35, 1, 2)),
        Key(name: "CapsLock", x: 0.022, y: 0.606, led: 3, frame: grid(0, 3.35, 1.75, 1)),
        Key(name: "A", x: 0.095, y: 0.606, led: 9, frame: grid(1.75, 3.35, 1, 1)),
        Key(name: "S", x: 0.149, y: 0.606, led: 15, frame: grid(2.75, 3.35, 1, 1)),
        Key(name: "D", x: 0.204, y: 0.606, led: 21, frame: grid(3.75, 3.35, 1, 1)),
        Key(name: "F", x: 0.258, y: 0.606, led: 27, frame: grid(4.75, 3.35, 1, 1)),
        Key(name: "G", x: 0.313, y: 0.606, led: 33, frame: grid(5.75, 3.35, 1, 1)),
        Key(name: "H", x: 0.368, y: 0.606, led: 39, frame: grid(6.75, 3.35, 1, 1)),
        Key(name: "J", x: 0.421, y: 0.606, led: 45, frame: grid(7.75, 3.35, 1, 1)),
        Key(name: "K", x: 0.475, y: 0.606, led: 51, frame: grid(8.75, 3.35, 1, 1)),
        Key(name: "L", x: 0.528, y: 0.606, led: 57, frame: grid(9.75, 3.35, 1, 1)),
        Key(name: ";", x: 0.584, y: 0.606, led: 63, frame: grid(10.75, 3.35, 1, 1)),
        Key(name: "'", x: 0.637, y: 0.606, led: 69, frame: grid(11.75, 3.35, 1, 1)),
        Key(name: "Enter", x: 0.726, y: 0.606, led: 81, frame: grid(12.75, 3.35, 2.25, 1)),
        Key(name: "Num4", x: 0.838, y: 0.606, led: 93, frame: grid(15.4, 3.35, 1, 1)),
        Key(name: "Num5", x: 0.893, y: 0.606, led: 99, frame: grid(16.4, 3.35, 1, 1)),
        Key(name: "Num6", x: 0.946, y: 0.606, led: 105, frame: grid(17.4, 3.35, 1, 1)),
        Key(name: "LShift", x: 0.035, y: 0.783, led: 4, frame: grid(0, 4.35, 2.25, 1)),
        Key(name: "Z", x: 0.124, y: 0.783, led: 10, frame: grid(2.25, 4.35, 1, 1)),
        Key(name: "X", x: 0.177, y: 0.783, led: 16, frame: grid(3.25, 4.35, 1, 1)),
        Key(name: "C", x: 0.232, y: 0.783, led: 22, frame: grid(4.25, 4.35, 1, 1)),
        Key(name: "V", x: 0.286, y: 0.783, led: 28, frame: grid(5.25, 4.35, 1, 1)),
        Key(name: "B", x: 0.339, y: 0.783, led: 34, frame: grid(6.25, 4.35, 1, 1)),
        Key(name: "N", x: 0.393, y: 0.783, led: 40, frame: grid(7.25, 4.35, 1, 1)),
        Key(name: "M", x: 0.448, y: 0.783, led: 46, frame: grid(8.25, 4.35, 1, 1)),
        Key(name: ",", x: 0.503, y: 0.783, led: 52, frame: grid(9.25, 4.35, 1, 1)),
        Key(name: ".", x: 0.557, y: 0.783, led: 58, frame: grid(10.25, 4.35, 1, 1)),
        Key(name: "/", x: 0.610, y: 0.783, led: 64, frame: grid(11.25, 4.35, 1, 1)),
        Key(name: "RShift", x: 0.684, y: 0.789, led: 82, frame: grid(12.25, 4.35, 1.75, 1)),
        Key(name: "Up", x: 0.773, y: 0.817, led: 88, frame: grid(14.2, 4.55, 1, 1)),
        Key(name: "Num1", x: 0.839, y: 0.783, led: 94, frame: grid(15.4, 4.35, 1, 1)),
        Key(name: "Num2", x: 0.893, y: 0.783, led: 100, frame: grid(16.4, 4.35, 1, 1)),
        Key(name: "Num3", x: 0.948, y: 0.783, led: 106, frame: grid(17.4, 4.35, 1, 1)),
        Key(name: "LCtrl", x: 0.008, y: 0.967, led: 5, frame: grid(0, 5.35, 1.25, 1)),
        Key(name: "LWin", x: 0.077, y: 0.972, led: 11, frame: grid(1.25, 5.35, 1.25, 1)),
        Key(name: "LAlt", x: 0.144, y: 0.967, led: 17, frame: grid(2.5, 5.35, 1.25, 1)),
        Key(name: "Space", x: 0.346, y: 0.972, led: 35, frame: grid(3.75, 5.35, 6.25, 1)),
        Key(name: "RAlt", x: 0.545, y: 0.961, led: 53, frame: grid(10, 5.35, 1, 1)),
        Key(name: "FN", x: 0.599, y: 0.961, led: 59, frame: grid(11, 5.35, 1, 1)),
        Key(name: "RCtrl", x: 0.652, y: 0.961, led: 65, frame: grid(12, 5.35, 1, 1)),
        Key(name: "Left", x: 0.717, y: 0.994, led: 83, frame: grid(13.2, 5.55, 1, 1)),
        Key(name: "Down", x: 0.773, y: 0.994, led: 89, frame: grid(14.2, 5.55, 1, 1)),
        Key(name: "Right", x: 0.826, y: 1.000, led: 95, frame: grid(15.2, 5.55, 1, 1)),
        Key(name: "Num0", x: 0.893, y: 0.961, led: 101, frame: grid(16.4, 5.35, 1, 1)),
        Key(name: "Num .", x: 0.946, y: 0.961, led: 107, frame: grid(17.4, 5.35, 1, 1)),
        Key(name: "Enter", x: 1.000, y: 0.881, led: 112, frame: grid(18.4, 4.35, 1, 2)),
        Key(name: "PgDn", x: 1.000, y: 0.000, led: 108, frame: grid(18.4, 0, 1, 1)),
    ]
}
