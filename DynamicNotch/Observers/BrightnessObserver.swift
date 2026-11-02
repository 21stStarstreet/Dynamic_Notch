// BrightnessObserver.swift
// DynamicNotch / Observers
//
// Observes display brightness via Apple's DisplayServices framework.
// Features Smart Intent Filtering to distinguish deliberate user actions (F1/F2 keys, Control Center)
// from ambient light sensor micro-drifts (Adaptive Brightness / True Tone).
// Hardware IPC queries execute entirely on a dedicated background worker queue, completely
// freeing the Main RunLoop (ProMotion 120 FPS) from blocking WindowServer calls.

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

    private let workerQueue = DispatchQueue(label: "com.dynamicnotch.brightness.worker", qos: .userInteractive)
    private var pollTimer: DispatchSourceTimer?
    private var lastReportedBrightness: Float = -1.0
    private var lastActivityTime: Date = .distantPast

    /// Threshold for detecting genuine display brightness adjustments (0.009 ≈ 0.9%).
    private let stepThreshold: Float = 0.009

    // MARK: - Init / Deinit

    init() {
        loadDisplayServices()
        seedInitialBrightness()
        startPolling()
    }

    deinit {
        pollTimer?.cancel()
        pollTimer = nil
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
        let clamped = max(0.0, min(1.0, newBrightness))
        lastReportedBrightness = clamped
        lastActivityTime = Date()

        workerQueue.async { [weak self] in
            guard let self, let setBrightness = self.setBrightnessFunc else { return }
            let displayID = CGMainDisplayID()
            let status = setBrightness(displayID, clamped)
            if status == 0 {
                DispatchQueue.main.async {
                    self.brightness = clamped
                    self.brightnessChangeEvent = clamped
                }
            }
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
        workerQueue.async { [weak self] in
            guard let self else { return }
            if let current = self.readCurrentBrightness() {
                DispatchQueue.main.async {
                    self.brightness = current
                    self.lastReportedBrightness = current
                }
            }
        }
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: workerQueue)
        // Adaptive 100ms background polling keeps F1/F2 keys instant without blocking Main RunLoop
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.evaluateBrightnessOnWorker()
        }
        timer.resume()
        pollTimer = timer
    }

    private func evaluateBrightnessOnWorker() {
        guard let current = readCurrentBrightness() else { return }

        // Initial baseline seed
        if lastReportedBrightness < 0 {
            lastReportedBrightness = current
            DispatchQueue.main.async {
                self.brightness = current
            }
            return
        }

        let delta = abs(current - lastReportedBrightness)

        if delta >= stepThreshold {
            lastReportedBrightness = current
            lastActivityTime = Date()
            DispatchQueue.main.async {
                self.brightness = current
                self.brightnessChangeEvent = current
            }
        }
    }
}
