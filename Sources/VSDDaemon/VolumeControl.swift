import CoreAudio
import Foundation

enum VolumeControl {

    /// Base step per unit (0.0–1.0 range). ~2% per unit, so config step:5 = ~10% per tick.
    private static let baseStep: Float32 = 0.02

    /// Adjust system volume. Step sign = direction, magnitude = how much.
    static func adjust(step: Int) {
        guard step != 0 else { return }
        guard let deviceID = defaultOutputDevice() else { return }
        let current = getVolume(deviceID)
        let delta = baseStep * Float32(step)
        let newVol = min(1.0, max(0.0, current + delta))
        setVolume(deviceID, volume: newVol)
    }

    /// Toggle mute on the default output device.
    static func toggleMute() {
        guard let deviceID = defaultOutputDevice() else { return }
        let muted = getMute(deviceID)
        setMute(deviceID, mute: !muted)
    }

    // MARK: - CoreAudio helpers

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if status != noErr {
            print("Warning: could not get default output device (status \(status))")
        }
        return status == noErr ? deviceID : nil
    }

    private static func getVolume(_ deviceID: AudioDeviceID) -> Float32 {
        // Try master channel first (element 0), fall back to channel 1
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
                if status == noErr { return volume }
            }
        }
        return 0
    }

    private static func setVolume(_ deviceID: AudioDeviceID, volume: Float32) {
        // Set on all available channels (master=0, left=1, right=2)
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var vol = volume
            let size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
            }
        }
    }

    private static func getMute(_ deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        }
        return muted != 0
    }

    private static func setMute(_ deviceID: AudioDeviceID, mute: Bool) {
        var muted: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)
        }
    }
}
