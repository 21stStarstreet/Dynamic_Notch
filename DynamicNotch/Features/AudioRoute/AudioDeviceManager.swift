// AudioDeviceManager.swift
// DynamicNotch / Features / AudioRoute
//
// Thread-safe CoreAudio manager discovering available audio output endpoints
// and switching the macOS default output device programmatically.

import Foundation
import CoreAudio
import AudioToolbox
import AppKit

@MainActor
final class AudioDeviceManager: ObservableObject {

    static let shared = AudioDeviceManager()

    @Published private(set) var outputDevices: [AudioDeviceItem] = []
    @Published private(set) var currentDefaultDevice: AudioDeviceItem? = nil
    @Published private(set) var inputDevices: [AudioDeviceItem] = []
    @Published private(set) var currentDefaultInputDevice: AudioDeviceItem? = nil
    @Published private(set) var inputVolume: Float = 0.5
    @Published private(set) var isInputMuted: Bool = false

    private var inputVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var inputMuteListenerBlock: AudioObjectPropertyListenerBlock?
    private var trackedInputDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)

    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        refreshDevices()
        setupListeners()
    }

    // MARK: - CoreAudio Device Discovery

    func refreshDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        let defaultID = getDefaultOutputDeviceID()
        var list: [AudioOutputDevice] = []

        for deviceID in deviceIDs {
            // Filter: Only include devices with active output channels/streams
            guard hasOutputStreams(deviceID: deviceID) else { continue }

            let name = getDeviceName(deviceID: deviceID)
            guard !name.isEmpty else { continue }

            let uid = getDeviceUID(deviceID: deviceID)
            let transport = getDeviceTransportType(deviceID: deviceID)
            let isDefault = (deviceID == defaultID)

            list.append(AudioOutputDevice(
                id: deviceID,
                uid: uid,
                name: name,
                transportType: transport,
                isCurrentDefault: isDefault
            ))
        }

        // Sort: Active default device first, then built-in speakers, then alphabetical
        list.sort { d1, d2 in
            if d1.isCurrentDefault { return true }
            if d2.isCurrentDefault { return false }
            if d1.transportType == .builtIn && d2.transportType != .builtIn { return true }
            if d1.transportType != .builtIn && d2.transportType == .builtIn { return false }
            return d1.name.localizedCaseInsensitiveCompare(d2.name) == .orderedAscending
        }

        self.outputDevices = list
        self.currentDefaultDevice = list.first(where: { $0.isCurrentDefault })

        // Input Devices (Microphones)
        let defaultInputID = getDefaultInputDeviceID()
        var inList: [AudioDeviceItem] = []

        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID: deviceID) else { continue }
            let name = getDeviceName(deviceID: deviceID)
            guard !name.isEmpty else { continue }
            let uid = getDeviceUID(deviceID: deviceID)
            let transport = getDeviceTransportType(deviceID: deviceID)
            let isDefault = (deviceID == defaultInputID)

            inList.append(AudioDeviceItem(
                id: deviceID,
                uid: uid,
                name: name,
                transportType: transport,
                isCurrentDefault: isDefault,
                isInput: true
            ))
        }

        inList.sort { d1, d2 in
            if d1.isCurrentDefault { return true }
            if d2.isCurrentDefault { return false }
            return d1.name.localizedCaseInsensitiveCompare(d2.name) == .orderedAscending
        }

        self.inputDevices = inList
        self.currentDefaultInputDevice = inList.first(where: { $0.isCurrentDefault })

        if let defaultInput = self.currentDefaultInputDevice {
            setupInputListeners(deviceID: defaultInput.id)
            refreshInputVolume()
        } else {
            removeInputListeners()
        }
    }

    // MARK: - Programmatic Output & Input Switching

    @discardableResult
    func setDefaultOutputDevice(_ device: AudioOutputDevice) -> Bool {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var targetID = device.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            size,
            &targetID
        )

        if status == noErr {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            refreshDevices()
            return true
        }
        return false
    }

    @discardableResult
    func setDefaultInputDevice(_ device: AudioDeviceItem) -> Bool {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var targetID = device.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            size,
            &targetID
        )

        if status == noErr {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            refreshDevices()
            return true
        }
        return false
    }

    // MARK: - Input Volume & Mute Controls

    func refreshInputVolume() {
        guard let defaultInput = currentDefaultInputDevice else { return }
        let deviceID = defaultInput.id

        var vol: Float = 0.5
        var size = UInt32(MemoryLayout<Float>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        if status != noErr {
            addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeInput,
                mElement:  kAudioObjectPropertyElementMain
            )
            status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        }
        if status != noErr {
            addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeInput,
                mElement:  1
            )
            status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        }

        if status == noErr {
            self.inputVolume = min(max(vol, 0.0), 1.0)
        }

        var muteVal: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var muteStatus = AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &muteSize, &muteVal)
        if muteStatus != noErr {
            muteAddr.mElement = 1
            muteStatus = AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &muteSize, &muteVal)
        }
        if muteStatus == noErr {
            self.isInputMuted = (muteVal != 0)
        }
    }

    func setDefaultInputVolume(_ level: Float) {
        guard let defaultInput = currentDefaultInputDevice else { return }
        let deviceID = defaultInput.id
        var clamped = min(max(level, 0.0), 1.0)
        let size = UInt32(MemoryLayout<Float>.size)

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &clamped)
        if status != noErr {
            addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeInput,
                mElement:  kAudioObjectPropertyElementMain
            )
            status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &clamped)
        }
        if status != noErr {
            addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeInput,
                mElement:  1
            )
            _ = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &clamped)
        }

        self.inputVolume = clamped
        if isInputMuted && clamped > 0.005 {
            toggleInputMute()
        }
    }

    func toggleInputMute() {
        guard let defaultInput = currentDefaultInputDevice else { return }
        let deviceID = defaultInput.id
        let targetMuted = !isInputMuted
        var muteVal: UInt32 = targetMuted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &muteVal)
        if status != noErr {
            addr.mElement = 1
            _ = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &muteVal)
        }
        self.isInputMuted = targetMuted
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func setupInputListeners(deviceID: AudioObjectID) {
        removeInputListeners()
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        trackedInputDeviceID = deviceID

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshInputVolume()
            }
        }
        inputVolumeListenerBlock = block
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshInputVolume()
            }
        }
        inputMuteListenerBlock = muteBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main, muteBlock)
    }

    private func removeInputListeners() {
        guard trackedInputDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        if let block = inputVolumeListenerBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope:    kAudioDevicePropertyScopeInput,
                mElement:  kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(trackedInputDeviceID, &addr, DispatchQueue.main, block)
            inputVolumeListenerBlock = nil
        }
        if let muteBlock = inputMuteListenerBlock {
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope:    kAudioDevicePropertyScopeInput,
                mElement:  kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(trackedInputDeviceID, &muteAddr, DispatchQueue.main, muteBlock)
            inputMuteListenerBlock = nil
        }
        trackedInputDeviceID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - CoreAudio Low-Level Helpers

    private func getDefaultOutputDeviceID() -> AudioObjectID {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultDeviceID = AudioObjectID(kAudioObjectUnknown)
        var defaultSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultDeviceID
        )
        return status == noErr ? defaultDeviceID : AudioObjectID(kAudioObjectUnknown)
    }

    private func hasOutputStreams(deviceID: AudioObjectID) -> Bool {
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &streamAddress,
            0,
            nil,
            &streamSize
        )
        return status == noErr && streamSize > 0
    }

    private func getDefaultInputDeviceID() -> AudioObjectID {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultDeviceID = AudioObjectID(kAudioObjectUnknown)
        var defaultSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultDeviceID
        )
        return status == noErr ? defaultDeviceID : AudioObjectID(kAudioObjectUnknown)
    }

    private func hasInputStreams(deviceID: AudioObjectID) -> Bool {
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &streamAddress,
            0,
            nil,
            &streamSize
        )
        return status == noErr && streamSize > 0
    }

    private func getDeviceName(deviceID: AudioObjectID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>? = nil
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &unmanagedName
        )
        if status == noErr, let unmanaged = unmanagedName {
            let name = unmanaged.takeRetainedValue() as String
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func getDeviceUID(deviceID: AudioObjectID) -> String {
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>? = nil
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &unmanagedUID
        )
        if status == noErr, let unmanaged = unmanagedUID {
            let uid = unmanaged.takeRetainedValue() as String
            return uid
        }
        return ""
    }

    private func getDeviceTransportType(deviceID: AudioObjectID) -> AudioDeviceTransportType {
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rawTransport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &rawTransport
        )
        guard status == noErr else { return .unknown }

        switch rawTransport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .hdmi
        default:
            return .unknown
        }
    }

    // MARK: - Hardware Event Listeners

    private func setupListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let dBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        devicesListenerBlock = dBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            dBlock
        )

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        defaultDeviceListenerBlock = defBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            DispatchQueue.main,
            defBlock
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defInBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        defaultInputDeviceListenerBlock = defInBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main,
            defInBlock
        )
    }

    private func removeListeners() {
        if let dBlock = devicesListenerBlock {
            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                DispatchQueue.main,
                dBlock
            )
        }
        if let defBlock = defaultDeviceListenerBlock {
            var defaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddress,
                DispatchQueue.main,
                defBlock
            )
        }
        if let defInBlock = defaultInputDeviceListenerBlock {
            var defaultInputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                DispatchQueue.main,
                defInBlock
            )
        }
    }
}
