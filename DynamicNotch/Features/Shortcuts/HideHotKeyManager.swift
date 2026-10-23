// HideHotKeyManager.swift
// DynamicNotch / Features / Shortcuts
//
// Apple-grade global keyboard shortcut manager to toggle hide/show of Dynamic Notch.
// Listens for Option + Shift + H (⌥ + ⇧ + H) via Carbon RegisterEventHotKey.
//
// Characteristics:
// ─────────────────
// • Zero Permissions: Requires 0 Accessibility / Input Monitoring permissions.
// • System Integrity: Filtered by signature ('DNHD') to prevent event crosstalk.
// • Latency: Instantaneous hardware-level dispatch directly on main thread.

import AppKit
import Carbon

final class HideHotKeyManager {

    var onTrigger: (() -> Void)?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Signature 'DNHD' (0x444E4844), ID 1
    private let hideSignature = OSType(0x444E4844)
    private let hideHotKeyID = UInt32(1)

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
                if err == noErr && hotKeyID.signature == OSType(0x444E4844) {
                    let manager = Unmanaged<HideHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + H (kVK_ANSI_H = 0x04)
        let hotKeyID = EventHotKeyID(signature: hideSignature, id: hideHotKeyID)
        let modifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
