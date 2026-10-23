// CalendarHotKeyManager.swift
// DynamicNotch / Features / Calendar
//
// Apple-grade global keyboard shortcut manager for instant Calendar card toggle.
// Listens for Option + Shift + C (⌥ + ⇧ + C) via Carbon RegisterEventHotKey.

import AppKit
import Carbon

final class CalendarHotKeyManager {

    var onTrigger: (() -> Void)?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Signature 'DNCL' (0x444E434C), ID 1
    private let calendarSignature = OSType(0x444E434C)
    private let calendarHotKeyID = UInt32(1)

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
                if err == noErr && hotKeyID.signature == OSType(0x444E434C) {
                    let manager = Unmanaged<CalendarHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + C (kVK_ANSI_C = 0x08)
        let hotKeyID = EventHotKeyID(signature: calendarSignature, id: calendarHotKeyID)
        let modifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
