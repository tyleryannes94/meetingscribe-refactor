import Foundation
import CoreAudio
import AudioToolbox

/// Read-only CoreAudio helper for choosing a recording input device. Used to
/// honor "prefer AirPods/Bluetooth, never the built-in mic" without changing the
/// user's system-wide default input — the engine is pinned to the chosen device.
enum AudioInputDevices {
    struct Device {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32
        var isBluetooth: Bool {
            transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
        }
        var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
        var isAirPods: Bool { name.localizedCaseInsensitiveContains("airpod") }
    }

    /// All hardware input devices (those exposing at least one input channel).
    static func all() -> [Device] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            return Device(id: id, name: name(of: id) ?? "Unknown", transport: transport(of: id))
        }
    }

    /// The device to record from given the "prefer Bluetooth" setting:
    /// AirPods first, then any Bluetooth input. Returns nil to mean "use the
    /// system default" (no suitable Bluetooth input connected).
    static func preferredBluetoothInput() -> Device? {
        let inputs = all()
        if let airpods = inputs.first(where: { $0.isAirPods }) { return airpods }
        return inputs.first(where: { $0.isBluetooth })
    }

    /// The current system default input device, for diagnostics/warnings.
    static func defaultInput() -> Device? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID) == noErr,
              devID != 0 else { return nil }
        return Device(id: devID, name: name(of: devID) ?? "Unknown", transport: transport(of: devID))
    }

    // MARK: - Property readers

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let abl = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { abl.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, abl) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(abl.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t) == noErr else { return 0 }
        return t
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}
