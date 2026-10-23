// KeyboardBrightnessHotKeyManager.swift
// DynamicNotch / Features / KeyboardHUD
//
// Apple-grade global keyboard shortcut manager for Keyboard Backlight illumination.
// Designed specifically for Apple Silicon MacBooks without physical F5/F6 brightness keys.
//
// Registered Shortcuts (Requires ZERO Accessibility or Input Monitoring permissions):
// • ⌥ + F5 (Option + F5) or ⌃ + ⌥ + ↓ : Step down keyboard brightness (1/16th)
// • ⌥ + F6 (Option + F6) or ⌃ + ⌥ + ↑ : Step up keyboard brightness (1/16th)
// • ⇧ + ⌥ + F5 or ⌃ + ⌥ + ⇧ + ↓       : Fine-tune step down (1/64th)
// • ⇧ + ⌥ + F6 or ⌃ + ⌥ + ⇧ + ↑       : Fine-tune step up (1/64th)

import AppKit
import Carbon

final class KeyboardBrightnessHotKeyManager {

    var onStepUp: ((Bool) -> Void)?
    var onStepDown: ((Bool) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    // Signature 'DNKB' (0x444E4B42)
    private let signature = OSType(0x444E4B42)

    private enum HotKeyID: UInt32 {
        case stepDownF5 = 1
        case stepUpF6 = 2
        case fineDownF5 = 3
        case fineUpF6 = 4
        case stepDownArrow = 5
        case stepUpArrow = 6
        case fineDownArrow = 7
        case fineUpArrow = 8
    }

    init(
        onStepUp: @escaping (Bool) -> Void,
        onStepDown: @escaping (Bool) -> Void
    ) {
        self.onStepUp = onStepUp
        self.onStepDown = onStepDown
        setupCarbonHotKeys()
    }

    deinit {
        tearDown()
    }

    func tearDown() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    private func setupCarbonHotKeys() {
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
                guard err == noErr else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<KeyboardBrightnessHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                guard hotKeyID.signature == manager.signature else { return OSStatus(eventNotHandledErr) }

                DispatchQueue.main.async {
                    switch hotKeyID.id {
                    case HotKeyID.stepDownF5.rawValue, HotKeyID.stepDownArrow.rawValue:
                        manager.onStepDown?(false)
                    case HotKeyID.stepUpF6.rawValue, HotKeyID.stepUpArrow.rawValue:
                        manager.onStepUp?(false)
                    case HotKeyID.fineDownF5.rawValue, HotKeyID.fineDownArrow.rawValue:
                        manager.onStepDown?(true)
                    case HotKeyID.fineUpF6.rawValue, HotKeyID.fineUpArrow.rawValue:
                        manager.onStepUp?(true)
                    default:
                        break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else { return }

        // Key Codes
        let kVK_F5: UInt32 = 0x60       // 96
        let kVK_F6: UInt32 = 0x61       // 97
        let kVK_DownArrow: UInt32 = 0x7D // 125
        let kVK_UpArrow: UInt32 = 0x7E   // 126

        // Modifiers
        let optMod = UInt32(optionKey)
        let optShiftMod = UInt32(optionKey | shiftKey)
        let ctrlOptMod = UInt32(controlKey | optionKey)
        let ctrlOptShiftMod = UInt32(controlKey | optionKey | shiftKey)

        registerHotKey(id: .stepDownF5, keyCode: kVK_F5, modifiers: optMod)
        registerHotKey(id: .stepUpF6, keyCode: kVK_F6, modifiers: optMod)
        registerHotKey(id: .fineDownF5, keyCode: kVK_F5, modifiers: optShiftMod)
        registerHotKey(id: .fineUpF6, keyCode: kVK_F6, modifiers: optShiftMod)

        registerHotKey(id: .stepDownArrow, keyCode: kVK_DownArrow, modifiers: ctrlOptMod)
        registerHotKey(id: .stepUpArrow, keyCode: kVK_UpArrow, modifiers: ctrlOptMod)
        registerHotKey(id: .fineDownArrow, keyCode: kVK_DownArrow, modifiers: ctrlOptShiftMod)
        registerHotKey(id: .fineUpArrow, keyCode: kVK_UpArrow, modifiers: ctrlOptShiftMod)
    }

    private func registerHotKey(id: HotKeyID, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        }
    }
}
