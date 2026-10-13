import Foundation
import IOKit.hid

/// The AULA vendor command channel: 520-byte HID feature reports, report id 6.
///
/// ```text
/// byte 0      report id (6)
/// byte 1      command, high bit set = read
/// byte 2      parameter
/// byte 3      0
/// byte 4      total packages
/// byte 5      package index
/// byte 6..7   payload length, little endian
/// byte 8..    payload, zero padded
/// ```
///
/// A read is a SET_FEATURE of the request header followed by a GET_FEATURE.
/// Only read commands and the settings-page write (0x04) are ever sent.
final class Keyboard {
    static let reportID: UInt8 = 6
    static let reportLength = 520
    static let header = 8
    /// The vendor driver waits this long around every transfer.
    static let gap: useconds_t = 20_000

    enum Command: UInt8 {
        case readIdentity = 0x82
        case readSettings = 0x84
        case writeSettings = 0x04
        /// Live colours, 3 bytes (R, G, B) per LED. These go to the
        /// keyboard's working memory, not its saved settings.
        case stream = 0x08
    }

    /// LED slots in one streamed frame (378 bytes). The F99 uses 0-112.
    static let streamSlots = 126

    let device: IOHIDDevice
    let identity: [UInt8]
    let modelName: String?

    var isF99: Bool { modelName != nil }
    var identityHex: String { identity.map { String(format: "%02x", $0) }.joined(separator: " ") }

    private init(device: IOHIDDevice, identity: [UInt8]) {
        self.device = device
        self.identity = identity
        self.modelName = F99.identities[identity]
    }

    deinit { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    // MARK: Discovery

    private static func devices(vendor: Int, product: Int) -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendor,
            kIOHIDProductIDKey: product,
        ] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// Find the wired F99 and open its vendor channel. Discovery only sends
    /// read commands.
    static func connect() throws -> Keyboard {
        // The interface that carries the vendor channel declares a feature
        // report of a full 520 bytes; the typing interfaces do not.
        let candidates = devices(vendor: F99.vendorID, product: F99.productID)
            .filter { intProperty($0, kIOHIDMaxFeatureReportSizeKey) >= reportLength - 1 }

        if candidates.isEmpty {
            if !devices(vendor: F99.receiverVendorID, product: F99.receiverProductID).isEmpty {
                throw KeyboardError.wirelessOnly
            }
            throw KeyboardError.notFound
        }

        var lastError: Error = KeyboardError.notFound
        for device in candidates {
            let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if status == kIOReturnNotPermitted {
                // Ask only if macOS has never asked; once it has, asking
                // again would just nag (the app shows where to allow it).
                if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
                    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                }
                lastError = KeyboardError.permissionDenied
                continue
            }
            guard status == kIOReturnSuccess else {
                lastError = KeyboardError.io(String(format: "open failed (0x%08x)", status))
                continue
            }
            do {
                let identity = try read(device, .readIdentity, parameter: 1, length: 6)
                let keyboard = Keyboard(device: device, identity: identity)
                // Accepting the report id is not proof this is the right
                // channel; a real settings page with its end marker is.
                _ = try keyboard.readSettings()
                return keyboard
            } catch {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
                lastError = error
            }
        }
        throw lastError
    }

    /// Read-only diagnostic: every data area the vendor driver itself reads,
    /// as hex text, so two snapshots can be compared. Only read commands from
    /// AULA's own driver are sent (see AulaSofwareLinux src/proto.rs).
    func snapshot() -> String {
        // (command, parameter, length, name)
        let areas: [(UInt8, UInt8, Int, String)] = [
            (0x84, 0, 128, "settings"),
            (0x8a, 0, 113 * 3, "per-key colours"),
            (0x86, 0, 512, "game mode table"),
            (0x85, 0, 512, "macros"),
            (0x83, 0, 512, "key layer 0"),
            (0x83, 1, 512, "key layer 1"),
            (0x83, 2, 512, "key layer 2"),
            (0x83, 3, 512, "key layer 3"),
            (0x87, 2, 2, "battery"),
        ]
        var out: [String] = []
        for (command, parameter, length, name) in areas {
            out.append(String(format: "== %@ (0x%02x/%d, %d bytes)", name, command, parameter, length))
            var reply = [UInt8](repeating: 0, count: Self.reportLength)
            var size = CFIndex(Self.reportLength)
            var request = [UInt8](repeating: 0, count: Self.reportLength)
            request[0] = Self.reportID; request[1] = command; request[2] = parameter
            request[4] = 1; request[6] = UInt8(length & 0xff); request[7] = UInt8(length >> 8)
            usleep(Self.gap)
            let set = request.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(Self.reportID), $0.baseAddress!, $0.count)
            }
            usleep(Self.gap)
            reply[0] = Self.reportID
            let get = reply.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(Self.reportID), $0.baseAddress!, &size)
            }
            guard set == kIOReturnSuccess, get == kIOReturnSuccess else {
                out.append(String(format: "failed: set 0x%08x get 0x%08x", set, get)); continue
            }
            let data = Array(reply.prefix(size))
            for row in stride(from: 0, to: data.count, by: 32) {
                out.append(String(format: "%04x ", row) + data[row..<min(row + 32, data.count)].map { String(format: "%02x", $0) }.joined(separator: " "))
            }
            usleep(50_000)
        }
        return out.joined(separator: "\n")
    }

    /// Read-only diagnostic: send the identity and settings reads and describe
    /// exactly what comes back. Used by `--probe`.
    static func probe() -> String {
        var out: [String] = []
        let all = devices(vendor: F99.vendorID, product: F99.productID)
        out.append("\(all.count) HID interface(s) for 258a:010c")
        for device in all {
            let feature = intProperty(device, kIOHIDMaxFeatureReportSizeKey)
            let page = intProperty(device, kIOHIDPrimaryUsagePageKey)
            let usage = intProperty(device, kIOHIDPrimaryUsageKey)
            out.append(String(format: "- usage page 0x%04x usage 0x%02x, max feature report %d", page, usage, feature))
            guard feature >= reportLength - 1 else { continue }
            let open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            out.append(String(format: "  open: 0x%08x", open))
            guard open == kIOReturnSuccess else { continue }
            defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
            for (command, parameter, length) in [(Command.readIdentity, UInt8(1), 6), (.readSettings, 0, 128)] {
                let request = frame(command, parameter: parameter, length: length)
                usleep(gap)
                let set = request.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), $0.baseAddress!, $0.count)
                }
                usleep(gap)
                var reply = [UInt8](repeating: 0, count: reportLength)
                reply[0] = reportID
                var size = CFIndex(reportLength)
                let get = reply.withUnsafeMutableBufferPointer {
                    IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), $0.baseAddress!, &size)
                }
                let shown = reply.prefix(min(max(size, 0), 24)).map { String(format: "%02x", $0) }.joined(separator: " ")
                out.append(String(format: "  cmd 0x%02x: set 0x%08x, get 0x%08x, %d bytes: %@", command.rawValue, set, get, size, shown))
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Transport

    private static func frame(_ command: Command, parameter: UInt8, length: Int, payload: [UInt8] = []) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: reportLength)
        buf[0] = reportID
        buf[1] = command.rawValue
        buf[2] = parameter
        buf[4] = 1 // packages: everything this app sends fits in one
        buf[5] = 0
        buf[6] = UInt8(length & 0xff)
        buf[7] = UInt8(length >> 8)
        buf.replaceSubrange(header..<header + payload.count, with: payload)
        return buf
    }

    private static func setFeature(_ device: IOHIDDevice, _ buf: [UInt8]) throws {
        var last: IOReturn = kIOReturnError
        for _ in 0..<3 {
            usleep(gap)
            last = buf.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), $0.baseAddress!, $0.count)
            }
            if last == kIOReturnSuccess { return }
            usleep(70_000)
        }
        throw KeyboardError.io(String(format: "write failed (0x%08x)", last))
    }

    private static func read(_ device: IOHIDDevice, _ command: Command, parameter: UInt8, length: Int) throws -> [UInt8] {
        try setFeature(device, frame(command, parameter: parameter, length: length))
        usleep(gap)
        var reply = [UInt8](repeating: 0, count: reportLength)
        reply[0] = reportID
        var size = CFIndex(reportLength)
        let status = reply.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), $0.baseAddress!, &size)
        }
        guard status == kIOReturnSuccess else {
            throw KeyboardError.io(String(format: "read failed (0x%08x)", status))
        }
        guard reply[1] == command.rawValue, size >= header + length else { throw KeyboardError.badReply }
        return Array(reply[header..<header + length])
    }

    // MARK: Settings page

    /// Read the settings page, retrying while the keyboard is busy.
    func readSettings() throws -> ConfigPage {
        var lastError: Error = KeyboardError.badReply
        for attempt in 0..<4 {
            if attempt > 0 { usleep(150_000) }
            do {
                let raw = try Self.read(device, .readSettings, parameter: 0, length: ConfigPage.length)
                if let page = ConfigPage(raw) { return page }
                lastError = KeyboardError.badReply
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func writeSettings(_ page: ConfigPage) throws {
        try Self.setFeature(device, Self.frame(.writeSettings, parameter: 0, length: ConfigPage.length, payload: page.bytes))
    }

    /// Read the page, patch the lighting fields, write it back, and confirm the
    /// keyboard kept them. If it did not, the original page is written back.
    @discardableResult
    func apply(_ lighting: ConfigPage.Lighting, strip: ConfigPage.Strip? = nil) throws -> ConfigPage {
        try write { page in
            try page.apply(lighting)
            if let strip { try page.setStrip(strip) }
        }
    }

    @discardableResult
    func setStrip(_ strip: ConfigPage.Strip) throws -> ConfigPage {
        try write { try $0.setStrip(strip) }
    }

    /// Put back the lighting part (effect and per-effect table) of a page saved
    /// earlier. Every other byte stays as the keyboard has it now.
    @discardableResult
    func restoreLighting(from saved: ConfigPage) throws -> ConfigPage {
        try write { page in page.copyLighting(from: saved) }
    }

    /// Switch to per-key mode so colours streamed from the Mac show up.
    /// Returns the page from before, for `restoreLighting(from:)` afterwards.
    func enterStreamMode(strip: ConfigPage.Strip? = nil) throws -> ConfigPage {
        let before = try readSettings()
        _ = try write { page in
            page.setStreamMode()
            if let strip { try page.setStrip(strip) }
        }
        return before
    }

    /// Change one of the strip's settings bytes (read, patch, write, check).
    @discardableResult
    func setStripByte(_ offset: Int, _ value: UInt8) throws -> ConfigPage {
        try write { try $0.setStripByte(offset, value) }
    }

    /// Send one frame of colours: `rgb` holds R, G, B for each LED slot.
    /// Callers must leave at least 46 ms between frames. Sending faster
    /// starves the keyboard's key scanning, and keypresses get dropped.
    func stream(_ rgb: [UInt8]) throws {
        precondition(rgb.count == Self.streamSlots * 3)
        try Self.setFeature(device, Self.frame(.stream, parameter: 0, length: rgb.count, payload: rgb))
    }

    private func write(_ change: (inout ConfigPage) throws -> Void) throws -> ConfigPage {
        guard isF99 else { throw KeyboardError.unknownModel(identityHex) }
        let original = try readSettings()
        var page = original
        try change(&page)
        let changed = page.diff(original)
        if changed.isEmpty { return page }

        try writeSettings(page)
        // A settings write makes the firmware repaint a few hundred ms later.
        usleep(400_000)
        let back = try readSettings()
        if changed.contains(where: { back.bytes[$0] != page.bytes[$0] }) {
            try? writeSettings(original)
            throw KeyboardError.verifyFailed
        }
        return back
    }
}
