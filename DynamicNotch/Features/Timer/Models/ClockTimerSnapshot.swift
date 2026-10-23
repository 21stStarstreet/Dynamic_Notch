// ClockTimerSnapshot.swift
// DynamicNotch / Features / Timer / Models
//
// Immutable model representing a point-in-time snapshot of the macOS native Clock timer.

import Foundation

struct ClockTimerSnapshot: Equatable {
    let identifier: String
    let title: String
    let duration: TimeInterval
    let endDate: Date
    let isPaused: Bool
    let pausedRemaining: TimeInterval?
    let fingerprint: String

    func remainingTime(at date: Date = Date()) -> TimeInterval {
        if isPaused, let pausedRemaining {
            return max(0, pausedRemaining)
        }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = Date()) -> Double {
        let resolvedDuration = max(duration, 1)
        return min(max(1.0 - (remainingTime(at: date) / resolvedDuration), 0.0), 1.0)
    }
}
