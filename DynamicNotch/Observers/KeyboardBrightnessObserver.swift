// KeyboardBrightnessObserver.swift
// DynamicNotch / Observers
//
// Apple-grade Keyboard Backlight hardware observer and controller.
// Interfaces directly with Apple's private CoreBrightness framework (KeyboardBrightnessClient)
// to observe and control keyboard illumination across Apple Silicon and Intel MacBooks.
//
// Features:
// ─────────
// • Zero Privileges: Direct in-process dynamic linking via dlopen/dlsym; zero root/daemon needed.
// • Hardware Discovery: Automatically resolves keyboard backlight hardware IDs via copyKeyboardBacklightIDs.
// • Smart Intent Filtering: Distinguishes genuine user adjustments (Control Center, keys) from sensor micro-drifts.
// • System Illumination Key Interception: Listens to NX_KEYTYPE_ILLUMINATION_UP / DOWN system-defined events.
// • Exact Apple 16-Step Scale: Provides stepUp / stepDown quantized to 0.0625 (or 0.015625 fine steps).

import AppKit
import Combine
import CoreGraphics

final class KeyboardBrightnessObserver: ObservableObject {

    // MARK: - Published Properties

    /// Current keyboard brightness (0.0 … 1.0).
    @Published private(set) var brightness: Float = 0.5

    /// Emits only on genuine user brightness changes (never on app launch).
    @Published private(set) var brightnessChangeEvent: Float? = nil

    // MARK: - CoreBrightness Types & Handles

    private var clientInstance: AnyObject?
    private var keyboardID: UInt64?

    private typealias GetBrightnessFunc = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightnessFunc = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private var getBrightnessFunc: GetBrightnessFunc?
    private var setBrightnessFunc: SetBrightnessFunc?
    private var getBrightnessSel: Selector?
    private var setBrightnessSel: Selector?

    // MARK: - Monitoring & Polling

    private var pollTimer: AnyCancellable?
    private var systemKeyMonitorGlobal: Any?
    private var systemKeyMonitorLocal: Any?
    private var lastReportedBrightness: Float = -1.0
    private var lastManualChangeTime: Date = .distantPast

    /// Threshold for detecting deliberate user changes from Control Center (0.045 ≈ 4.5%).
    /// Ambient light sensor (ALS) micro-drifts transition continuously in micro-steps (< 0.015 per 80ms sample).
    /// Intentional slider drags in Control Center or keypresses jump by >= 0.045 in a single sample.
    private let manualAdjustmentThreshold: Float = 0.045

    // MARK: - Init / Deinit

    init() {
        loadCoreBrightness()
        seedInitialBrightness()
        startPolling()
        setupSystemIlluminationKeyMonitor()
    }

    deinit {
        pollTimer?.cancel()
        if let monitor = systemKeyMonitorGlobal {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = systemKeyMonitorLocal {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Framework Binding

    private func loadCoreBrightness() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil else {
            return
        }

        guard let kbcClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            return
        }

        let client = kbcClass.init()
        self.clientInstance = client

        // Discover Keyboard Backlight ID dynamically from hardware
        let copySel = NSSelectorFromString("copyKeyboardBacklightIDs")
        if client.responds(to: copySel),
           let unmanaged = client.perform(copySel),
           let ids = unmanaged.takeRetainedValue() as? [NSNumber],
           let firstID = ids.first {
            self.keyboardID = firstID.uint64Value
        } else {
            // Default fallback hardware ID on MacBooks
            self.keyboardID = 1
        }

        let getSel = NSSelectorFromString("brightnessForKeyboard:")
        if client.responds(to: getSel) {
            let imp = client.method(for: getSel)
            self.getBrightnessFunc = unsafeBitCast(imp, to: GetBrightnessFunc.self)
            self.getBrightnessSel = getSel
        }

        let setSel = NSSelectorFromString("setBrightness:forKeyboard:")
        if client.responds(to: setSel) {
            let imp = client.method(for: setSel)
            self.setBrightnessFunc = unsafeBitCast(imp, to: SetBrightnessFunc.self)
            self.setBrightnessSel = setSel
        }
    }

    // MARK: - Reading & Writing

    func readCurrentBrightness() -> Float? {
        guard let client = clientInstance,
              let kbID = keyboardID,
              let getFunc = getBrightnessFunc,
              let sel = getBrightnessSel else {
            return nil
        }

        let val = getFunc(client, sel, kbID)
        guard val >= 0.0 else { return nil }
        return max(0.0, min(1.0, val))
    }

    func setBrightness(_ newBrightness: Float) {
        guard let client = clientInstance,
              let kbID = keyboardID,
              let setFunc = setBrightnessFunc,
              let sel = setBrightnessSel else {
            return
        }

        let clamped = max(0.0, min(1.0, newBrightness))
        lastManualChangeTime = Date()
        let success = setFunc(client, sel, clamped, kbID)
        if success {
            lastReportedBrightness = clamped
            brightness = clamped
            brightnessChangeEvent = clamped
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    // MARK: - Apple 16-Step Quantized Stepping

    /// Steps brightness up by 1/16th (0.0625) or 1/64th (0.015625) fine step.
    func stepUp(fine: Bool = false) {
        let step: Float = fine ? 0.015625 : 0.0625
        let current = readCurrentBrightness() ?? brightness
        setBrightness(min(1.0, current + step))
    }

    /// Steps brightness down by 1/16th (0.0625) or 1/64th (0.015625) fine step.
    func stepDown(fine: Bool = false) {
        let step: Float = fine ? 0.015625 : 0.0625
        let current = readCurrentBrightness() ?? brightness
        setBrightness(max(0.0, current - step))
    }

    // MARK: - Seed & Polling

    private func seedInitialBrightness() {
        if let current = readCurrentBrightness() {
            brightness = current
            lastReportedBrightness = current
        }
    }

    private func startPolling() {
        // 80ms interval ensures instant pickup of Control Center adjustments
        pollTimer = Timer.publish(every: 0.08, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollBrightness()
            }
    }

    private func pollBrightness() {
        guard let current = readCurrentBrightness() else { return }

        // Initial baseline seed
        if lastReportedBrightness < 0 {
            lastReportedBrightness = current
            brightness = current
            return
        }

        let delta = abs(current - lastReportedBrightness)
        lastReportedBrightness = current
        brightness = current

        // Suppress poller while user is actively adjusting via keys or DynamicNotch
        // to prevent feedback loops while hardware LED ramps.
        guard Date().timeIntervalSince(lastManualChangeTime) > 0.6 else { return }

        // SMART INTENT FILTER:
        // Ambient Light Sensor (ALS) transitions and micro-drifts happen continuously
        // with small sample-to-sample deltas (< 0.045 per 80ms).
        // If delta is below 0.045, it is an automatic sensor adjustment -> keep silent, do not pop up HUD!
        guard delta >= manualAdjustmentThreshold else { return }

        // Significant jump (>= 4.5% in 80ms) indicates deliberate user interaction (e.g. Control Center slider)
        brightnessChangeEvent = current
    }

    // MARK: - Media Illumination Key Monitor

    private func setupSystemIlluminationKeyMonitor() {
        let handleEvent: (NSEvent) -> Void = { [weak self] event in
            guard event.subtype.rawValue == 8 else { return } // 8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS
            let data1 = event.data1
            let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = (data1 & 0x0000FFFF)
            let keyState = (keyFlags & 0xFF00) >> 8
            let isKeyDown = keyState == 0x0A

            guard isKeyDown else { return }

            let isFine = event.modifierFlags.contains(.option) && event.modifierFlags.contains(.shift)

            // 21 = Illumination Up, 22 = Illumination Down
            if keyCode == 21 {
                DispatchQueue.main.async {
                    self?.stepUp(fine: isFine)
                }
            } else if keyCode == 22 {
                DispatchQueue.main.async {
                    self?.stepDown(fine: isFine)
                }
            }
        }

        // Global monitor for when other apps have focus
        systemKeyMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            handleEvent(event)
        }

        // Local monitor for when DynamicNotch itself is key
        systemKeyMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            handleEvent(event)
            return event
        }
    }
}
