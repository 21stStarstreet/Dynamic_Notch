// QuickNoteHotKeyManager.swift
// DynamicNotch / Features / QuickNote
//
// Apple-grade global keyboard shortcut manager for the Dynamic Notch Quick Note.
// Listens for Option + Shift + N (⌥ + ⇧ + N) via Carbon RegisterEventHotKey.
// Provides instantaneous, zero-permission, system-wide hotkey triggering.

import AppKit
import Carbon

final class QuickNoteHotKeyManager {

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

    // MARK: - Carbon HotKey Registration (Option + Shift + N)

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
                // Match signature 'DNCH' and ID 7 (Quick Note)
                if err == noErr && hotKeyID.signature == OSType(0x444E4348) && hotKeyID.id == 7 {
                    let manager = Unmanaged<QuickNoteHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + N (kVK_ANSI_N = 0x2D / 45, Signature 'DNCH', ID 7)
        let hotKeyID = EventHotKeyID(signature: OSType(0x444E4348), id: 7)
        let optionShiftModifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            optionShiftModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
