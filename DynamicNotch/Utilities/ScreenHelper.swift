// ScreenHelper.swift
// DynamicNotch / Utilities
//
// Convenience queries for multi-display setups, preferring the built-in
// MacBook display when a notch is present.

import AppKit

enum ScreenHelper {

    /// Returns the preferred screen for hosting the DynamicNotch window:
    /// prefers the screen with a physical notch if connected, otherwise `NSScreen.main`.
    static var targetScreen: NSScreen {
        if let notchedScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchedScreen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Standard menu bar height on the target screen.
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
}
