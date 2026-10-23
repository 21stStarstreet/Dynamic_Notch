// BatteryObserver.swift
// DynamicNotch / Observers
//
// Monitors power source state via IOKit.ps run-loop notifications.
//
// Event deduplication & Startup Seeding
// ─────────────────────────────────────
// • On init, `update(isInitialSeed: true)` reads the current power state and
//   records `lastFiredEvent` without publishing a notification banner (so the
//   app doesn't pop up "Batarya dolu" every time it launches at 100%).
// • Subsequent IOKit run-loop callbacks pass `isInitialSeed: false` and publish
//   `event` only when a semantic transition (.charging, .low, .full) occurs.

import Foundation
import IOKit.ps

enum BatteryEvent: Equatable {
    case charging
    case low        // ≤ 20 % on battery
    case full       // 100 %
}

final class BatteryObserver: ObservableObject {

    @Published private(set) var event:      BatteryEvent? = nil
    @Published private(set) var percentage: Int           = 100
    @Published private(set) var isCharging: Bool          = false

    private var lastFiredEvent: BatteryEvent?
    private var lastObservedOnAC: Bool?
    private var runLoopSource: CFRunLoopSource?

    /// Records the exact timestamp of an AC power connect/disconnect event.
    /// Used by other observers (e.g. BrightnessObserver) to suppress automatic
    /// macOS power profile brightness changes from overriding the Battery alert.
    private(set) var lastPowerTransitionTime: Date = .distantPast

    var isWithinPowerTransitionCooldown: Bool {
        Date().timeIntervalSince(lastPowerTransitionTime) < 2.0
    }

    init() {
        startMonitoring()
    }

    deinit {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func startMonitoring() {
        let opaque = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        runLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let obs = Unmanaged<BatteryObserver>.fromOpaque(ctx).takeUnretainedValue()
            obs.update(isInitialSeed: false)
        }, opaque)?.takeRetainedValue()

        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        update(isInitialSeed: true)
    }

    private func update(isInitialSeed: Bool) {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        // Find the primary internal battery, or fallback to the first power source with capacity.
        // Prevents connected Bluetooth accessories (e.g. Magic Mouse, Keyboard) from overwriting
        // the Mac's internal battery state in the loop!
        var primaryDesc: [String: Any]? = nil

        for source in list {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let type = desc[kIOPSTypeKey] as? String
                if type == kIOPSInternalBatteryType {
                    primaryDesc = desc
                    break
                } else if primaryDesc == nil {
                    primaryDesc = desc
                }
            }
        }

        guard let desc = primaryDesc else { return }

        let capacity = desc[kIOPSCurrentCapacityKey] as? Int    ?? 100
        let onAC     = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.percentage = capacity
            self.isCharging = onAC

            if !isInitialSeed, let prevOnAC = self.lastObservedOnAC, prevOnAC != onAC {
                self.lastPowerTransitionTime = Date()
            }
            self.lastObservedOnAC = onAC

            let currentSemanticState: BatteryEvent? = {
                if onAC {
                    if capacity >= 100 {
                        return .full
                    } else {
                        return .charging
                    }
                } else {
                    if capacity <= 20 {
                        return .low
                    }
                    return nil
                }
            }()

            if isInitialSeed {
                self.lastFiredEvent = currentSemanticState
                return
            }

            if let newEvent = currentSemanticState, newEvent != self.lastFiredEvent {
                self.lastFiredEvent = newEvent
                self.event = newEvent
            } else if currentSemanticState == nil {
                self.lastFiredEvent = nil
            }
        }
    }

    // MARK: - Debug / Simulation Trigger

    func debugTrigger(_ simulatedEvent: BatteryEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch simulatedEvent {
            case .charging:
                if self.percentage >= 100 || self.percentage <= 20 {
                    self.percentage = 67
                }
                self.isCharging = true
            case .low:
                if self.percentage > 20 {
                    self.percentage = 14
                }
                self.isCharging = false
            case .full:
                self.percentage = 100
                self.isCharging = true
            }
            self.lastFiredEvent = simulatedEvent
            self.event = simulatedEvent
        }
    }
}
