// LocalTimerViewModel.swift
// DynamicNotch / Features / Timer / ViewModels
//
// Drift-free, high-precision countdown engine for in-app timers.
// Uses target completion timestamp (endDate) and Combine 100ms ticker
// to guarantee zero lag, zero drift, and immediate pause/resume responsiveness.

import Foundation
import AppKit
import Combine

enum LocalTimerState: Equatable {
    case stopped
    case running
    case paused
}

final class LocalTimerViewModel: ObservableObject {
    @Published var state: LocalTimerState = .stopped
    @Published var remainingTime: TimeInterval = 0

    var totalTime: TimeInterval = 0
    var endDate: Date?
    var pausedRemaining: TimeInterval?
    var onTimerFinished: (() -> Void)?
    var onTick: ((TimeInterval) -> Void)?

    private var timer: AnyCancellable?

    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        totalTime = duration
        remainingTime = duration
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(duration)
        resume()
    }

    func start(hours: Int, minutes: Int, seconds: Int) {
        let total = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        start(duration: total)
    }

    func restart() {
        guard totalTime > 0 else { return }
        remainingTime = totalTime
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(totalTime)
        resume()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        timer?.cancel()
        timer = nil

        if let endDate = endDate {
            pausedRemaining = max(0, endDate.timeIntervalSince(Date()))
        }
        remainingTime = pausedRemaining ?? 0
        onTick?(remainingTime)
    }

    func resume() {
        state = .running
        if let pausedRemaining = pausedRemaining {
            endDate = Date().addingTimeInterval(pausedRemaining)
        } else {
            endDate = Date().addingTimeInterval(remainingTime)
        }
        pausedRemaining = nil

        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self else { return }
                let rem = self.remainingTime(at: now)
                self.remainingTime = rem
                self.onTick?(rem)
                if rem <= 0.05 {
                    self.timerFinished()
                }
            }
    }

    private func timerFinished() {
        stop()
        onTimerFinished?()
    }

    func stop() {
        state = .stopped
        timer?.cancel()
        timer = nil
        remainingTime = 0
        endDate = nil
        pausedRemaining = nil
    }

    func remainingTime(at date: Date) -> TimeInterval {
        switch state {
        case .stopped:
            return 0
        case .paused:
            return pausedRemaining ?? 0
        case .running:
            guard let endDate = endDate else { return 0 }
            return max(0, endDate.timeIntervalSince(date))
        }
    }

    var formattedRemainingTime: String {
        let displaySeconds = max(0, Int(ceil(remainingTime)))
        let hours = displaySeconds / 3600
        let minutes = (displaySeconds % 3600) / 60
        let seconds = displaySeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
