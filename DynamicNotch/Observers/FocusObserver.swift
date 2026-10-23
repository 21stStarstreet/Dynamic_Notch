// FocusObserver.swift
// DynamicNotch / Observers
//
// Observes macOS Do Not Disturb / Focus Mode state transitions across macOS 14 Sonoma,
// macOS 15 Sequoia, and macOS 26 Tahoe.
//
// Detection Architecture
// ──────────────────────
// 1. DistributedNotificationCenter (`_NSDoNotDisturbEnabledNotification` and
//    `_NSDoNotDisturbDisabledNotification`):
//    Posted directly by macOS when Do Not Disturb / Focus mode is toggled ON or OFF.
// 2. Optional Assertions DB (`~/Library/DoNotDisturb/DB/Assertions.json`):
//    Used only when Full Disk Access permits reading the file; never falls back to a
//    synthetic `false` when unreadable, preventing false deactivation events.

import Foundation
import Combine
import notify

final class FocusObserver: ObservableObject {

    /// Current Focus / Do Not Disturb state (`true` = Focus active).
    @Published private(set) var isFocusActive: Bool = false

    /// Emits only when Focus / Do Not Disturb state changes after initial launch seed.
    @Published private(set) var focusChangeEvent: Bool? = nil

    private var lastKnownFocusState: Bool? = nil
    private var darwinTokens: [Int32] = []

    private let assertionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

    // MARK: - Init / Deinit

    init() {
        // Seed initial state only if Assertions.json is readable; otherwise keep `nil`
        // so the first explicit enable OR disable transition is always captured.
        if let initial = readFocusStateFromAssertionsDB() {
            lastKnownFocusState = initial
            isFocusActive = initial
            registerDarwinNotifications()
        }

        registerDistributedNotifications()
    }

    deinit {
        for token in darwinTokens {
            notify_cancel(token)
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - 1. Distributed Notification Center (Authoritative Enable / Disable Signals)

    private func registerDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(
            self,
            selector: #selector(handleDNDEnabled(_:)),
            name: NSNotification.Name("_NSDoNotDisturbEnabledNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        dnc.addObserver(
            self,
            selector: #selector(handleDNDDisabled(_:)),
            name: NSNotification.Name("_NSDoNotDisturbDisabledNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleDNDEnabled(_ notification: Notification) {
        publishExplicitState(true)
    }

    @objc private func handleDNDDisabled(_ notification: Notification) {
        publishExplicitState(false)
    }

    // MARK: - 2. Darwin Notifications (Active only when Assertions DB is accessible)

    private func registerDarwinNotifications() {
        let names = [
            "com.apple.donotdisturb.state.changed",
            "com.apple.focus.state.changed"
        ]

        for name in names {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] _ in
                guard let self, let state = self.readFocusStateFromAssertionsDB() else { return }
                self.publishExplicitState(state)
            }
            if status == NOTIFY_STATUS_OK {
                darwinTokens.append(token)
            }
        }
    }

    // MARK: - State Publishing

    private func publishExplicitState(_ newState: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.lastKnownFocusState != newState else { return }
            self.lastKnownFocusState = newState
            self.isFocusActive       = newState
            self.focusChangeEvent    = newState
        }
    }

    // MARK: - Optional Assertions DB Reader

    /// Returns `true` or `false` ONLY if `Assertions.json` is readable on disk;
    /// returns `nil` when inaccessible so we never emit a bogus `false` state.
    private func readFocusStateFromAssertionsDB() -> Bool? {
        guard let data = try? Data(contentsOf: assertionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first else {
            return nil
        }

        if let records = first["storeAssertionRecords"] as? [Any], !records.isEmpty {
            return true
        }
        return false
    }
}
