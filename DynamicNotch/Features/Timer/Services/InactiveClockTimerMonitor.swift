// InactiveClockTimerMonitor.swift
// DynamicNotch / Features / Timer / Services

import Foundation

final class InactiveClockTimerMonitor: ClockTimerMonitoring {
    var onSnapshotChange: ((ClockTimerSnapshot?) -> Void)?

    func startMonitoring() {
        onSnapshotChange?(nil)
    }

    func stopMonitoring() {}
}
