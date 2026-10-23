// NotchWindowController.swift
// DynamicNotch / Core / Window
//
// Owns and manages the single borderless NSWindow that overlays the notch area.
//
// 3-State Lifecycle
// ─────────────────
// 1. Completely Hidden (`hideToIdle()`):
//    • No LiveActivity and no Alert is active.
//    • `window.ignoresMouseEvents = true` and hover tracking is disabled so
//      nothing appears or reacts when the user moves the cursor near the notch.
// 2. Compact Wing Mode (`showCompact()`):
//    • A LiveActivity (Now Playing / Download) is active.
//    • Small icons appear on the left and right sides of the physical notch.
//    • Hover tracking is active: hovering expands the notch to show controls.
// 3. Expanded Mode (`expand(to:)`):
//    • Triggered by hovering over an active Compact LiveActivity or by an Alert.

import AppKit
import SwiftUI

final class NotchHostingView<Content: View>: NSHostingView<Content> {

    var onScrollWheel: ((NSEvent) -> Void)?
    var onSwipe: ((NSEvent) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        self.sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        onScrollWheel?(event)
    }

    override func swipe(with event: NSEvent) {
        super.swipe(with: event)
        onSwipe?(event)
    }
}

final class NotchPanel: NSPanel {
    var allowsKeyWindow: Bool = false

    override var canBecomeKey: Bool { allowsKeyWindow }
    override var canBecomeMain: Bool { allowsKeyWindow }
    override var acceptsFirstResponder: Bool { true }

    override var isMovable: Bool {
        get { false }
        set {}
    }

    override var isMovableByWindowBackground: Bool {
        get { false }
        set {}
    }
}


// MARK: - SkyLight Private Spaces & Window Server Bridge

final class SkyLightSpaceBridge {
    static let shared = SkyLightSpaceBridge()

    private typealias SLSMainConnectionIDType = @convention(c) () -> UInt32
    private typealias SLSSpaceCreateType = @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
    private typealias SLSSpaceSetAbsoluteLevelType = @convention(c) (UInt32, UInt64, Int32) -> Void
    private typealias SLSAddWindowsToSpacesType = @convention(c) (UInt32, CFArray, CFArray) -> Void
    private typealias SLSShowSpacesType = @convention(c) (UInt32, CFArray) -> Void
    private typealias CGSSetWindowTagsType = @convention(c) (UInt32, UInt32, UnsafePointer<UInt32>, Int32) -> Int32

    private var slsMainConnectionID: SLSMainConnectionIDType?
    private var slsSpaceCreate: SLSSpaceCreateType?
    private var slsSpaceSetAbsoluteLevel: SLSSpaceSetAbsoluteLevelType?
    private var slsAddWindowsToSpaces: SLSAddWindowsToSpacesType?
    private var slsShowSpaces: SLSShowSpacesType?
    private var cgsSetWindowTags: CGSSetWindowTagsType?

    private var lockSpaceID: UInt64?

    private init() {
        loadSymbols()
    }

    private func loadSymbols() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return
        }

        if let sym = dlsym(handle, "SLSMainConnectionID") {
            slsMainConnectionID = unsafeBitCast(sym, to: SLSMainConnectionIDType.self)
        }
        if let sym = dlsym(handle, "SLSSpaceCreate") {
            slsSpaceCreate = unsafeBitCast(sym, to: SLSSpaceCreateType.self)
        }
        if let sym = dlsym(handle, "SLSSpaceSetAbsoluteLevel") {
            slsSpaceSetAbsoluteLevel = unsafeBitCast(sym, to: SLSSpaceSetAbsoluteLevelType.self)
        }
        if let sym = dlsym(handle, "SLSAddWindowsToSpaces") {
            slsAddWindowsToSpaces = unsafeBitCast(sym, to: SLSAddWindowsToSpacesType.self)
        }
        if let sym = dlsym(handle, "SLSShowSpaces") {
            slsShowSpaces = unsafeBitCast(sym, to: SLSShowSpacesType.self)
        }
        if let sym = dlsym(handle, "CGSSetWindowTags") {
            cgsSetWindowTags = unsafeBitCast(sym, to: CGSSetWindowTagsType.self)
        }
    }

    /// Attaches the given window to an unmanaged lock-screen space at level 400
    /// (kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock) and marks it sticky.
    func attachToLockScreenSpace(windowNumber: Int) {
        guard let getMainConnectionID = slsMainConnectionID,
              let createSpace = slsSpaceCreate,
              let setSpaceLevel = slsSpaceSetAbsoluteLevel,
              let addWindows = slsAddWindowsToSpaces,
              let showSpaces = slsShowSpaces else {
            return
        }

        let cid = getMainConnectionID()
        let wid = UInt32(windowNumber)

        // 1. Mark window sticky across all spaces (tag 0x0800 = CGSTagSticky)
        if let setTags = cgsSetWindowTags {
            var tags: [UInt32] = [0x0800, 0]
            _ = setTags(cid, wid, &tags, 32)
        }

        // 2. Ensure lock space exists and set level to 400 (NotificationCenterAtScreenLock)
        let spaceID: UInt64
        if let existing = lockSpaceID {
            spaceID = existing
        } else {
            spaceID = createSpace(cid, 1, nil)
            lockSpaceID = spaceID
        }
        setSpaceLevel(cid, spaceID, 400)

        // 3. Add window to this lock space and display space
        let winArray = [NSNumber(value: wid)] as CFArray
        let spaceArray = [NSNumber(value: spaceID)] as CFArray
        addWindows(cid, winArray, spaceArray)
        showSpaces(cid, spaceArray)
    }
}

@MainActor
final class NotchWindowController: NSObject {

    // MARK: - Properties

    private var window: NotchPanel!
    private weak var viewModel: NotchViewModel?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var scrollLocalMonitor: Any?
    private var isMouseInside: Bool = false
    private var isWindowExpanded: Bool = false
    private var isInteractive: Bool = false
    private var isScreenLocked: Bool = false

    private var activePillSize: CGSize = .zero
    private var hoverRetentionSize: CGSize = .zero
    private var collapseCanvasWorkItem: DispatchWorkItem?

    private var accumulatedScrollX: CGFloat = 0.0
    private var accumulatedScrollY: CGFloat = 0.0
    private var isHorizontalSwipeTriggered: Bool = false
    private var lastProcessedEventTimestamp: TimeInterval = 0

    private let overshootHorizontalMargin: CGFloat = 36.0
    private let overshootBottomMargin:     CGFloat = 24.0

    // MARK: - Init / Deinit

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init()
        setupWindow(viewModel: viewModel)
        setupMouseHoverMonitors()
        observeScreenChanges()
    }

    deinit {
        collapseCanvasWorkItem?.cancel()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor  { NSEvent.removeMonitor(localMouseMonitor) }
        if let scrollLocalMonitor { NSEvent.removeMonitor(scrollLocalMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window Setup

    private func setupWindow(viewModel: NotchViewModel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let canvasFrame = NotchPositionCalculator.fixedCanvasFrame(for: screen)
        activePillSize  = NotchPositionCalculator.hiddenFrame(for: screen).size

        window = NotchPanel(
            contentRect: canvasFrame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        window.isFloatingPanel             = true
        window.becomesKeyOnlyIfNeeded      = true
        window.isMovable                   = false
        window.isMovableByWindowBackground = false
        window.level                       = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1
        )

        window.backgroundColor         = .clear
        window.isOpaque                = false
        window.hasShadow               = false
        window.ignoresMouseEvents      = true   // Pass-through whenever cursor is outside active pill!
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed    = false
        window.canHide                 = false
        window.hidesOnDeactivate       = false
        window.collectionBehavior      = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let rootView = NotchContainerView(viewModel: viewModel)
        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onScrollWheel = { [weak self] event in
            self?.handleScrollOrSwipeEvent(event)
        }
        hostingView.onSwipe = { [weak self] event in
            self?.handleScrollOrSwipeEvent(event)
        }
        window.contentView = hostingView

        SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: window.windowNumber)
        window.orderFrontRegardless()
    }

    // MARK: - Mouse Hover Tracking (Active ONLY when content is present)

    private func setupMouseHoverMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateMouseHover()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.evaluateMouseHover()
            }
            return event
        }

        scrollLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .swipe]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScrollOrSwipeEvent(event)
            }
            return event
        }
    }

    // MARK: - 2-Finger Trackpad Gesture & Swipe Handling

    private func handleScrollOrSwipeEvent(_ event: NSEvent) {
        guard event.timestamp != lastProcessedEventTimestamp else { return }
        lastProcessedEventTimestamp = event.timestamp

        guard let vm = viewModel, vm.isExpanded else {
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
            return
        }

        if event.type == .swipe {
            if event.deltaX < 0 {
                vm.switchToSquareMenu()
            } else if event.deltaX > 0 {
                vm.restoreFromSquareMenu()
            }
            return
        }

        guard event.type == .scrollWheel else { return }

        if event.phase == .began {
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
        }

        if event.phase == .changed || event.phase == .began || (event.phase == [] && event.hasPreciseScrollingDeltas) {
            accumulatedScrollX += event.scrollingDeltaX
            accumulatedScrollY += event.scrollingDeltaY

            guard !isHorizontalSwipeTriggered else { return }

            let absX = abs(accumulatedScrollX)
            let absY = abs(accumulatedScrollY)
            let threshold: CGFloat = 24.0

            if absX > threshold && absX > (absY * 1.20) {
                // In macOS Natural Scrolling (system default):
                // Swiping fingers left on trackpad produces scrollingDeltaX < 0.
                // In Inverted Scrolling:
                // Swiping fingers left produces scrollingDeltaX > 0.
                let isLeftSwipe = event.isDirectionInvertedFromDevice ? (accumulatedScrollX < 0) : (accumulatedScrollX > 0)
                let isRightSwipe = event.isDirectionInvertedFromDevice ? (accumulatedScrollX > 0) : (accumulatedScrollX < 0)

                if isLeftSwipe {
                    isHorizontalSwipeTriggered = true
                    vm.switchToSquareMenu()
                } else if isRightSwipe {
                    isHorizontalSwipeTriggered = true
                    vm.restoreFromSquareMenu()
                }
            }
        }

        if event.phase == .ended || event.phase == .cancelled {
            if !isHorizontalSwipeTriggered {
                let absX = abs(accumulatedScrollX)
                let absY = abs(accumulatedScrollY)
                if absX > 16.0 && absX > (absY * 1.20) {
                    let isLeftSwipe = event.isDirectionInvertedFromDevice ? (accumulatedScrollX < 0) : (accumulatedScrollX > 0)
                    let isRightSwipe = event.isDirectionInvertedFromDevice ? (accumulatedScrollX > 0) : (accumulatedScrollX < 0)
                    if isLeftSwipe {
                        vm.switchToSquareMenu()
                    } else if isRightSwipe {
                        vm.restoreFromSquareMenu()
                    }
                }
            }
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
        }
    }

    func isMouseWithinExpandedRect(of size: CGSize) -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let mouseLoc = NSEvent.mouseLocation
        let envelopeSize = CGSize(
            width: max(size.width, hoverRetentionSize.width),
            height: max(size.height, hoverRetentionSize.height)
        )
        let rect = NotchPositionCalculator.expandedFrame(size: envelopeSize, screen: screen)
            .insetBy(dx: -8, dy: -8)
        return rect.contains(mouseLoc)
    }

    /// Checks whether the mouse cursor is currently resting over the physical notch
    /// or compact wings area (top ~38pt of the screen, horizontally centered).
    func isMouseOverPhysicalNotch() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let mouseLoc = NSEvent.mouseLocation

        if NotchPositionCalculator.isFloatingCapsule(for: screen) {
            let compactFrame = NotchPositionCalculator.compactFrame(for: screen)
                .insetBy(dx: -12, dy: -6)
            return compactFrame.contains(mouseLoc)
        }

        // 1. Check compact frame with comfortable margin (covers physical cutout and compact wings)
        let compactFrame = NotchPositionCalculator.compactFrame(for: screen)
            .insetBy(dx: -12, dy: -6)
        if compactFrame.contains(mouseLoc) {
            return true
        }

        // 2. Direct physical cutout bounds check (top of the screen, horizontally centered)
        let cutoutW = NotchPositionCalculator.notchBaseWidth(for: screen) + 20.0
        let cutoutH = NotchPositionCalculator.effectiveNotchHeight(for: screen) + 8.0
        let cutoutX = (screen.frame.width - cutoutW) / 2.0 + screen.frame.origin.x
        let cutoutY = screen.frame.maxY - cutoutH
        let cutoutRect = NSRect(x: cutoutX, y: cutoutY, width: cutoutW, height: cutoutH)
        return cutoutRect.contains(mouseLoc)
    }

    private func evaluateMouseHover() {
        if isScreenLocked {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
            }
            if isMouseInside {
                isMouseInside = false
                hoverRetentionSize = .zero
                self.viewModel?.setHovered(false)
            }
            return
        }

        guard isInteractive else {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
            }
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Keep hover and hit-testing active while the user is dragging (e.g. volume slider or satellite orb)
        if isMouseInside && (NSEvent.pressedMouseButtons & 1) != 0 {
            window.ignoresMouseEvents = false
            return
        }

        let mouseLoc = NSEvent.mouseLocation

        let pillScreenRect = NotchPositionCalculator.expandedFrame(
            size: activePillSize,
            screen: screen
        )

        var clickHitRect = pillScreenRect.insetBy(dx: -8, dy: -8)
        if viewModel?.hasSecondaryLiveActivity == true {
            clickHitRect.size.width += (SatelliteOrbView.diameter + 18.0)
        }
        if viewModel?.hasLeftSatelliteOrb == true {
            clickHitRect.origin.x -= (SatelliteOrbView.diameter + 18.0)
            clickHitRect.size.width += (SatelliteOrbView.diameter + 18.0)
        }

        let insideClickRect = clickHitRect.contains(mouseLoc)
        if window.ignoresMouseEvents != !insideClickRect {
            window.ignoresMouseEvents = !insideClickRect
        }

        // Dynamic Proximity Dodge for macOS Menu Bar:
        // When in floating capsule mode, DynamicNotch floats detached below the menu bar,
        // so menu bar dodging is not needed (menu bar is 100% click-through).
        let isFloating = NotchPositionCalculator.isFloatingCapsule(for: screen)
        if !isFloating {
            let menuBarHeight = NotchPositionCalculator.effectiveNotchHeight(for: screen)
            let menuBarBottomY = screen.frame.maxY - menuBarHeight
            let isAtTopMenuBarHeight = mouseLoc.y >= (menuBarBottomY - 2.0)

            let dynamicLeftBoundary = clickHitRect.minX
            let dynamicRightBoundary = clickHitRect.maxX

            let isOutsideLeft = mouseLoc.x < (dynamicLeftBoundary - 4.0)
            let isOutsideRight = mouseLoc.x > (dynamicRightBoundary + 4.0)
            let isOverSystemMenuBar = isAtTopMenuBarHeight && !insideClickRect && (isOutsideLeft || isOutsideRight)

            if isOverSystemMenuBar {
                if !window.ignoresMouseEvents {
                    window.ignoresMouseEvents = true
                }
                viewModel?.setMenuBarDodging(true)
                if isMouseInside {
                    isMouseInside = false
                    hoverRetentionSize = .zero
                    self.viewModel?.setHovered(false)
                }
                return
            } else {
                viewModel?.setMenuBarDodging(false)
            }
        } else {
            viewModel?.setMenuBarDodging(false)
        }

        let hoverInside: Bool
        if isMouseInside && hoverRetentionSize != .zero {
            let retentionEnvelope = CGSize(
                width: max(activePillSize.width, hoverRetentionSize.width),
                height: max(activePillSize.height, hoverRetentionSize.height)
            )
            var retentionRect = NotchPositionCalculator.expandedFrame(
                size: retentionEnvelope,
                screen: screen
            ).insetBy(dx: -8, dy: -8)
            if viewModel?.hasSecondaryLiveActivity == true {
                retentionRect.size.width += (SatelliteOrbView.diameter + 18.0)
            }
            if viewModel?.hasLeftSatelliteOrb == true {
                retentionRect.origin.x -= (SatelliteOrbView.diameter + 18.0)
                retentionRect.size.width += (SatelliteOrbView.diameter + 18.0)
            }
            hoverInside = retentionRect.contains(mouseLoc)
            if !hoverInside {
                hoverRetentionSize = .zero
            }
        } else {
            hoverInside = insideClickRect
        }

        guard hoverInside != isMouseInside else { return }
        isMouseInside = hoverInside

        self.viewModel?.setHovered(hoverInside)
    }

    // MARK: - 3-State Canvas Transitions (Zero window.setFrame Calls!)

    /// Called at the start of Phase 1 when shrinking the current menu/wings into the physical notch
    /// before emerging the next action. Preserves the current hover envelope so the temporary
    /// retraction into `hiddenSize` does not trigger a false mouse-exit event.
    func beginRetractTransition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        if isMouseInside {
            hoverRetentionSize = CGSize(
                width: max(hoverRetentionSize.width, activePillSize.width),
                height: max(hoverRetentionSize.height, activePillSize.height)
            )
        }
        isInteractive    = true
        isWindowExpanded = false
        activePillSize   = NotchPositionCalculator.hiddenFrame(for: screen).size
        evaluateMouseHover()
    }

    /// State 3: Expand to full interactive card.
    func expand(
        to size: CGSize,
        preserveHoverRetention: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        if preserveHoverRetention && isMouseInside {
            hoverRetentionSize = CGSize(
                width: max(hoverRetentionSize.width, max(activePillSize.width, size.width)),
                height: max(hoverRetentionSize.height, max(activePillSize.height, size.height))
            )
        } else {
            hoverRetentionSize = size
        }

        isInteractive    = true
        isWindowExpanded = true
        activePillSize   = size
        evaluateMouseHover()
        completion?()
    }

    /// State 2: Show compact side wings (LiveActivity or compact alert active, mouse not hovering).
    func collapseToCompact(completion: (() -> Void)? = nil) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        hoverRetentionSize = .zero
        isInteractive      = true
        isWindowExpanded   = false
        activePillSize     = NotchPositionCalculator.compactFrame(for: screen).size
        evaluateMouseHover()
        completion?()
    }

    /// State 1: Hide completely behind the physical notch (no active action).
    func hideToIdle(completion: (() -> Void)? = nil) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        hoverRetentionSize        = .zero
        isInteractive             = false
        isWindowExpanded          = false
        isMouseInside             = false
        window.ignoresMouseEvents = true
        activePillSize            = NotchPositionCalculator.hiddenFrame(for: screen).size
        completion?()
    }

    /// Toggles whether the floating notch panel can receive key focus for text/keyboard inputs.
    func setKeyFocus(_ enabled: Bool) {
        guard let panel = window else { return }
        if enabled {
            panel.allowsKeyWindow = true
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.allowsKeyWindow = false
            panel.resignKey()
        }
    }

    // MARK: - Lock Screen Handling

    func onScreenLocked() {
        isScreenLocked = true
        isMouseInside = false
        hoverRetentionSize = .zero
        window.ignoresMouseEvents = true

        SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: window.windowNumber)
        window.orderFrontRegardless()

        // Re-order front over loginwindow shield during and after space transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: self.window.windowNumber)
            self.window.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: self.window.windowNumber)
            self.window.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { [weak self] in
            guard let self else { return }
            SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: self.window.windowNumber)
            self.window.orderFrontRegardless()
        }
    }

    func onScreenUnlocked() {
        isScreenLocked = false
        SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: window.windowNumber)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.window.orderFrontRegardless()
            self?.evaluateMouseHover()
        }
    }

    // MARK: - Screen Change Observer

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name:     NSApplication.didChangeScreenParametersNotification,
            object:   nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name:     .notchPresentationModeChanged,
            object:   nil
        )
    }

    @objc func screenParametersChanged() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let canvasFrame = NotchPositionCalculator.fixedCanvasFrame(for: screen)
        if window.frame != canvasFrame {
            window.setFrame(canvasFrame, display: true)
        }
        SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: window.windowNumber)
        window.orderFrontRegardless()
        if !isInteractive {
            activePillSize = NotchPositionCalculator.hiddenFrame(for: screen).size
        } else if !isWindowExpanded {
            activePillSize = NotchPositionCalculator.compactFrame(for: screen).size
        }
        evaluateMouseHover()
    }
}

extension Notification.Name {
    static let notchPresentationModeChanged = Notification.Name("notchPresentationModeChanged")
}
