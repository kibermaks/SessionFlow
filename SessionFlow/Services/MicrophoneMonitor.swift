import Foundation
import CoreAudio
import Combine

class MicrophoneMonitor: ObservableObject {
    @Published private(set) var isMicActive = false
    /// True when the default input and output devices are the same hardware
    /// (e.g. Thunderbolt Display), which causes false mic activation from audio playback.
    @Published private(set) var inputOutputSharedDevice = false
    @Published private(set) var sharedDeviceName: String?

    private var runningListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedDevice: AudioDeviceID = 0

    init() {
        observeDefaultInputDevice()
        checkSharedDevice()
    }

    deinit {
        removeAllListeners()
    }

    private func observeDefaultInputDevice() {
        // Get default input device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return }

        observedDevice = deviceID
        updateMicState()

        // Listen for changes to "is running somewhere"
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateMicState() }
        }
        runningListenerBlock = block

        AudioObjectAddPropertyListenerBlock(deviceID, &runningAddress, DispatchQueue.main, block)

        // Listen for default input device changes
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.removeAllListeners()
                self?.observeDefaultInputDevice()
                self?.checkSharedDevice()
            }
        }
        defaultDeviceListenerBlock = deviceBlock

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            deviceBlock
        )
    }

    private func updateMicState() {
        guard observedDevice != 0 else { return }

        // Check if input device has input streams running
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(observedDevice, &address, 0, nil, &size, &isRunning)

        let active = (status == noErr && isRunning != 0)
        if isMicActive != active {
            isMicActive = active
        }
    }

    /// Checks whether the default input and output devices are the same hardware.
    private func checkSharedDevice() {
        let inputID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        let outputID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let shared = inputID != 0 && inputID == outputID
        if inputOutputSharedDevice != shared {
            inputOutputSharedDevice = shared
            sharedDeviceName = shared ? deviceName(for: inputID) : nil
        }
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return nil }
        var name: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let cf = name?.takeUnretainedValue() else { return nil }
        return cf as String
    }

    private func removeAllListeners() {
        if let block = runningListenerBlock, observedDevice != 0 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(observedDevice, &address, DispatchQueue.main, block)
            runningListenerBlock = nil
        }
        if let block = defaultDeviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
            )
            defaultDeviceListenerBlock = nil
        }
    }
}
