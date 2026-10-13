import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no
/// special permission to listen.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// Replace every registered shortcut. Returns the shortcuts macOS refused
    /// (usually because another app already owns them).
    @discardableResult
    func register(_ bindings: [(Hotkey, () -> Void)]) -> [Hotkey] {
        installHandler()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()

        var failed: [Hotkey] = []
        var seen = Set<Hotkey>()
        for (key, action) in bindings where seen.insert(key).inserted {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key.keyCode, key.modifiers,
                                             EventHotKeyID(signature: OSType(0x46393921), id: id), // 'F99!'
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = action
            } else {
                failed.append(key)
            }
        }
        return failed
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let action = HotkeyCenter.shared.actions[hk.id]
            DispatchQueue.main.async { action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Runs a macro's action.
enum MacroRunner {
    /// Typing into other apps needs Accessibility permission.
    static var canType: Bool { AXIsProcessTrusted() }

    static func askForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func run(_ macro: Macro) {
        switch macro.action {
        case .typeText: type(macro.value)
        case .open: open(macro.value)
        }
    }

    static func type(_ text: String) {
        guard canType else { askForAccessibility(); return }
        // Give the user a moment to let go of the shortcut's modifier keys,
        // otherwise ⌃/⌥ would still be held while the text goes in.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            let source = CGEventSource(stateID: .hidSystemState)
            for line in text.components(separatedBy: "\n").enumerated() {
                if line.offset > 0 { press(36, source) } // Return
                let units = Array(line.element.utf16)
                for chunk in stride(from: 0, to: units.count, by: 16) {
                    var slice = Array(units[chunk..<min(chunk + 16, units.count)])
                    for down in [true, false] {
                        let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                        e?.flags = []
                        e?.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                        e?.post(tap: .cghidEventTap)
                    }
                    usleep(8_000)
                }
            }
        }
    }

    private static func press(_ key: CGKeyCode, _ source: CGEventSource?) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            e?.flags = []
            e?.post(tap: .cghidEventTap)
        }
        usleep(8_000)
    }

    static func open(_ target: String) {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let ws = NSWorkspace.shared
        if t.hasPrefix("/") || t.hasPrefix("~") {
            ws.open(URL(fileURLWithPath: (t as NSString).expandingTildeInPath))
        } else if t.contains("://"), let url = URL(string: t) {
            ws.open(url)
        } else if let app = appURL(named: t) {
            ws.openApplication(at: app, configuration: .init())
        } else if let url = URL(string: "https://" + t), t.contains(".") {
            ws.open(url)
        }
    }

    private static func appURL(named name: String) -> URL? {
        let file = name.hasSuffix(".app") ? name : name + ".app"
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
