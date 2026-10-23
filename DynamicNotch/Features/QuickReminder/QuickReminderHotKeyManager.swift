// QuickReminderHotKeyManager.swift
// DynamicNotch / Features / QuickReminder
//
// Apple-grade global keyboard shortcut manager for Dynamic Notch Quick Reminder.
// Listens for Option + Shift + R (⌥ + ⇧ + R) via Carbon RegisterEventHotKey.
// Provides instantaneous, zero-permission, system-wide hotkey orchestration.

import AppKit
import Carbon

final class QuickReminderHotKeyManager {

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

    // MARK: - Carbon HotKey Registration (Option + Shift + R)

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
                // Match signature 'DNCH' and ID 8 (Quick Reminder)
                if err == noErr && hotKeyID.signature == OSType(0x444E4348) && hotKeyID.id == 8 {
                    let manager = Unmanaged<QuickReminderHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + R (kVK_ANSI_R = 15, Signature 'DNCH', ID 8)
        let hotKeyID = EventHotKeyID(signature: OSType(0x444E4348), id: 8)
        let optionShiftModifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            optionShiftModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
