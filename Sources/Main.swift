import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--info") {
            exit(CLI.info())
        }
        // --strip <offset> <value>: change one strip byte (0x1c-0x1f only).
        if let i = CommandLine.arguments.firstIndex(of: "--strip"), CommandLine.arguments.count > i + 2,
           let offset = Int(CommandLine.arguments[i + 1].replacingOccurrences(of: "0x", with: ""), radix: 16),
           let value = UInt8(CommandLine.arguments[i + 2]) {
            do {
                let page = try Keyboard.connect().setStripByte(offset, value)
                print(String(format: "strip bytes now: %02x %02x %02x %02x",
                             page.bytes[0x1c], page.bytes[0x1d], page.bytes[0x1e], page.bytes[0x1f]))
            } catch { print("error: \(error.localizedDescription)") }
            exit(0)
        }
        if CommandLine.arguments.contains("--snapshot") {
            do { print(try Keyboard.connect().snapshot()) } catch { print("error: \(error.localizedDescription)") }
            exit(0)
        }
        if CommandLine.arguments.contains("--probe") {
            print(Keyboard.probe())
            exit(0)
        }
        if CommandLine.arguments.contains("--listen") {
            exit(CLI.listen())
        }
        F99MoodApp.main()
    }
}

struct F99MoodApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        // The main window opens at launch. Closing it leaves the app running
        // in the menu bar; click the Dock icon or the menu bar icon to get it back.
        Window("F99 Mood", id: "main") {
            MainView().environmentObject(model)
        }
        .defaultSize(width: 760, height: 820)

        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)

        Window("F99 Mood Settings", id: "editor") {
            EditorView().environmentObject(model)
        }
        .defaultSize(width: 920, height: 620)
    }
}

/// `F99 Mood --info`: a read-only check from the terminal. Sends only the
/// identity and settings-page read commands.
enum CLI {
    static func info() -> Int32 {
        do {
            let kb = try Keyboard.connect()
            print("model      \(kb.modelName ?? "unknown (changes disabled)")")
            print("identity   \(kb.identityHex)")
            let page = try kb.readSettings()
            if let cur = page.current {
                print("effect     \(F99.effect(cur.effect)?.name ?? "other") (\(cur.effect))")
                print("brightness \(cur.brightness)")
                print("speed      \(cur.speed)")
                print("colour     \(cur.color)")
            }
            print("\n" + page.hexDump)
            return 0
        } catch {
            print("error: \(error.localizedDescription)")
            return 1
        }
    }

    /// `F99 Mood --listen`: show what music mode hears for 10 seconds, as a
    /// text equaliser. Doesn't touch the keyboard.
    static func listen() -> Int32 {
        let samples = SampleBuffer()
        let source = SystemAudioSource()
        do { try source.start(into: samples) } catch {
            print("error: \(error.localizedDescription)")
            return 1
        }
        defer { source.stop() }
        // Same timing as the app: analysis every 12 ms, a line every ~50 ms.
        let analyzer = MusicAnalyzer(hop: 0.012)
        let bars = " ▁▂▃▄▅▆▇█"
        var beats = 0
        var heard = false
        for i in 0..<833 {
            usleep(12_000)
            let latest = samples.latest(2048)
            if latest.contains(where: { $0 != 0 }) { heard = true }
            let m = analyzer.analyze(latest, sampleRate: samples.sampleRate, time: ProcessInfo.processInfo.systemUptime)
            if m.beat { beats += 1 }
            guard i % 4 == 0 else { continue }
            let line = m.bands.map { b in bars[bars.index(bars.startIndex, offsetBy: Int(b * 8.99))] }
            print("\r" + String(line) + String(format: "  level %3.0f%%  %3.0f BPM  ", m.level * 100, m.bpm) + (m.beat ? "BEAT" : "    "),
                  terminator: "")
            fflush(stdout)
        }
        print("\n\(beats) beats in 10 s")
        if !heard { print("Heard only silence: nothing is playing, or audio recording isn't allowed for this app.") }
        return 0
    }
}
