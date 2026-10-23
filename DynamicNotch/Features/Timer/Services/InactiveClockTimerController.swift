// InactiveClockTimerController.swift
// DynamicNotch / Features / Timer / Services

import Foundation

@MainActor
final class InactiveClockTimerController: ClockTimerControlling {
    func togglePauseResume() async -> Bool { false }
    func stopTimer() async -> Bool { false }
}
