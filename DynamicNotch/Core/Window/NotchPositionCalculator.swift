// NotchPositionCalculator.swift
// DynamicNotch / Core / Window
//
// Pure-value geometry engine for the 3 states of the notch NSWindow:
//   1. `hiddenFrame`:  Completely hidden behind the physical camera cutout (zero wings).
//   2. `compactFrame`: Closed at menu-bar height with 36pt left & right icon wings.
//   3. `expandedFrame`: Expanded downward and outward to show full interactive content.

import AppKit

struct NotchPositionCalculator {

    /// Width of each compact side wing (left and right of the physical notch).
    static let compactWingWidth: CGFloat = 42.0

    /// Outward concave ear radius in compact mode.
    static let compactTopEarRadius: CGFloat = 10.0

    /// Outward concave ear radius in expanded mode.
    static let expandedTopEarRadius: CGFloat = 14.0

    /// Subtle downward extension (in points) for the compact island.
    static let compactVerticalExtension: CGFloat = 1.0

    // MARK: - Presentation Modes & Floating Island Geometry

    enum PresentationMode: String, CaseIterable, Identifiable {
        case automatic = "automatic"
        case floatingCapsule = "floatingCapsule"
        case physicalNotch = "physicalNotch"

        var id: String { rawValue }
    }

    /// Returns true if the screen should render as an autonomous floating Dynamic Island capsule.
    static func isFloatingCapsule(for screen: NSScreen) -> Bool {
        let savedMode = UserDefaults.standard.string(forKey: "notchPresentationMode") ?? PresentationMode.automatic.rawValue
        switch savedMode {
        case PresentationMode.floatingCapsule.rawValue:
            return true
        case PresentationMode.physicalNotch.rawValue:
            return false
        default:
            return !hasPhysicalNotch(screen: screen)
        }
    }

    @MainActor
    static func isFloatingCapsule() -> Bool {
        isFloatingCapsule(for: ScreenHelper.targetScreen)
    }

    /// Authentic compact Dynamic Island dimensions for floating capsule mode.
    static let compactFloatingIslandSize = CGSize(width: 186.0, height: 34.0)

    /// Vertical clearance from the top of the display when floating.
    /// In normal desktop space, floats 10pt below the macOS menu bar.
    /// In full-screen space or when menu bar is hidden, floats 10pt below the screen top bezel.
    static func floatingTopOffset(for screen: NSScreen) -> CGFloat {
        let positionSetting = UserDefaults.standard.string(forKey: "floatingIslandPosition") ?? "belowMenuBar"
        if positionSetting == "screenTop" {
            return 10.0
        }

        // Measure actual menu bar height on target screen
        let visibleTop = screen.visibleFrame.maxY
        let fullTop = screen.frame.maxY
        let menuBarDiff = fullTop - visibleTop
        if menuBarDiff > 0 {
            // Desktop space with menu bar visible: float 10pt below the menu bar
            return menuBarDiff + 10.0
        } else {
            // Full screen mode or hidden menu bar: float 10pt below top edge
            return 10.0
        }
    }

    @MainActor
    static func floatingTopOffset() -> CGFloat {
        floatingTopOffset(for: ScreenHelper.targetScreen)
    }

    // MARK: - Notch Base Width (Hardware Cutout)

    static func notchBaseWidth(for screen: NSScreen) -> CGFloat {
        if isFloatingCapsule(for: screen) {
            return compactFloatingIslandSize.width
        }

        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           leftArea.width > 0, rightArea.width > 0 {
            let gap = rightArea.minX - leftArea.maxX
            if gap >= 140 && gap <= 260 {
                return ceil(gap)
            }
        }

        let topInset = screen.safeAreaInsets.top
        switch topInset {
        case 40...:   return 212.0   // MacBook Pro 14" / 16"
        case 20..<40: return 184.0   // MacBook Air 13.6" / 15.3"
        default:      return 160.0   // Fallback
        }
    }

    @MainActor
    static func notchBaseWidth() -> CGFloat {
        notchBaseWidth(for: ScreenHelper.targetScreen)
    }

    // MARK: - 3-State Frame Calculations

    /// State 1 — Completely Idle (No active action):
    /// Hugs only the physical camera cutout with zero side wings, or invisible in floating mode.
    static func hiddenFrame(for screen: NSScreen) -> NSRect {
        if isFloatingCapsule(for: screen) {
            let w = compactFloatingIslandSize.width
            let h = compactFloatingIslandSize.height
            let x = (screen.frame.width - w) / 2.0 + screen.frame.origin.x
            let y = screen.frame.maxY - floatingTopOffset(for: screen) - h
            return NSRect(x: round(x), y: round(y), width: ceil(w), height: ceil(h))
        }

        let baseWidth   = notchBaseWidth(for: screen)
        let notchHeight = effectiveNotchHeight(for: screen)

        let x = (screen.frame.width - baseWidth) / 2.0 + screen.frame.origin.x
        let y = screen.frame.maxY - notchHeight

        return NSRect(x: round(x), y: round(y), width: ceil(baseWidth), height: ceil(notchHeight))
    }

    /// State 2 — Compact Wing Mode (LiveActivity active, mouse not hovering):
    /// On physical notch: extends left and right with wings.
    /// On floating capsule: presents as a sleek 186×34pt monolithic Dynamic Island pill.
    static func compactFrame(for screen: NSScreen) -> NSRect {
        if isFloatingCapsule(for: screen) {
            let w = compactFloatingIslandSize.width
            let h = compactFloatingIslandSize.height
            let x = (screen.frame.width - w) / 2.0 + screen.frame.origin.x
            let y = screen.frame.maxY - floatingTopOffset(for: screen) - h
            return NSRect(x: round(x), y: round(y), width: ceil(w), height: ceil(h))
        }

        let baseWidth   = notchBaseWidth(for: screen)
        let totalWidth  = baseWidth + (compactWingWidth * 2.0) + (compactTopEarRadius * 2.0)
        let notchHeight = effectiveNotchHeight(for: screen) + compactVerticalExtension

        let x = (screen.frame.width - totalWidth) / 2.0 + screen.frame.origin.x
        let y = screen.frame.maxY - notchHeight

        return NSRect(x: round(x), y: round(y), width: ceil(totalWidth), height: ceil(notchHeight))
    }

    /// Legacy alias for compactFrame.
    static func idleFrame(for screen: NSScreen) -> NSRect {
        compactFrame(for: screen)
    }

    /// State 3 — Expanded Mode (Mouse hovering over active LiveActivity, or Alert active):
    static func expandedFrame(size: CGSize, screen: NSScreen) -> NSRect {
        let x = (screen.frame.width - size.width) / 2.0 + screen.frame.origin.x
        let topOffset = isFloatingCapsule(for: screen) ? floatingTopOffset(for: screen) : 0.0
        let y = screen.frame.maxY - topOffset - size.height

        return NSRect(x: round(x), y: round(y), width: ceil(size.width), height: ceil(size.height))
    }

    /// Fixed-canvas frame for the borderless NSWindow so AppKit never has to call
    /// `window.setFrame(...)` during spring animations (eliminating NSHostingView backing-store jitter).
    static func fixedCanvasFrame(for screen: NSScreen) -> NSRect {
        let canvasWidth  = ceil(min(max(screen.frame.width * 0.64, 620.0), 960.0))
        let canvasHeight: CGFloat = 380.0
        let x = (screen.frame.width - canvasWidth) / 2.0 + screen.frame.origin.x
        let y = screen.frame.maxY - canvasHeight

        return NSRect(x: round(x), y: round(y), width: canvasWidth, height: canvasHeight)
    }

    // MARK: - Convenience Queries

    static func effectiveNotchHeight(for screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> CGFloat {
        if isFloatingCapsule(for: screen) {
            return compactFloatingIslandSize.height
        }
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 34.0
    }

    static func hasPhysicalNotch(screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func hasNotch(screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> Bool {
        !isFloatingCapsule(for: screen)
    }

    static func notchHeight(screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> CGFloat {
        screen.safeAreaInsets.top
    }

    // MARK: - Satellite Orb Geometry (Dual Live Activity)

    /// Gap between the right edge of the main notch and the satellite orb.
    /// Tucked snugly alongside the notch ear flare for a seamless Apple Dynamic Island look.
    static let orbGap: CGFloat = -2.5

    /// Fixed canvas size for the Satellite Orb window to avoid backing-store jitter.
    static let orbCanvasSize = CGSize(width: 360.0, height: 260.0)

    /// Returns the screen frame for the Satellite Orb window canvas, anchored to the right of the main notch.
    static func orbCanvasFrame(for screen: NSScreen, notchWidth: CGFloat) -> NSRect {
        let notchX = (screen.frame.width - notchWidth) / 2.0 + screen.frame.origin.x
        let notchMaxX = notchX + notchWidth
        let x = notchMaxX + (isFloatingCapsule(for: screen) ? 8.0 : orbGap)
        let topOffset = isFloatingCapsule(for: screen) ? floatingTopOffset(for: screen) : 0.0
        let y = screen.frame.maxY - topOffset - orbCanvasSize.height

        let clampedX = min(x, screen.frame.maxX - orbCanvasSize.width - 6.0)
        return NSRect(x: round(clampedX), y: round(y), width: orbCanvasSize.width, height: orbCanvasSize.height)
    }

    /// Screen rect for mouse hit-testing of the active orb (compact or expanded).
    static func orbHitRect(for screen: NSScreen, notchWidth: CGFloat, activeSize: CGSize, isExpanded: Bool) -> NSRect {
        let isFloating = isFloatingCapsule(for: screen)
        let notchX = (screen.frame.width - notchWidth) / 2.0 + screen.frame.origin.x
        let notchMaxX = notchX + notchWidth
        let x = notchMaxX + (isFloating ? 8.0 : orbGap)

        let notchH = effectiveNotchHeight(for: screen)
        let topOffset: CGFloat
        if isFloating {
            topOffset = floatingTopOffset(for: screen) + (isExpanded ? 0.0 : max(0.0, (notchH - activeSize.height) / 2.0))
        } else {
            topOffset = isExpanded ? 0.0 : max(2.0, (notchH - activeSize.height) / 2.0)
        }
        let y = screen.frame.maxY - topOffset - activeSize.height

        let clampedX = min(x, screen.frame.maxX - activeSize.width - 6.0)
        return NSRect(x: round(clampedX), y: round(y), width: ceil(activeSize.width), height: ceil(activeSize.height))
    }
}
