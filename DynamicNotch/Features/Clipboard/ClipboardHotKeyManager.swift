// ClipboardHotKeyManager.swift
// DynamicNotch / Features / Clipboard
//
// Apple-grade global keyboard shortcut manager for the Dynamic Notch Clipboard History.
// Listens for Command (Cmd) key held down for > 2.0 seconds (and Option + Shift + V as instant shortcut).
//
// Architecture:
// ─────────────
// 1. Long-Press Cmd Detector (NSEvent .flagsChanged + .keyDown):
//    • Starts a 2.0-second timer whenever the Command key is pressed alone.
//    • Automatically cancels the timer if Command is released before 2.0 seconds, or if
//      another key is pressed (e.g. Cmd + C, Cmd + Tab, Cmd + V), ensuring normal system
//      shortcuts are never interrupted.
//    • If Command is held continuously for 2.0 seconds, opens the Dynamic Notch clipboard history.
// 2. Carbon Global Event HotKey (RegisterEventHotKey):
//    • Provides an instant, zero-permission shortcut for `Option + Shift + V`.

import AppKit
import Carbon

final class ClipboardHotKeyManager {

    var onTrigger: (() -> Void)?

    private let requiredHoldDuration: TimeInterval = 2.0

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var carbonHotKeyRefOptShiftV: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private var commandHoldWorkItem: DispatchWorkItem?
    private var isCommandDown: Bool = false
    private var hasTriggeredForCurrentPress: Bool = false

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        setupMonitors()
        setupCarbonHotKeys()
    }

    deinit {
        tearDown()
    }

    func tearDown() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        if let hk = carbonHotKeyRefOptShiftV {
            UnregisterEventHotKey(hk)
            carbonHotKeyRefOptShiftV = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        commandHoldWorkItem?.cancel()
        commandHoldWorkItem = nil
    }

    // MARK: - Carbon HotKey Registration (Cmd + Shift + V)

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
                if err == noErr && hotKeyID.signature == OSType(0x444E4348) {
                    let manager = Unmanaged<ClipboardHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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

        // Register Option + Shift + V (Signature 'DNCH', ID 2)
        let hotKeyIDShift = EventHotKeyID(signature: OSType(0x444E4348), id: 2)
        let optionShiftModifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            optionShiftModifiers,
            hotKeyIDShift,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRefOptShiftV
        )
    }

    // MARK: - NSEvent Monitors (Cmd held for > 3 seconds)

    private func setupMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.handleEvent(event)
            }
        }

        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.handleEvent(event)
                return event
            }
        }
    }

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            evaluateFlagsChanged(event)
        case .keyDown:
            evaluateKeyDown(event)
        default:
            break
        }
    }

    private func evaluateFlagsChanged(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isOnlyCommand = (modifiers == .command)

        if isOnlyCommand {
            guard !isCommandDown else { return }
            isCommandDown = true
            hasTriggeredForCurrentPress = false

            commandHoldWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isCommandDown, !self.hasTriggeredForCurrentPress else { return }
                self.hasTriggeredForCurrentPress = true
                self.onTrigger?()
            }
            commandHoldWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + requiredHoldDuration, execute: work)
        } else {
            isCommandDown = false
            hasTriggeredForCurrentPress = false
            commandHoldWorkItem?.cancel()
            commandHoldWorkItem = nil
        }
    }

    private func evaluateKeyDown(_ event: NSEvent) {
        // Any key press while Command is held means the user is executing a standard shortcut (e.g. Cmd+C, Cmd+Tab, Cmd+V)
        // Cancel the hold timer immediately so normal shortcuts proceed without interruption.
        commandHoldWorkItem?.cancel()
        commandHoldWorkItem = nil
    }
}
