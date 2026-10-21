import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// Output volume, mute state and the current output device.
@MainActor
@Observable
final class AudioService {
    static let shared = AudioService()

    var volume: Double = 0
    var isMuted = false
    var outputDevice: String = "Built-in Output"

    private var defaultDevice: AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else { return 0 }
        return deviceID
    }

    func refresh() {
        let device = defaultDevice
        guard device != 0 else { return }
        volume = Self.readVolume(device: device)
        isMuted = Self.readMute(device: device)
        outputDevice = Self.readDeviceName(device: device) ?? "Output"
    }

    func setVolume(_ value: Double) {
        let device = defaultDevice
        guard device != 0 else { return }
        let clamped = min(max(value, 0), 1)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume32 = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            size,
            &volume32
        )
        volume = clamped
    }

    func toggleMute() {
        let device = defaultDevice
        guard device != 0 else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = isMuted ? 0 : 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &muted)
        isMuted.toggle()
    }

    // MARK: - Reading

    private static func readVolume(device: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else {
            return 0
        }
        return Double(volume)
    }

    private static func readMute(device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
            return false
        }
        return muted != 0
    }

    private static func readDeviceName(device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name
        else {
            return nil
        }
        // The property hands over a +1 reference.
        return name.takeRetainedValue() as String
    }
}
