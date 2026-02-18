import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Mutes system audio and blocks volume/mute keys during the bedtime overlay.
///
/// Persists the previous audio state to a marker file so it can be restored
/// after a crash (the CGEventTap dies with the process, so only audio state
/// needs recovery).
class AudioMuter {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Public API

    func mute() {
        print("\(debugMarker) AudioMuter.mute called")
        guard let deviceID = defaultOutputDevice() else {
            print("\(debugMarker) AudioMuter: no default output device")
            return
        }

        saveCurrentState(deviceID: deviceID)
        setMute(deviceID: deviceID, muted: true)
        installEventTap()
    }

    func unmute() {
        print("\(debugMarker) AudioMuter.unmute called")
        removeEventTap()
        restoreState()
    }

    func restoreIfNeeded() {
        print("\(debugMarker) AudioMuter.restoreIfNeeded called")
        guard Paths.fileExists(at: Paths.audioMutedPath) else {
            print("\(debugMarker) AudioMuter: no crash-recovery marker found")
            return
        }
        print("\(debugMarker) AudioMuter: crash-recovery marker found, restoring")
        restoreState()
    }

    // MARK: - Audio device helpers

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            print("\(debugMarker) AudioMuter: failed to get default output device, status=\(status)")
            return nil
        }
        return deviceID
    }

    private func setMute(deviceID: AudioDeviceID, muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &address) {
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(
                deviceID, &address, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &value
            )
            print("\(debugMarker) AudioMuter: setMute(\(muted)) via mute property, status=\(status)")
        } else {
            // Fallback: set volume to 0
            print("\(debugMarker) AudioMuter: mute property not available, falling back to volume=0")
            if muted {
                setVolume(deviceID: deviceID, volume: 0.0)
            }
        }
    }

    private func setVolume(deviceID: AudioDeviceID, volume: Float32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = volume
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &vol
        )
        print("\(debugMarker) AudioMuter: setVolume(\(volume)), status=\(status)")
    }

    private func getVolume(deviceID: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return volume
    }

    private func getMute(deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    // MARK: - State persistence

    private struct SavedAudioState: Codable {
        let wasMuted: UInt32
        let volume: Float32?
    }

    private func saveCurrentState(deviceID: AudioDeviceID) {
        let state = SavedAudioState(
            wasMuted: getMute(deviceID: deviceID) ?? 0,
            volume: getVolume(deviceID: deviceID)
        )
        Paths.ensureDirectoryExists()
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Paths.audioMutedPath, options: .atomic)
            print("\(debugMarker) AudioMuter: saved state wasMuted=\(state.wasMuted) volume=\(state.volume ?? -1)")
        }
    }

    private func restoreState() {
        guard let data = try? Data(contentsOf: Paths.audioMutedPath),
              let state = try? JSONDecoder().decode(SavedAudioState.self, from: data) else {
            print("\(debugMarker) AudioMuter: no saved state to restore")
            Paths.removeFile(at: Paths.audioMutedPath)
            return
        }

        guard let deviceID = defaultOutputDevice() else {
            print("\(debugMarker) AudioMuter: no output device for restore")
            Paths.removeFile(at: Paths.audioMutedPath)
            return
        }

        setMute(deviceID: deviceID, muted: state.wasMuted == 1)
        if let volume = state.volume {
            setVolume(deviceID: deviceID, volume: volume)
        }

        Paths.removeFile(at: Paths.audioMutedPath)
        print("\(debugMarker) AudioMuter: restored state and removed marker")
    }

    // MARK: - CGEventTap for blocking volume/mute keys

    private func installEventTap() {
        // NX_SYSDEFINED = 14 — media keys are system-defined events
        let eventMask: CGEventMask = 1 << 14

        // The callback is a C function pointer — use a static-like closure.
        // We pass `self` as userInfo so we can log from the callback.
        let tapCallback: CGEventTapCallBack = { _, _, event, userInfo in
            // System-defined events carry media key data in a specific format.
            // NSEvent subtype 8 = system-defined media key events.
            let nsEvent = NSEvent(cgEvent: event)
            guard nsEvent?.subtype.rawValue == 8 else { return Unmanaged.passRetained(event) }

            // Media key data is packed into event data1:
            // bits 16-31: key code, bit 8: key down flag
            guard let data1 = nsEvent?.data1 else { return Unmanaged.passRetained(event) }
            let keyCode = (data1 & 0xFFFF0000) >> 16

            // NX_KEYTYPE_SOUND_UP = 0, NX_KEYTYPE_SOUND_DOWN = 1, NX_KEYTYPE_MUTE = 7
            if keyCode == 0 || keyCode == 1 || keyCode == 7 {
                // Swallow the event by returning nil
                return nil
            }

            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: nil
        ) else {
            print("\(debugMarker) AudioMuter: failed to create CGEventTap (Accessibility permission needed)")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("\(debugMarker) AudioMuter: CGEventTap installed")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        print("\(debugMarker) AudioMuter: CGEventTap removed")
    }
}
