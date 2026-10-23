// NotchDetector.swift
// DynamicNotch / Utilities
//
// Hardware inspection helper for determining whether a display features a
// physical camera housing notch and computing its exact menu-bar geometry.

import AppKit

enum NotchDetector {

    /// Returns true if the given screen has a physical top safe-area cutout (notch).
    static func hasPhysicalNotch(on screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Computes the exact horizontal gap between the left and right menu bar
    /// auxiliary areas when macOS reports them, falling back to `NotchPositionCalculator`.
    static func hardwareCutoutRect(on screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> NSRect {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else {
            return NotchPositionCalculator.idleFrame(for: screen)
        }

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           leftArea.width > 0, rightArea.width > 0 {
            let cutoutX = leftArea.maxX
            let cutoutWidth = rightArea.minX - leftArea.maxX
            if cutoutWidth > 100 && cutoutWidth < 350 {
                return NSRect(
                    x: cutoutX,
                    y: screen.frame.maxY - topInset,
                    width: cutoutWidth,
                    height: topInset
                )
            }
        }

        return NotchPositionCalculator.idleFrame(for: screen)
    }
}
