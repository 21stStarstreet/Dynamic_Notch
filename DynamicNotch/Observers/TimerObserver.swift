// TimerObserver.swift
// DynamicNotch / Observers
//
// Apple-grade Timer Coordinator & Facade for Dynamic Notch.
// Orchestrates:
// 1. System Clock Mirroring: ClockTimerMonitor (Unified Logging + Plist + AX fallback)
// 2. System Clock Control: ClockTimerController (AXUIElement programatic clicker)
// 3. In-App Countdown Engine: LocalTimerViewModel (drift-free 100ms ticker)
// 4. Alarm Sound Manager: TimerSoundPlayer (looping AVAudioPlayer / NSSound)
//
// Maintains 100% backward and forward compatibility with NotchViewModel and Live Activity views.

import Foundation
import Combine
import AppKit

@MainActor
final class TimerObserver: ObservableObject {

    enum ActiveSource: Equatable {
        case none
        case system
        case local
    }

    // MARK: - Published State

    @Published private(set) var activeTimer: TimerItem? = nil

    // MARK: - Subsystems

    private var clockMonitor: ClockTimerMonitoring
    private var clockController: ClockTimerControlling
    private let localTimerVM: LocalTimerViewModel
    private let soundPlayer: TimerSoundPlaying

    // MARK: - State Tracking

    private(set) var activeSource: ActiveSource = .none
    private var isManuallyCancelled: Bool = false
    private var cancelledTimerIDString: String? = nil
    private var cancelledTimerDuration: TimeInterval? = nil
    private var dismissedTimerIDs: Set<String> = []

    private var uiTicker: AnyCancellable?
    private var completionWorkItem: DispatchWorkItem?

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    // MARK: - Initialization / Deinitialization

    convenience init() {
        self.init(
            clockMonitor: ClockTimerMonitor(),
            clockController: ClockTimerController(),
            localTimerVM: LocalTimerViewModel(),
            soundPlayer: TimerSoundPlayer.shared
        )
    }

    init(
        clockMonitor: ClockTimerMonitoring,
        clockController: ClockTimerControlling,
        localTimerVM: LocalTimerViewModel,
        soundPlayer: TimerSoundPlaying
    ) {
        self.clockMonitor = clockMonitor
        self.clockController = clockController
        self.localTimerVM = localTimerVM
        self.soundPlayer = soundPlayer

        setupSubsystems()
    }

    deinit {
        uiTicker?.cancel()
        completionWorkItem?.cancel()
        clockMonitor.stopMonitoring()
        localTimerVM.stop()
    }

    // MARK: - Subsystems Setup

    private func setupSubsystems() {
        // 1. Clock.app / MobileTimer system monitor callback
        clockMonitor.onSnapshotChange = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.handleClockSnapshot(snapshot)
            }
        }
        clockMonitor.startMonitoring()

        // 2. Local Timer ViewModel callbacks
        localTimerVM.onTick = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLocalTimerTick()
            }
        }

        localTimerVM.onTimerFinished = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleLocalTimerFinished()
            }
        }
    }

    // MARK: - System Snapshot Handler

    private func handleClockSnapshot(_ snapshot: ClockTimerSnapshot?) {
        // If a local timer is currently running, do not let background snapshots clobber it
        if activeSource == .local {
            return
        }

        guard let snapshot = snapshot else {
            if activeSource == .system {
                handleNoActiveSystemTimer()
            }
            return
        }

        // Check if user has explicitly cancelled this specific timer from DynamicNotch:
        if isManuallyCancelled {
            let matchesID = (cancelledTimerIDString != nil && snapshot.identifier == cancelledTimerIDString)
                || dismissedTimerIDs.contains(snapshot.identifier)

            if matchesID {
                // The native timer was cancelled by the user from DynamicNotch. Suppress resurrection.
                return
            } else {
                // A new, distinct timer was started in macOS Clock app!
                isManuallyCancelled = false
                cancelledTimerIDString = nil
                cancelledTimerDuration = nil
            }
        }

        let isNewSession = activeSource != .system || activeTimer == nil
        activeSource = .system
        let stableID = (!isNewSession && activeTimer != nil)
            ? activeTimer!.id
            : (UUID(uuidString: snapshot.identifier) ?? UUID())

        var resolvedTitle = snapshot.title
        if resolvedTitle.isEmpty || resolvedTitle == "CURRENT_TIMER" || resolvedTitle == "Timer" {
            resolvedTitle = isTurkish ? "Zamanlayıcı" : "Timer"
        }

        if let existing = activeTimer, !isNewSession {
            // Existing tracked system timer
            var updated = existing
            updated.title = resolvedTitle
            updated.totalDuration = snapshot.duration
            updated.isPaused = snapshot.isPaused

            if snapshot.isPaused {
                updated.remainingWhenPaused = snapshot.pausedRemaining ?? snapshot.remainingTime()
                stopUITicker()
            } else {
                updated.remainingWhenPaused = nil
                updated.endDate = snapshot.endDate
                if uiTicker == nil {
                    startUITicker()
                }
            }

            self.activeTimer = updated

            if updated.isExpired {
                handleSystemTimerExpiration()
            }
        } else {
            // New system timer detected
            let item = TimerItem(
                id: stableID,
                title: resolvedTitle,
                totalDuration: snapshot.duration,
                endDate: snapshot.endDate,
                isPaused: snapshot.isPaused,
                remainingWhenPaused: snapshot.pausedRemaining
            )

            self.activeTimer = item

            if snapshot.isPaused {
                stopUITicker()
            } else {
                startUITicker()
            }

            if item.isExpired {
                handleSystemTimerExpiration()
            }
        }
    }

    private func handleNoActiveSystemTimer() {
        guard activeSource == .system else { return }
        stopUITicker()
        completionWorkItem?.cancel()
        completionWorkItem = nil
        activeSource = .none
        activeTimer = nil
    }

    // MARK: - Local Timer Handlers

    private func handleLocalTimerTick() {
        guard activeSource == .local, let current = activeTimer else { return }
        var updated = current
        updated.isPaused = localTimerVM.state == .paused
        if updated.isPaused {
            updated.remainingWhenPaused = localTimerVM.remainingTime
        } else {
            updated.remainingWhenPaused = nil
            if let end = localTimerVM.endDate {
                updated.endDate = end
            }
        }
        self.activeTimer = updated
    }

    private func handleLocalTimerFinished() {
        guard activeSource == .local else { return }
        stopUITicker()

        // Update activeTimer to expired 00:00
        if var current = activeTimer {
            current.endDate = Date()
            current.isPaused = false
            current.remainingWhenPaused = 0
            self.activeTimer = current
        }

        // Play alarm acoustic loop
        soundPlayer.play(sound: .radar, isSoundEnabled: true, loop: true)

        // Keep expired card visible for 5 seconds before dismiss
        completionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.soundPlayer.stop()
                self?.activeTimer = nil
                self?.activeSource = .none
            }
        }
        completionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    private func handleSystemTimerExpiration() {
        stopUITicker()

        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }

        completionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeSource == .system else { return }
                self.activeTimer = nil
                self.activeSource = .none
            }
        }
        completionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    // MARK: - Public Controls

    /// Starts a new local countdown timer with the specified duration in seconds.
    func startTimer(duration: TimeInterval, title: String = "Timer") {
        guard duration > 0 else { return }

        // Stop any running alarm sound
        soundPlayer.stop()
        completionWorkItem?.cancel()
        completionWorkItem = nil

        // Clear suppression state
        isManuallyCancelled = false
        cancelledTimerIDString = nil
        cancelledTimerDuration = nil
        dismissedTimerIDs.removeAll()

        activeSource = .local

        let item = TimerItem(
            id: UUID(),
            title: title,
            totalDuration: duration,
            endDate: Date().addingTimeInterval(duration),
            isPaused: false,
            remainingWhenPaused: nil
        )

        self.activeTimer = item
        localTimerVM.start(duration: duration)
        startUITicker()
    }

    /// Toggles play / pause for the currently active timer (system or local).
    func togglePlayPause() {
        guard let current = activeTimer else { return }
        if current.isPaused {
            resume()
        } else {
            pause()
        }
    }

    /// Pauses the active timer.
    func pause() {
        guard var current = activeTimer, !current.isPaused else { return }

        // Optimistic UI update for immediate response
        current.isPaused = true
        current.remainingWhenPaused = current.remaining
        activeTimer = current
        stopUITicker()

        switch activeSource {
        case .system:
            Task { [weak self] in
                guard let self = self else { return }
                _ = await self.clockController.togglePauseResume()
            }
        case .local:
            localTimerVM.pause()
        case .none:
            break
        }
    }

    /// Resumes the active timer.
    func resume() {
        guard var current = activeTimer, current.isPaused else { return }

        // Optimistic UI update for immediate response
        let rem = current.remainingWhenPaused ?? current.remaining
        current.isPaused = false
        current.remainingWhenPaused = nil
        current.endDate = Date().addingTimeInterval(rem)
        activeTimer = current
        startUITicker()

        switch activeSource {
        case .system:
            Task { [weak self] in
                guard let self = self else { return }
                _ = await self.clockController.togglePauseResume()
            }
        case .local:
            localTimerVM.resume()
        case .none:
            break
        }
    }

    /// Cancels and clears the active timer immediately.
    func cancel() {
        soundPlayer.stop()
        completionWorkItem?.cancel()
        completionWorkItem = nil
        stopUITicker()

        switch activeSource {
        case .system:
            isManuallyCancelled = true
            if let id = activeTimer?.id.uuidString {
                cancelledTimerIDString = id
                dismissedTimerIDs.insert(id)
            }
            if let dur = activeTimer?.totalDuration {
                cancelledTimerDuration = dur
            }

            Task { [weak self] in
                guard let self = self else { return }
                _ = await self.clockController.stopTimer()
            }

        case .local:
            localTimerVM.stop()

        case .none:
            break
        }

        activeTimer = nil
        activeSource = .none
    }

    /// Adds incremental seconds (e.g. +60s) to the active countdown.
    func addTime(seconds: TimeInterval) {
        guard var current = activeTimer, seconds > 0 else { return }

        if current.isPaused {
            let existing = current.remainingWhenPaused ?? current.remaining
            current.remainingWhenPaused = existing + seconds
            current.totalDuration += seconds
        } else {
            current.endDate = current.endDate.addingTimeInterval(seconds)
            current.totalDuration += seconds
        }
        activeTimer = current

        if activeSource == .local {
            localTimerVM.totalTime += seconds
            if localTimerVM.state == .paused {
                localTimerVM.pausedRemaining = (localTimerVM.pausedRemaining ?? 0) + seconds
            } else if let end = localTimerVM.endDate {
                localTimerVM.endDate = end.addingTimeInterval(seconds)
            }
        }
    }

    // MARK: - UI Ticker Loop

    private func startUITicker() {
        stopUITicker()

        // 0.25s interval ensures fluid countdown without battery/CPU drain
        uiTicker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleUITick()
            }
    }

    private func stopUITicker() {
        uiTicker?.cancel()
        uiTicker = nil
    }

    private func handleUITick() {
        guard let current = activeTimer else {
            stopUITicker()
            return
        }

        if current.isExpired {
            if activeSource == .system {
                handleSystemTimerExpiration()
            } else if activeSource == .local {
                handleLocalTimerFinished()
            }
            return
        }

        // Trigger SwiftUI reactive redraw
        activeTimer = current
    }
}
