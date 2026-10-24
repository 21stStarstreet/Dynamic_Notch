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
        screenTransferTimer?.invalidate()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor  { NSEvent.removeMonitor(localMouseMonitor) }
        if let scrollLocalMonitor { NSEvent.removeMonitor(scrollLocalMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window Setup

    private func setupWindow(viewModel: NotchViewModel) {
        let screen = ScreenHelper.targetScreen

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

    // MARK: - Mouse Hover & Active Display Tracking

    private func setupMouseHoverMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleTrackedMouseEvent(event)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleTrackedMouseEvent(event)
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

    private func handleTrackedMouseEvent(_ event: NSEvent) {
        checkScreenTransfer(for: NSEvent.mouseLocation, isClick: event.type == .leftMouseUp)
        // Prevent false hover-exit collapse on the old screen while dwelling or transferring to a new display
        guard pendingScreenCandidate == nil, !isTransferringScreen else { return }
        evaluateMouseHover()
    }

    // MARK: - Smart Display Auto-Detection & Fluid Hand-off

    private var isTransferringScreen: Bool = false
    private var pendingScreenCandidate: NSScreen?
    private var screenTransferTimer: Timer?

    private func checkScreenTransfer(for mouseLoc: NSPoint, isClick: Bool) {
        // Do not interrupt while an animated hand-off is already in flight
        guard !isTransferringScreen else { return }

        // Do not transfer while user is dragging a control on the notch
        if isMouseInside && (NSEvent.pressedMouseButtons & 1) != 0 { return }

        guard let screenUnderCursor = ScreenHelper.screen(containing: mouseLoc) else { return }
        let currentTargetScreen = ScreenHelper.targetScreen

        guard screenUnderCursor != currentTargetScreen else {
            // Mouse returned to current screen -> cancel any pending candidate dwell
            if pendingScreenCandidate != nil {
                screenTransferTimer?.invalidate()
                screenTransferTimer = nil
                pendingScreenCandidate = nil
            }
            return
        }

        // If the user clicked on the new display, transfer immediately without dwell lag!
        if isClick {
            screenTransferTimer?.invalidate()
            screenTransferTimer = nil
            pendingScreenCandidate = nil
            viewModel?.cancelHoverExitTimer()
            executeScreenTransfer(to: screenUnderCursor)
            return
        }

        // Otherwise apply Apple-grade 200ms dwell/hysteresis protection:
        // prevents unwanted flickering when cursor merely brushes a screen edge.
        if pendingScreenCandidate != screenUnderCursor {
            screenTransferTimer?.invalidate()
            pendingScreenCandidate = screenUnderCursor
            viewModel?.cancelHoverExitTimer()
            screenTransferTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self, let target = self.pendingScreenCandidate else { return }
                    self.pendingScreenCandidate = nil
                    self.executeScreenTransfer(to: target)
                }
            }
        }
    }

    private func executeScreenTransfer(to newScreen: NSScreen) {
        guard newScreen != ScreenHelper.targetScreen, !isTransferringScreen else { return }
        isTransferringScreen = true
        pendingScreenCandidate = nil
        screenTransferTimer?.invalidate()
        screenTransferTimer = nil
        viewModel?.cancelHoverExitTimer()

        // Phase 1: Dematerialize (Smoothly scale down and fade out on current screen)
        viewModel?.setScreenTransferring(true)

        // Phase 2: Silent Relocation while invisible (150ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }

            // 1. Commit new target screen
            ScreenHelper.updateTargetScreen(newScreen)

            // 2. Move NSWindow canvas frame silently to new display's coordinate space
            let canvasFrame = NotchPositionCalculator.fixedCanvasFrame(for: newScreen)
            self.window.setFrame(canvasFrame, display: false)
            SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: self.window.windowNumber)
            self.window.orderFrontRegardless()

            // 3. Update active pill size for the new display form-factor
            if !self.isInteractive {
                self.activePillSize = NotchPositionCalculator.hiddenFrame(for: newScreen).size
            } else if !self.isWindowExpanded {
                self.activePillSize = NotchPositionCalculator.compactFrame(for: newScreen).size
            } else if let content = self.viewModel?.displayedContent ?? self.viewModel?.currentAlert ?? self.viewModel?.activeLiveActivity {
                let targetSize = self.viewModel?.effectiveTargetSize(for: content, screen: newScreen) ?? self.activePillSize
                self.activePillSize = targetSize
                self.hoverRetentionSize = targetSize
            }
            self.viewModel?.updateScreenGeometry(for: newScreen)

            // Phase 3: Materialize (Fluid Apple spring entrance on the new screen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self = self else { return }
                self.viewModel?.setScreenTransferring(false)
                self.isTransferringScreen = false
                self.evaluateMouseHover()
            }
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
        let screen = ScreenHelper.targetScreen
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
        let screen = ScreenHelper.targetScreen
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
        let screen = ScreenHelper.targetScreen

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

            let isOverSystemMenuBar: Bool
            if viewModel?.isExpanded == true {
                // When expanded, the notch is an active, open interactive overlay.
                // If the cursor is anywhere inside the expanded card's border/hit area,
                // NEVER dodge. The user is actively interacting with the expanded widget.
                if insideClickRect {
                    isOverSystemMenuBar = false
                } else {
                    let isOutsideExpandedLeft = mouseLoc.x < (clickHitRect.minX - 4.0)
                    let isOutsideExpandedRight = mouseLoc.x > (clickHitRect.maxX + 4.0)
                    isOverSystemMenuBar = isAtTopMenuBarHeight && (isOutsideExpandedLeft || isOutsideExpandedRight)
                }
            } else {
                // In compact mode: wings sit at menu bar height beside the camera cutout.
                // Any cursor movement at menu bar height outside the physical camera cutout
                // must dodge so system menu bar items remain clickable.
                let notchBaseW   = NotchPositionCalculator.notchBaseWidth(for: screen)
                let notchCenterX = screen.frame.midX + screen.frame.origin.x
                let dodgeLeft    = notchCenterX - notchBaseW / 2.0 - 8.0
                let dodgeRight   = notchCenterX + notchBaseW / 2.0 + 8.0

                let isOutsideLeft  = mouseLoc.x < (dodgeLeft  - 4.0)
                let isOutsideRight = mouseLoc.x > (dodgeRight + 4.0)
                isOverSystemMenuBar = isAtTopMenuBarHeight && (isOutsideLeft || isOutsideRight)
            }

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
        let screen = ScreenHelper.targetScreen
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
        let screen = ScreenHelper.targetScreen
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
        let screen = ScreenHelper.targetScreen
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
        ScreenHelper.refreshTargetScreen()
        let screen = ScreenHelper.targetScreen
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
