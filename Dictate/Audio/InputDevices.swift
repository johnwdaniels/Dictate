import Combine
import CoreAudio
import Foundation

/// Microphones from Core Audio. The choice is saved as the device UID, which survives restarts and replugging.
enum InputDevices {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    static let storageKey = "audio.inputDeviceUID"

    /// Empty means the system default.
    static var selectedUID: String {
        UserDefaults.standard.string(forKey: storageKey) ?? ""
    }

    static func all() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                  let name = string(kAudioObjectPropertyName, of: id) else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    static func defaultInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    /// The device to record from: the saved choice when it is connected, otherwise the system default.
    static func resolvedInputID(selectedUID: String = selectedUID, devices: [Device] = all()) -> AudioDeviceID? {
        if !selectedUID.isEmpty, let chosen = devices.first(where: { $0.uid == selectedUID }) {
            return chosen.id
        }
        return defaultInputID()
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

/// Keeps the Settings picker current as microphones are plugged in or removed, or the system default changes.
@MainActor
final class InputDeviceList: ObservableObject {
    @Published private(set) var devices: [InputDevices.Device] = []
    @Published private(set) var defaultName = ""

    private var listening = false
    private let listener: AudioObjectPropertyListenerBlock

    init() {
        weak var weakSelf: InputDeviceList?
        listener = { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { weakSelf?.refresh() }
            }
        }
        weakSelf = self
        refresh()
    }

    func startListening() {
        guard !listening else { return }
        listening = true
        for selector in Self.selectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }

    func stopListening() {
        guard listening else { return }
        listening = false
        for selector in Self.selectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }

    func refresh() {
        devices = InputDevices.all()
        let defaultID = InputDevices.defaultInputID()
        defaultName = devices.first { $0.id == defaultID }?.name ?? ""
    }

    private static let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
