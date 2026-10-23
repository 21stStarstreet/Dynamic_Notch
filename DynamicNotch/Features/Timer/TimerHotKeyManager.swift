// TimerHotKeyManager.swift
// DynamicNotch / Features / Timer
//
// Apple-grade global keyboard shortcut manager for the Dynamic Notch Timer.
// Listens for Option + Shift + T (⌥ + ⇧ + T) via Carbon RegisterEventHotKey.
//
// Characteristics:
// ─────────────────
// • Zero Permissions: Requires 0 Accessibility / Input Monitoring permissions.
// • System Integrity: Filtered by signature ('DNTM') to prevent event crosstalk.
// • Latency: Instantaneous hardware-level dispatch directly on main thread.

import AppKit
import Carbon

final class TimerHotKeyManager {

    var onTrigger: (() -> Void)?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Signature 'DNTM' (0x444E544D), ID 1
    private let timerSignature = OSType(0x444E544D)
    private let timerHotKeyID = UInt32(1)

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
                if err == noErr && hotKeyID.signature == OSType(0x444E544D) {
                    let manager = Unmanaged<TimerHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + T
        let hotKeyID = EventHotKeyID(signature: timerSignature, id: timerHotKeyID)
        let modifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
