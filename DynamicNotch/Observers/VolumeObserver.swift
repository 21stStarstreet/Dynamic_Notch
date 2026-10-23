// VolumeObserver.swift
// DynamicNotch / Observers
//
// Listens to the system default audio output device's virtual main volume
// using CoreAudio / AudioToolbox property listeners.
//
// Design decisions
// ─────────────────
// • AudioObjectAddPropertyListenerBlock delivers callbacks on DispatchQueue.main.
// • Initial volume read when attaching to a device seeds `lastKnownVolume` without
//   publishing a spurious HUD event on app launch.
// • Supports both `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (from
//   AudioToolbox) and per-channel `kAudioDevicePropertyVolumeScalar` fallback for
//   external audio interfaces.
// • A 0.01 threshold filter prevents hair-trigger updates from floating-point
//   rounding; macOS volume steps are 0.0625 (1/16th).

import Foundation
import CoreAudio
import AudioToolbox

final class VolumeObserver: ObservableObject {

    /// Current normalized output volume (0.0 … 1.0).
    @Published private(set) var volume: Float = 0.5

    /// Current hardware/driver mute state (`true` = muted).
    @Published private(set) var isMuted: Bool = false

    /// Active audio output device name read from CoreAudio (e.g. "MacBook Pro Hoparlörleri", "AirPods Pro").
    @Published private(set) var outputDeviceName: String = "Mac Hoparlörleri"

    /// Synchronous snapshot of the active output device name for dynamic layout sizing in `NotchSizeCalculator`.
    static private(set) var currentOutputDeviceName: String = "Mac Hoparlörleri"

    /// Emits only on genuine user/system volume changes (never on initial launch seed).
    @Published private(set) var volumeChangeEvent: Float? = nil

    /// Emits only when the output device is muted (`true`) or unmuted (`false`).
    @Published private(set) var muteChangeEvent: Bool? = nil

    private var lastKnownVolume: Float = -1.0
    private var lastKnownMuted: Bool? = nil
    private var lastMuteEventTime: Date = .distantPast

    private var currentDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var propertyListener: AudioObjectPropertyListenerBlock?
    private var mutePropertyListener: AudioObjectPropertyListenerBlock?
    private var namePropertyListener: AudioObjectPropertyListenerBlock?
    private var deviceChangeListener: AudioObjectPropertyListenerBlock?

    // MARK: - Init / Deinit

    init() {
        setupDeviceChangeListener()
        updateDevice(isInitial: true)
    }

    deinit {
        tearDownVolumeListener()
        tearDownDeviceChangeListener()
    }

    // MARK: - Default Device Change Listener

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope:    kAudioObjectPropertyScopeGlobal,
        mElement:  kAudioObjectPropertyElementMain
    )

    private func setupDeviceChangeListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.updateDevice(isInitial: false)
        }
        deviceChangeListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            block
        )
    }

    private func tearDownDeviceChangeListener() {
        guard let block = deviceChangeListener else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Volume, Mute & Name Property Listeners

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope:    kAudioDevicePropertyScopeOutput,
        mElement:  kAudioObjectPropertyElementMain
    )

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope:    kAudioDevicePropertyScopeOutput,
        mElement:  kAudioObjectPropertyElementMain
    )

    private var deviceNameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope:    kAudioObjectPropertyScopeGlobal,
        mElement:  kAudioObjectPropertyElementMain
    )

    private func setupVolumeListener(for deviceID: AudioObjectID, isInitial: Bool) {
        // Seed initial device name, mute, and volume state before attaching listener callbacks
        fetchOutputDeviceName(from: deviceID)
        fetchMute(from: deviceID, shouldPublishEvent: !isInitial)
        fetchVolume(from: deviceID, shouldPublishEvent: !isInitial)

        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.fetchOutputDeviceName(from: deviceID)
            self?.fetchVolume(from: deviceID, shouldPublishEvent: true)
        }
        propertyListener = volBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, volBlock)

        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.fetchOutputDeviceName(from: deviceID)
            self?.fetchMute(from: deviceID, shouldPublishEvent: true)
        }
        mutePropertyListener = muteBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, muteBlock)

        let nameBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.fetchOutputDeviceName(from: deviceID)
        }
        namePropertyListener = nameBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &deviceNameAddress, DispatchQueue.main, nameBlock)
    }

    private func tearDownVolumeListener() {
        guard currentDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        if let volBlock = propertyListener {
            AudioObjectRemovePropertyListenerBlock(
                currentDeviceID, &volumeAddress, DispatchQueue.main, volBlock
            )
            propertyListener = nil
        }
        if let muteBlock = mutePropertyListener {
            AudioObjectRemovePropertyListenerBlock(
                currentDeviceID, &muteAddress, DispatchQueue.main, muteBlock
            )
            mutePropertyListener = nil
        }
        if let nameBlock = namePropertyListener {
            AudioObjectRemovePropertyListenerBlock(
                currentDeviceID, &deviceNameAddress, DispatchQueue.main, nameBlock
            )
            namePropertyListener = nil
        }
    }

    private func updateDevice(isInitial: Bool) {
        let newDevice = defaultOutputDevice()
        guard newDevice != currentDeviceID else {
            fetchOutputDeviceName(from: currentDeviceID)
            return
        }

        tearDownVolumeListener()
        currentDeviceID = newDevice
        guard currentDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        setupVolumeListener(for: currentDeviceID, isInitial: isInitial)
    }

    // MARK: - Output Device Name Fetch

    private func fetchOutputDeviceName(from deviceID: AudioObjectID) {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        var address = deviceNameAddress
        var unmanagedName: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &unmanagedName) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                UnsafeMutableRawPointer(ptr)
            )
        }

        if status == noErr, let cfName = unmanagedName?.takeRetainedValue() {
            let trimmed = (cfName as String).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Self.currentOutputDeviceName = trimmed
                if outputDeviceName != trimmed {
                    outputDeviceName = trimmed
                }
            }
        }
    }

    // MARK: - Mute Fetch

    private func fetchMute(from deviceID: AudioObjectID, shouldPublishEvent: Bool) {
        var mutedVal: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddress

        var status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &mutedVal)
        if status != noErr {
            var ch1MuteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  1
            )
            status = AudioObjectGetPropertyData(deviceID, &ch1MuteAddr, 0, nil, &size, &mutedVal)
        }

        guard status == noErr else { return }
        let muted = (mutedVal != 0)

        if !shouldPublishEvent || lastKnownMuted == nil {
            lastKnownMuted = muted
            isMuted = muted
            return
        }

        if muted != lastKnownMuted {
            lastKnownMuted = muted
            isMuted = muted
            lastMuteEventTime = Date()
            muteChangeEvent = muted
        }
    }

    // MARK: - Volume Fetch

    private func fetchVolume(from deviceID: AudioObjectID, shouldPublishEvent: Bool) {
        var vol: Float = 0.0
        var size = UInt32(MemoryLayout<Float>.size)
        var addr = volumeAddress

        var status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)

        // Fallback to channel 1 scalar if VirtualMainVolume is not exposed by this device
        if status != noErr {
            var ch1Addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  1
            )
            status = AudioObjectGetPropertyData(deviceID, &ch1Addr, 0, nil, &size, &vol)
        }

        guard status == noErr else { return }

        let clamped = min(max(vol, 0.0), 1.0)

        if !shouldPublishEvent || lastKnownVolume < 0 {
            lastKnownVolume = clamped
            volume = clamped
            return
        }

        // Suppress duplicate volume event if a hardware Mute toggle just fired within 180ms
        if Date().timeIntervalSince(lastMuteEventTime) < 0.18 {
            lastKnownVolume = clamped
            volume = clamped
            return
        }

        if abs(clamped - lastKnownVolume) > 0.01 {
            let wasSilent = lastKnownVolume <= 0.005
            let isNowSilent = clamped <= 0.005
            lastKnownVolume = clamped
            volume = clamped

            if isNowSilent && !wasSilent {
                isMuted = true
                lastKnownMuted = true
                muteChangeEvent = true
            } else {
                if !isNowSilent && isMuted {
                    isMuted = false
                    lastKnownMuted = false
                }
                volumeChangeEvent = clamped
            }
        }
    }

    // MARK: - Interactive Control (from Expanded HUD)

    func setVolume(_ newVolume: Float) {
        let deviceID = currentDeviceID != AudioObjectID(kAudioObjectUnknown)
            ? currentDeviceID
            : defaultOutputDevice()
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        var clamped = min(max(newVolume, 0.0), 1.0)
        let size = UInt32(MemoryLayout<Float>.size)
        var addr = volumeAddress

        if isMuted && clamped > 0.005 {
            var unmuteVal: UInt32 = 0
            var mAddr = muteAddress
            AudioObjectSetPropertyData(deviceID, &mAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuteVal)
            isMuted = false
            lastKnownMuted = false
        }

        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &clamped)
        if status != noErr {
            var ch1Addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  1
            )
            AudioObjectSetPropertyData(deviceID, &ch1Addr, 0, nil, size, &clamped)
        }

        lastKnownVolume = clamped
        volume = clamped
    }

    func toggleMute() {
        let deviceID = currentDeviceID != AudioObjectID(kAudioObjectUnknown)
            ? currentDeviceID
            : defaultOutputDevice()
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        let targetMuted = !isMuted
        var muteVal: UInt32 = targetMuted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddress

        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &muteVal)
        if status != noErr {
            var ch1MuteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  1
            )
            AudioObjectSetPropertyData(deviceID, &ch1MuteAddr, 0, nil, size, &muteVal)
        }

        lastKnownMuted = targetMuted
        isMuted = targetMuted
        lastMuteEventTime = Date()
    }

    // MARK: - Helpers

    private func defaultOutputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size     = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr     = defaultDeviceAddress
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        return deviceID
    }
}
