// SpotifyPermissionHotKeyManager.swift
// DynamicNotch / Features / NowPlaying
//
// Apple-grade global keyboard shortcut manager for Dynamic Notch Spotify Permission HUD test.
// Listens for Option + Shift + S (⌥ + ⇧ + S) via Carbon RegisterEventHotKey.
// Provides instantaneous, zero-permission, system-wide hotkey orchestration.

import AppKit
import Carbon

final class SpotifyPermissionHotKeyManager {

    var onTrigger: (() -> Void)?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        setupCarbonHotKey()
    }

    deinit {
        tearDown()
    }

    func tearDown() {
        if let hk = carbonHotKeyRef {
            UnregisterEventHotKey(hk)
            carbonHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    // MARK: - Carbon HotKey Registration (Option + Shift + S)

    private func setupCarbonHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (handler, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                // Match signature 'DNCH' and ID 9 (Spotify Permission Test)
                if err == noErr && hotKeyID.signature == OSType(0x444E4348) && hotKeyID.id == 9 {
                    let manager = Unmanaged<SpotifyPermissionHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        manager.onTrigger?()
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else { return }

        // Register Option + Shift + S (kVK_ANSI_S = 0x01 / 1, Signature 'DNCH', ID 9)
        let hotKeyID = EventHotKeyID(signature: OSType(0x444E4348), id: 9)
        let optionShiftModifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            optionShiftModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
