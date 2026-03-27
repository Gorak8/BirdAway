import CoreAudio
import Foundation

struct AudioDevice: Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        return lhs.uid == rhs.uid
    }
}

protocol AudioDeviceManagerDelegate: AnyObject {
    func devicesDidChange(_ manager: AudioDeviceManager)
    func deviceDidDisconnect(_ device: AudioDevice, manager: AudioDeviceManager)
}

class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    weak var delegate: AudioDeviceManagerDelegate?
    private(set) var outputDevices: [AudioDevice] = []

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refresh()
        startListening()
    }

    func refresh() {
        outputDevices = enumerateOutputDevices()
    }

    func deviceWithUID(_ uid: String) -> AudioDevice? {
        return outputDevices.first { $0.uid == uid }
    }

    // MARK: - CoreAudio Enumeration

    private func enumerateOutputDevices() -> [AudioDevice] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { deviceID -> AudioDevice? in
            // Only include devices that have output streams
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return nil }

            let name = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Unknown Device"
            let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
            return AudioDevice(id: deviceID, name: name, uid: uid)
        }
    }

    private func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    // MARK: - Change Notifications

    private func startListening() {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let before = self.outputDevices
            self.refresh()
            let after = self.outputDevices

            for old in before where !after.contains(where: { $0.uid == old.uid }) {
                self.delegate?.deviceDidDisconnect(old, manager: self)
            }
            self.delegate?.devicesDidChange(self)
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, DispatchQueue.main, block
        )
    }

    deinit {
        guard let block = listenerBlock else { return }
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, DispatchQueue.main, block
        )
    }
}
