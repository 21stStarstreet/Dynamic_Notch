// ClockTimerController.swift
// DynamicNotch / Features / Timer / Services
//
// Controls native macOS Clock.app timer via Accessibility (AXUIElement) APIs
// by pressing the stable identifier-based buttons ("PauseResumeButton" and "CancelButton").
// Non-disruptive: surfaces Clock.app via 'clock-timer-running:' only if needed,
// executes action, and immediately restores user's previous frontmost application.

import Foundation
import AppKit
#if canImport(ApplicationServices)
import ApplicationServices
#endif
import OSLog

@MainActor
final class ClockTimerController: ClockTimerControlling {

    private enum Control {
        case pauseResume
        case stop

        var buttonIdentifier: String {
            switch self {
            case .pauseResume:
                return "PauseResumeButton"
            case .stop:
                return "CancelButton"
            }
        }

        var debugName: String {
            switch self {
            case .pauseResume:
                return "pause/resume"
            case .stop:
                return "stop"
            }
        }
    }

    private let logger = Logger(subsystem: "com.dynamicnotch.app", category: "ClockTimerController")
    private let workspace: NSWorkspace
    private let buttonSearchAttempts: Int
    private let buttonSearchIntervalNanoseconds: UInt64
    private let clockBundleIdentifier = "com.apple.clock"
    private let runningTimerURL = URL(string: "clock-timer-running:")!

    init(
        workspace: NSWorkspace = .shared,
        buttonSearchAttempts: Int = 20,
        buttonSearchIntervalNanoseconds: UInt64 = 100_000_000
    ) {
        self.workspace = workspace
        self.buttonSearchAttempts = max(buttonSearchAttempts, 1)
        self.buttonSearchIntervalNanoseconds = buttonSearchIntervalNanoseconds
    }

    func togglePauseResume() async -> Bool {
        await perform(.pauseResume)
    }

    func stopTimer() async -> Bool {
        await perform(.stop)
    }
}

private extension ClockTimerController {

    private static var hasPromptedForAccessibility = false

    private func perform(_ control: Control) async -> Bool {
        #if canImport(ApplicationServices)
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            logger.warning("Accessibility permission is reported as false for DynamicNotch.")
            if !Self.hasPromptedForAccessibility {
                Self.hasPromptedForAccessibility = true
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
            // Do NOT immediately return false! Attempt action anyway in case permission was just toggled
        }
        #endif

        let previousFrontmostApp = workspace.frontmostApplication
        let clockWasHidden = clockApplication?.isHidden ?? false

        // 1. Fast path: button already exists in open Clock window
        if let button = findButton(for: control) {
            return press(button, control: control)
        }

        // 2. Slow path: Clock window is closed/minimized -> surface the timer tab via URL scheme
        let didOpenRunningTimer = workspace.open(runningTimerURL)
        guard didOpenRunningTimer else {
            logger.error("Failed to surface the running Clock timer before attempting to \(control.debugName, privacy: .public).")
            return false
        }

        // Wait for window and button to materialize
        let button = await waitForButton(for: control)
        let didPerformAction = button.map { press($0, control: control) } ?? false

        if !didPerformAction {
            logger.error("Unable to find the Clock timer \(control.debugName, privacy: .public) control after surfacing Clock.")
        }

        // Instantly restore previous app so user experiences zero focus disruption
        restorePreviousFrontmostApp(
            previousFrontmostApp,
            clockWasHidden: clockWasHidden
        )

        return didPerformAction
    }

    var clockApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: clockBundleIdentifier).first
    }

    private func waitForButton(for control: Control) async -> AXUIElement? {
        for _ in 0..<buttonSearchAttempts {
            if let button = findButton(for: control) {
                return button
            }
            try? await Task.sleep(nanoseconds: buttonSearchIntervalNanoseconds)
        }
        return nil
    }

    private func findButton(for control: Control) -> AXUIElement? {
        guard let clockApplication else { return nil }

        let appElement = AXUIElementCreateApplication(clockApplication.processIdentifier)
        let focusedWindow: AXUIElement? = axAttribute(kAXFocusedWindowAttribute, from: appElement)
        let windows: [AXUIElement] = axAttribute(kAXWindowsAttribute, from: appElement) ?? []

        if let focusedWindow, let button = findButton(for: control, in: focusedWindow) {
            return button
        }

        for window in windows {
            if let button = findButton(for: control, in: window) {
                return button
            }
        }

        if let button = findButton(for: control, in: appElement) {
            return button
        }

        return nil
    }

    private func findButton(for control: Control, in element: AXUIElement) -> AXUIElement? {
        if isTargetButton(element, for: control) {
            return element
        }

        let children: [AXUIElement] = axAttribute(kAXChildrenAttribute, from: element) ?? []
        for child in children {
            if let button = findButton(for: control, in: child) {
                return button
            }
        }

        return nil
    }

    private func isTargetButton(_ element: AXUIElement, for control: Control) -> Bool {
        let role: String = axAttribute(kAXRoleAttribute, from: element) ?? ""
        guard role == kAXButtonRole as String else { return false }

        let elementIdentifier: String = axAttribute(kAXIdentifierAttribute, from: element) ?? ""
        let title: String = axAttribute(kAXTitleAttribute, from: element) ?? ""
        let description: String = axAttribute(kAXDescriptionAttribute, from: element) ?? ""
        let help: String = axAttribute(kAXHelpAttribute, from: element) ?? ""
        let value: String = axAttribute(kAXValueAttribute, from: element) ?? ""

        switch control {
        case .pauseResume:
            if elementIdentifier == "PauseResumeButton" ||
               elementIdentifier.localizedCaseInsensitiveContains("PauseResume") {
                return true
            }
            let candidates = ["pause", "resume", "duraklat", "sürdür", "devam"]
            return candidates.contains {
                title.localizedCaseInsensitiveContains($0) ||
                description.localizedCaseInsensitiveContains($0) ||
                help.localizedCaseInsensitiveContains($0) ||
                value.localizedCaseInsensitiveContains($0)
            }

        case .stop:
            if elementIdentifier == "CancelButton" ||
               elementIdentifier.localizedCaseInsensitiveContains("Cancel") {
                return true
            }
            let candidates = ["cancel", "stop", "vazgeç", "iptal", "sıfırla"]
            return candidates.contains {
                title.localizedCaseInsensitiveContains($0) ||
                description.localizedCaseInsensitiveContains($0) ||
                help.localizedCaseInsensitiveContains($0) ||
                value.localizedCaseInsensitiveContains($0)
            }
        }
    }

    private func press(_ button: AXUIElement, control: Control) -> Bool {
        let didPress = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        if !didPress {
            logger.error("Clock timer \(control.debugName, privacy: .public) action failed.")
        }
        return didPress
    }

    func restorePreviousFrontmostApp(
        _ previousFrontmostApp: NSRunningApplication?,
        clockWasHidden: Bool
    ) {
        if clockWasHidden {
            clockApplication?.hide()
        }

        guard let previousFrontmostApp,
              previousFrontmostApp.bundleIdentifier != clockBundleIdentifier else {
            return
        }

        previousFrontmostApp.activate()
    }

    func axAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }
}
