// LockScreenObserver.swift
// DynamicNotch / Observers
//
// Monitors macOS session lock and unlock events via distributed and workspace notifications.
// Ensures DynamicNotch gracefully collapses to compact mode and remains visible
// on top of the lock screen with hover expansion locked for security.

import AppKit
import Combine
import CoreGraphics

final class LockScreenObserver: ObservableObject {

    @Published private(set) var isLocked: Bool = false
    private var pollTimer: AnyCancellable?

    init() {
        setupObservers()
        checkInitialLockState()
        setupPollingTimer()
    }

    private func setupObservers() {
        // 1. Distributed notifications for screen lock/unlock
        let distCenter = DistributedNotificationCenter.default()

        distCenter.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        distCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        distCenter.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        distCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 2. NSWorkspace session notifications (Fast user switching / lock)
        let wsCenter = NSWorkspace.shared.notificationCenter

        wsCenter.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        wsCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        wsCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        wsCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screenLocked() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isLocked else { return }
            self.isLocked = true
        }
    }

    @objc private func screenUnlocked() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isLocked else { return }
            self.isLocked = false
        }
    }

    @objc private func screensDidSleep() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLocked = true
        }
    }

    @objc private func screensDidWake() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.checkInitialLockState()
        }
    }

    private func setupPollingTimer() {
        pollTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollLockState()
            }
    }

    private func pollLockState() {
        if let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            let locked: Bool
            if let isLockedNum = sessionDict["CGSSessionScreenIsLocked"] as? NSNumber {
                locked = isLockedNum.boolValue
            } else if let isLockedBool = sessionDict["CGSSessionScreenIsLocked"] as? Bool {
                locked = isLockedBool
            } else {
                locked = false
            }

            if self.isLocked != locked {
                self.isLocked = locked
            }
        }
    }

    private func checkInitialLockState() {
        pollLockState()
    }

    deinit {
        pollTimer?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
