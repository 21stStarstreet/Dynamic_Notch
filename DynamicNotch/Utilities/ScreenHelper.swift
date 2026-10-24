// ScreenHelper.swift
// DynamicNotch / Utilities
//
// Dynamic multi-display management engine:
// Automatically tracks the active working screen (MacBook built-in vs external displays)
// and coordinates seamless, animated hand-off transitions.

import AppKit

@MainActor
final class ScreenHelper {

    /// Currently active screen hosting the DynamicNotch window.
    private(set) static var targetScreen: NSScreen = initialScreen()

    /// Standard menu bar height on the active target screen.
    static var menuBarHeight: CGFloat {
        let screen = targetScreen
        if screen.safeAreaInsets.top > 0 {
            return screen.safeAreaInsets.top
        }
        let visibleTop = screen.visibleFrame.maxY
        let fullTop = screen.frame.maxY
        let diff = fullTop - visibleTop
        return diff > 0 ? diff : 24.0
    }

    /// Determines the initial screen at launch (prefers screen with physical notch if present).
    private static func initialScreen() -> NSScreen {
        if let notchedScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchedScreen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// Returns the screen containing the given point (e.g. mouse cursor location in global screen coordinates).
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSPointInRect(point, $0.frame) }
    }

    /// Whether the given screen has a physical hardware camera notch.
    static func hasPhysicalNotch(screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Updates the active target screen and notifies observers if changed.
    @discardableResult
    static func updateTargetScreen(_ newScreen: NSScreen) -> Bool {
        guard newScreen != targetScreen else { return false }
        targetScreen = newScreen
        NotificationCenter.default.post(
            name: .notchTargetScreenDidChange,
            object: newScreen
        )
        return true
    }

    /// Re-evaluates target screen when screen topology or parameters change (e.g. external display disconnected).
    static func refreshTargetScreen() {
        if !NSScreen.screens.contains(targetScreen) {
            targetScreen = initialScreen()
            NotificationCenter.default.post(
                name: .notchTargetScreenDidChange,
                object: targetScreen
            )
        }
    }
}

extension Notification.Name {
    static let notchTargetScreenDidChange = Notification.Name("notchTargetScreenDidChange")
}
