// ExternalDriveHotKeyManager.swift
// DynamicNotch / Features / ExternalDrive
//
// Apple-grade global keyboard shortcut manager for instant External Drive card toggle.
// Listens for Option + Shift + E (⌥ + ⇧ + E) via Carbon RegisterEventHotKey.

import AppKit
import Carbon

final class ExternalDriveHotKeyManager {

    var onTrigger: (() -> Void)?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Signature 'DNDR' (0x444E4452), ID 1
    private let driveSignature = OSType(0x444E4452)
    private let driveHotKeyID = UInt32(1)

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
                if err == noErr && hotKeyID.signature == OSType(0x444E4452) {
                    let manager = Unmanaged<ExternalDriveHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + E (kVK_ANSI_E = 0x0E)
        let hotKeyID = EventHotKeyID(signature: driveSignature, id: driveHotKeyID)
        let modifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
    }
}
