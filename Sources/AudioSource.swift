import AVFoundation
import CoreAudio

/// The most recent few thousand mono samples, written by the audio thread and
/// read by the lighting loop.
final class SampleBuffer {
    private var ring = [Float](repeating: 0, count: 8192)
    private var head = 0
    private let lock = NSLock()
    private(set) var sampleRate: Double = 48_000

    func setSampleRate(_ rate: Double) {
        lock.lock(); sampleRate = rate; lock.unlock()
    }

    /// Add `frames` frames of `channels`-interleaved float audio, mixed to mono.
    func append(_ data: UnsafePointer<Float>, frames: Int, channels: Int) {
        guard channels > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let scale = 1 / Float(channels)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += data[f * channels + c] }
            ring[head] = sum * scale
            head = (head + 1) % ring.count
        }
    }

    /// The last `count` samples, oldest first.
    func latest(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let n = min(count, ring.count)
        let start = (head - n + ring.count) % ring.count
        return (0..<n).map { ring[(start + $0) % ring.count] }
    }
}

enum AudioError: LocalizedError {
    case system(String, OSStatus)
    case microphoneDenied
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .system(let what, let status):
            return "Couldn't listen to your Mac's audio (\(what), error \(status)). Allow F99 Mood under System Settings → Privacy & Security → Screen & System Audio Recording."
        case .microphoneDenied:
            return "Microphone access is off. Allow F99 Mood under System Settings → Privacy & Security → Microphone."
        case .noMicrophone:
            return "This Mac has no microphone to listen with. Plug one in, or choose “Sound playing on this Mac” instead."
        }
    }
}

protocol AudioSource: AnyObject {
    func start(into buffer: SampleBuffer) throws
    func stop()
    /// Called (on the main queue) when the sound goes to a different device,
    /// say AirPods connecting, so listening has to start again.
    var onDeviceChange: (() -> Void)? { get set }
}

/// Everything the Mac is playing, through a Core Audio process tap
/// (macOS 14.2+). The sound still plays normally; the app only gets a copy.
final class SystemAudioSource: AudioSource {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "f99.audio", qos: .userInitiated)
    var onDeviceChange: (() -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    private static var outputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start(into buffer: SampleBuffer) throws {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onDeviceChange?() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.outputDeviceAddress,
                                               .main, block) == noErr {
            listener = block
        }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "F99 Mood"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw AudioError.system("tap", status) }

        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { stop(); throw AudioError.system("format", status) }
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            stop(); throw AudioError.system("unsupported format", -1)
        }
        buffer.setSampleRate(format.mSampleRate)
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "F99 Mood Listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw AudioError.system("listener device", status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            // Non-interleaved audio arrives one channel per buffer; the first
            // (left) channel is plenty for lighting.
            guard let first = buffers.first, let data = first.mData else { return }
            let channels = interleaved ? Int(first.mNumberChannels) : 1
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / max(channels, 1)
            buffer.append(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels)
        }
        guard status == noErr else { stop(); throw AudioError.system("listener", status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw AudioError.system("start", status) }
    }

    func stop() {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.outputDeviceAddress,
                                                   .main, listener)
            self.listener = nil
        }
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func defaultOutputUID() throws -> String {
        // The device music plays through (not the one for alert sounds).
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw AudioError.system("output device", status) }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw AudioError.system("output device id", status) }
        return uid.takeRetainedValue() as String
    }
}

/// The built-in (or any default) microphone, for music playing in the room.
final class MicrophoneSource: AudioSource {
    private let engine = AVAudioEngine()
    var onDeviceChange: (() -> Void)?

    func start(into buffer: SampleBuffer) throws {
        let access = AVCaptureDevice.authorizationStatus(for: .audio)
        guard access != .denied, access != .restricted else { throw AudioError.microphoneDenied }
        guard AVCaptureDevice.default(for: .audio) != nil else { throw AudioError.noMicrophone }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // With no input device the format is empty, and installing a tap
        // would crash.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.noMicrophone }
        buffer.setSampleRate(format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { pcm, _ in
            guard let channel = pcm.floatChannelData?[0] else { return }
            buffer.append(channel, frames: Int(pcm.frameLength), channels: 1)
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
