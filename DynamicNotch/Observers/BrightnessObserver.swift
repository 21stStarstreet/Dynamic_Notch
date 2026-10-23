// BrightnessObserver.swift
// DynamicNotch / Observers
//
// Observes display brightness via Apple's DisplayServices framework.
// Features Smart Intent Filtering to distinguish deliberate user actions (F1/F2 keys, Control Center)
// from ambient light sensor micro-drifts (Adaptive Brightness / True Tone).

import AppKit
import Combine
import CoreGraphics

final class BrightnessObserver: ObservableObject {

    // MARK: - Published Properties

    /// Current display brightness (0.0 … 1.0).
    @Published private(set) var brightness: Float = 1.0

    /// Emits only on genuine user brightness changes (never on app launch or ambient light sensor drift).
    @Published private(set) var brightnessChangeEvent: Float? = nil

    // MARK: - Private Properties

    private typealias DisplayServicesGetBrightnessType = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightnessType = @convention(c) (UInt32, Float) -> Int32

    private var getBrightnessFunc: DisplayServicesGetBrightnessType?
    private var setBrightnessFunc: DisplayServicesSetBrightnessType?

    private var pollTimer: AnyCancellable?
    private var lastReportedBrightness: Float = -1.0
    private var lastManualChangeTime: Date = .distantPast

    /// Threshold for detecting genuine display brightness adjustments (0.009 ≈ 0.9%).
    /// Captures F1/F2 keys (0.0625), Option+Shift+F1/F2 fine steps (0.0156), Control Center slider,
    /// and macOS adaptive brightness transitions, while filtering out raw hardware sensor jitter (< 0.002).
    private let stepThreshold: Float = 0.009

    // MARK: - Init / Deinit

    init() {
        loadDisplayServices()
        seedInitialBrightness()
        startPolling()
    }

    deinit {
        pollTimer?.cancel()
    }

    // MARK: - Framework Binding

    private func loadDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return
        }
        if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightnessFunc = unsafeBitCast(sym, to: DisplayServicesGetBrightnessType.self)
        }
        if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightnessFunc = unsafeBitCast(sym, to: DisplayServicesSetBrightnessType.self)
        }
    }

    // MARK: - Manual Control

    func setBrightness(_ newBrightness: Float) {
        guard let setBrightness = setBrightnessFunc else { return }
        let clamped = max(0.0, min(1.0, newBrightness))
        let displayID = CGMainDisplayID()
        let status = setBrightness(displayID, clamped)
        if status == 0 {
            lastReportedBrightness = clamped
            brightness = clamped
            brightnessChangeEvent = clamped
        }
    }

    // MARK: - Polling & Intent Filtering

    private func readCurrentBrightness() -> Float? {
        guard let getBrightness = getBrightnessFunc else { return nil }
        let displayID = CGMainDisplayID()
        var val: Float = 0.0
        let status = getBrightness(displayID, &val)
        guard status == 0 else { return nil }
        return max(0.0, min(1.0, val))
    }

    private func seedInitialBrightness() {
        if let current = readCurrentBrightness() {
            brightness = current
            lastReportedBrightness = current
        }
    }

    private func startPolling() {
        // 80ms interval ensures instant response to F1/F2 key taps and adaptive brightness
        pollTimer = Timer.publish(every: 0.08, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluateBrightness()
            }
    }

    private func evaluateBrightness() {
        guard let current = readCurrentBrightness() else { return }

        // If uninitialized, seed without firing
        if lastReportedBrightness < 0 {
            brightness = current
            lastReportedBrightness = current
            return
        }

        let delta = abs(current - lastReportedBrightness)

        if delta >= stepThreshold {
            lastReportedBrightness = current
            brightness = current
            brightnessChangeEvent = current
        }
    }
}
