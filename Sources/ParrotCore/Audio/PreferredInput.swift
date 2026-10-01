import CoreAudio
import Foundation

/// The input Parrot records from: the system's default, except a Bluetooth
/// one, replaced by the Mac's built-in microphone when there is one
/// (fork-007). A Bluetooth headset's microphone delivers digital silence for
/// ~0.55 s after it opens (measured on AirPods Pro: 28 of 28 dictations), so
/// the first words were lost, and opening it drops the headset's playback to
/// call quality during every dictation. Wired and USB microphones are kept.
enum PreferredInput {
    /// The device to record from, for `systemDefault`.
    static func choose(_ systemDefault: AudioDeviceID) -> AudioDeviceID {
        let substitute = choose(
            defaultIsBluetooth: isBluetooth(transportType(systemDefault)),
            builtIn: builtInInputID()
        )
        guard let substitute else { return systemDefault }
        logOnce(systemDefault, substitute)
        return substitute
    }

    /// The built-in microphone to use instead of the default, or nil to keep
    /// the default. Pure, so it is tested.
    static func choose(defaultIsBluetooth: Bool, builtIn: AudioDeviceID?) -> AudioDeviceID? {
        defaultIsBluetooth ? builtIn : nil
    }

    static func isBluetooth(_ transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return 0 }
        return transport
    }

    /// The first built-in device with input channels: the Mac's microphone.
    static func builtInInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids.first { transportType($0) == kAudioDeviceTransportTypeBuiltIn && InputDevice.inputChannels($0) > 0 }
    }

    /// Logs a substitution when it starts, not at every lookup.
    private static func logOnce(_ from: AudioDeviceID, _ to: AudioDeviceID) {
        let pair = (UInt64(from) << 32) | UInt64(to)
        guard lastLogged.swap(pair) != pair else { return }
        let name = { InputDevice.name(of: $0) ?? "device \($0)" }
        Log.info("input: \(name(from)) is Bluetooth; recording from \(name(to))")
    }

    private static let lastLogged = AtomicPair()
}

/// The last logged substitution, read from capture and main threads.
private final class AtomicPair: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    /// Stores `new`; returns the previous value.
    func swap(_ new: UInt64) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = new
        return old
    }
}
