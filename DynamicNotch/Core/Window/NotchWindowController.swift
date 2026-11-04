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
    var onMouseEntered: ((NSEvent) -> Void)?
    var onMouseExited: ((NSEvent) -> Void)?
    var onMouseMoved: ((NSEvent) -> Void)?

    private var trackingArea: NSTrackingArea?

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEntered?(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(event)
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

struct DesktopSpace: Identifiable, Equatable {
    let id: UInt64
    let displayUUID: String
    let index: Int
    let name: String
    let isCurrent: Bool
    let isFullscreenApp: Bool
    let pid: pid_t?
    let appName: String?
}

struct DisplaySpacesGroup: Identifiable, Equatable {
    var id: String { displayUUID }
    let displayUUID: String
    let displayName: String
    let isTargetDisplay: Bool
    let spaces: [DesktopSpace]
}

final class SkyLightSpaceBridge {
    static let shared = SkyLightSpaceBridge()

    private typealias SLSMainConnectionIDType = @convention(c) () -> UInt32
    private typealias SLSSpaceCreateType = @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
    private typealias SLSSpaceSetAbsoluteLevelType = @convention(c) (UInt32, UInt64, Int32) -> Void
    private typealias SLSAddWindowsToSpacesType = @convention(c) (UInt32, CFArray, CFArray) -> Void
    private typealias SLSShowSpacesType = @convention(c) (UInt32, CFArray) -> Void
    private typealias CGSSetWindowTagsType = @convention(c) (UInt32, UInt32, UnsafePointer<UInt32>, Int32) -> Int32
    private typealias CGSCopyManagedDisplaySpacesType = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias CGSCopySpacesForWindowsType = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SLSCopySpacesType = @convention(c) (UInt32, Int32) -> Unmanaged<CFArray>?
    private typealias SLSSpaceCopyNameType = @convention(c) (UInt32, UInt64) -> Unmanaged<CFString>?

    private var slsMainConnectionID: SLSMainConnectionIDType?
    private var slsSpaceCreate: SLSSpaceCreateType?
    private var slsSpaceSetAbsoluteLevel: SLSSpaceSetAbsoluteLevelType?
    private var slsAddWindowsToSpaces: SLSAddWindowsToSpacesType?
    private var slsShowSpaces: SLSShowSpacesType?
    private var cgsSetWindowTags: CGSSetWindowTagsType?
    private var cgsCopyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesType?
    private var cgsCopySpacesForWindows: CGSCopySpacesForWindowsType?
    private var slsCopySpaces: SLSCopySpacesType?
    private var slsSpaceCopyName: SLSSpaceCopyNameType?

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
        if let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") {
            cgsCopyManagedDisplaySpaces = unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesType.self)
        }
        if let sym = dlsym(handle, "CGSCopySpacesForWindows") {
            cgsCopySpacesForWindows = unsafeBitCast(sym, to: CGSCopySpacesForWindowsType.self)
        }
        if let sym = dlsym(handle, "SLSCopySpaces") {
            slsCopySpaces = unsafeBitCast(sym, to: SLSCopySpacesType.self)
        }
        if let sym = dlsym(handle, "SLSSpaceCopyName") {
            slsSpaceCopyName = unsafeBitCast(sym, to: SLSSpaceCopyNameType.self)
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

    /// Detects whether macOS Mission Control / App Exposé / Show Desktop is currently active on screen.
    func isMissionControlActive() -> Bool {
        // Primary: Query active OS spaces (mask 0x9 = kCGSSpaceIncludesCurrent | kCGSSpaceIncludesOS).
        // When Mission Control, App Exposé, or Show Desktop is presented, Dock activates its dedicated
        // OS spaces ("mission-control", "SpacesBarWindowController", "show-front") in mask 0x9.
        if let getMainConnectionID = slsMainConnectionID,
           let copySpaces = slsCopySpaces,
           let copyName = slsSpaceCopyName {
            let cid = getMainConnectionID()
            if let spaceIDs = copySpaces(cid, 0x9)?.takeRetainedValue() as? [NSNumber] {
                for sid in spaceIDs {
                    guard let rawName = copyName(cid, sid.uint64Value)?.takeRetainedValue() as String? else {
                        continue
                    }
                    if rawName == "mission-control"
                        || rawName == "SpacesBarWindowController"
                        || rawName == "show-front"
                        || rawName.contains("mission-control")
                        || rawName.contains("SpacesBar") {
                        return true
                    }
                }
                return false
            }
        }

        // Fallback: Inspect onscreen Dock windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for win in windowList {
            guard let owner = win[kCGWindowOwnerName as String] as? String, owner == "Dock" else { continue }
            let layer = win[kCGWindowLayer as String] as? Int ?? -1
            if layer == 0 {
                return true
            }
            if let bounds = win[kCGWindowBounds as String] as? [String: Any],
               let y = bounds["Y"] as? CGFloat, y == -1 {
                return true
            }
            let name = win[kCGWindowName as String] as? String ?? ""
            if name.contains("Mission Control") || name.contains("Expose") || name.contains("Exposé") {
                return true
            }
        }
        return false
    }

    /// Returns the display UUID string corresponding to the given NSScreen.
    func displayUUID(for screen: NSScreen) -> String? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenNumber) else {
            return nil
        }
        return (CFUUIDCreateString(nil, uuidRef.takeRetainedValue()) as String)
    }

    /// Queries all connected displays and their spaces (desktops & fullscreen apps).
    func fetchAllSpaceGroups(targetScreen: NSScreen) -> [DisplaySpacesGroup] {
        guard let getMainConnectionID = slsMainConnectionID,
              let copySpaces = cgsCopyManagedDisplaySpaces else {
            return []
        }
        let cid = getMainConnectionID()
        guard let rawDisplays = copySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        let targetUUID = displayUUID(for: targetScreen)
        var groups: [DisplaySpacesGroup] = []

        for (dIdx, dDict) in rawDisplays.enumerated() {
            guard let dUUID = dDict["Display Identifier"] as? String else { continue }
            let currentSpaceID = (dDict["Current Space"] as? [String: Any])?["id64"] as? UInt64 ?? 0
            let rawSpaces = dDict["Spaces"] as? [[String: Any]] ?? []

            let matchingScreen = NSScreen.screens.first { screen in
                displayUUID(for: screen) == dUUID
            }
            let displayName = matchingScreen?.localizedName ?? "Ekran \(dIdx + 1)"

            var desktopCount = 0
            var spaceList: [DesktopSpace] = []

            for sDict in rawSpaces {
                let sid = sDict["id64"] as? UInt64 ?? 0
                let type = sDict["type"] as? Int ?? 0
                let isCurrent = (sid == currentSpaceID)
                let pid = sDict["pid"] as? pid_t

                var name = ""
                var isFS = false
                var appName: String? = nil

                if type == 0 {
                    desktopCount += 1
                    name = "Masaüstü \(desktopCount)"
                } else if type == 4 {
                    isFS = true
                    if let pid = pid, let app = NSRunningApplication(processIdentifier: pid) {
                        appName = app.localizedName
                        name = appName ?? "Tam Ekran"
                    } else {
                        name = "Tam Ekran"
                    }
                } else {
                    desktopCount += 1
                    name = "Masaüstü \(desktopCount)"
                }

                spaceList.append(
                    DesktopSpace(
                        id: sid,
                        displayUUID: dUUID,
                        index: desktopCount,
                        name: name,
                        isCurrent: isCurrent,
                        isFullscreenApp: isFS,
                        pid: pid,
                        appName: appName
                    )
                )
            }

            groups.append(
                DisplaySpacesGroup(
                    displayUUID: dUUID,
                    displayName: displayName,
                    isTargetDisplay: (dUUID == targetUUID),
                    spaces: spaceList
                )
            )
        }

        return groups
    }

    /// Finds the PID of any regular application window located on the specified space ID.
    func findWindowPID(onSpaceID targetSpaceID: UInt64) -> pid_t? {
        guard let getMainConnectionID = slsMainConnectionID,
              let copySpacesForWindows = cgsCopySpacesForWindows else {
            return nil
        }
        let cid = getMainConnectionID()

        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var candidateWIDs: [NSNumber] = []
        var candidatePIDs: [pid_t] = []
        let currentPID = NSRunningApplication.current.processIdentifier

        for win in windowList {
            let layer = win[kCGWindowLayer as String] as? Int ?? -1
            let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let wid = win[kCGWindowNumber as String] as? Int ?? 0

            // Layer 0 is standard app windows. Exclude DynamicNotch and background/system daemons.
            if layer == 0 && pid != currentPID && wid > 0 {
                candidateWIDs.append(NSNumber(value: wid))
                candidatePIDs.append(pid)
            }
        }

        guard !candidateWIDs.isEmpty else { return nil }

        guard let rawSpaces = copySpacesForWindows(cid, 7, candidateWIDs as CFArray)?.takeRetainedValue() as? [NSNumber] else {
            return nil
        }

        for (idx, spaceNum) in rawSpaces.enumerated() {
            if spaceNum.uint64Value == targetSpaceID && idx < candidatePIDs.count {
                let pid = candidatePIDs[idx]
                if let app = NSRunningApplication(processIdentifier: pid),
                   app.activationPolicy == .regular {
                    return pid
                }
            }
        }
        return nil
    }

    /// Safely switches to the target space using native macOS mechanisms:
    /// - Tier 1: For Fullscreen Apps: Activates owning NSRunningApplication.
    /// - Tier 2: For Desktops with open windows: Finds window on target space and activates application natively.
    /// - Tier 3: For Empty Desktops: Warps cursor to target monitor, posts combinedSessionState Control+Arrow events,
    ///   and executes AppleScript System Events fallback.
    func switchToSpaceSafely(targetSpace: DesktopSpace, allSpaces: [DesktopSpace]) {
        func logDebug(_ msg: String) {
            #if DEBUG
            NSLog("[DynamicNotch Space] %@", msg)
            #endif
        }

        logDebug("switchToSpaceSafely -> Target: '\(targetSpace.name)' id=\(targetSpace.id), isFS=\(targetSpace.isFullscreenApp), display=\(targetSpace.displayUUID)")

        // Tier 1: Fullscreen App space
        if targetSpace.isFullscreenApp, let pid = targetSpace.pid {
            logDebug("Tier 1: Activating Fullscreen App pid=\(pid)")
            if let app = NSRunningApplication(processIdentifier: pid) {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
            }
            return
        }

        // Tier 2: Window-Focus Native Activation (if an app has a window on this space)
        if let windowPID = findWindowPID(onSpaceID: targetSpace.id),
           let app = NSRunningApplication(processIdentifier: windowPID) {
            logDebug("Tier 2: Found window on target space owned by '\(app.localizedName ?? "")' (pid \(windowPID)). Activating...")
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            return
        }

        // Tier 3: Empty Desktop navigation via keyboard shortcuts & AppleScript
        guard let currentIdx = allSpaces.firstIndex(where: { $0.isCurrent }),
              let targetIdx = allSpaces.firstIndex(where: { $0.id == targetSpace.id }) else {
            logDebug("Tier 3 Error: Cannot find currentIdx or targetIdx in allSpaces (count=\(allSpaces.count))")
            return
        }

        let diff = targetIdx - currentIdx
        logDebug("Tier 3: currentIdx=\(currentIdx), targetIdx=\(targetIdx), diff=\(diff)")
        guard diff != 0 else { return }

        // Warp mouse cursor to target screen center so macOS routes shortcut to the correct monitor
        if let matchingScreen = NSScreen.screens.first(where: { displayUUID(for: $0) == targetSpace.displayUUID }) {
            let center = CGPoint(x: matchingScreen.frame.midX, y: matchingScreen.frame.midY)
            logDebug("Warping mouse to screen center: \(center)")
            CGWarpMouseCursorPosition(center)
        }

        let isRight = diff > 0
        let keyCode: CGKeyCode = isRight ? 124 : 123 // 124 = Right Arrow, 123 = Left Arrow
        let count = abs(diff)

        DispatchQueue.global(qos: .userInteractive).async {
            guard let src = CGEventSource(stateID: .combinedSessionState) else {
                logDebug("Failed to create combinedSessionState CGEventSource")
                return
            }

            for step in 0..<count {
                if step > 0 {
                    usleep(320000) // 320ms between multi-space jumps
                }

                logDebug("Posting Arrow \(keyCode) with maskControl (step \(step + 1)/\(count))")

                let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
                let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

                keyDown?.flags = .maskControl
                keyUp?.flags   = .maskControl

                // Post to both session and HID event taps
                keyDown?.post(tap: .cgSessionEventTap)
                keyDown?.post(tap: .cghidEventTap)

                usleep(35000) // 35ms hold duration

                keyUp?.post(tap: .cgSessionEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }

            // AppleScript System Events fallback
            DispatchQueue.main.async {
                let scriptText = """
                tell application "System Events"
                    key code \(keyCode) using {control down}
                end tell
                """
                if let appleScript = NSAppleScript(source: scriptText) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let err = error {
                        logDebug("AppleScript fallback error: \(err)")
                    } else {
                        logDebug("AppleScript fallback succeeded")
                    }
                }
            }
        }
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
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isMouseInside: Bool = false
    private var isWindowExpanded: Bool = false
    private var isInteractive: Bool = false
    private var isScreenLocked: Bool = false
    private var idleHoverDwellWorkItem: DispatchWorkItem?

    private var activePillSize: CGSize = .zero
    private var hoverRetentionSize: CGSize = .zero
    private var collapseCanvasWorkItem: DispatchWorkItem?
    private var transitionGraceDeadline: Date = .distantPast

    /// Grants a grace period during which the cursor temporarily resting outside the new card
    /// border will not trigger a premature mouse-exit or watchdog collapse.
    func grantTransitionGrace(duration: TimeInterval = 1.8) {
        transitionGraceDeadline = max(transitionGraceDeadline, Date().addingTimeInterval(duration))
    }

    /// Whether an active transition grace period is currently shielding against false exits.
    var isWithinTransitionGrace: Bool {
        Date() < transitionGraceDeadline
    }

    private var accumulatedScrollX: CGFloat = 0.0
    private var accumulatedScrollY: CGFloat = 0.0
    private var isHorizontalSwipeTriggered: Bool = false
    private var lastProcessedEventTimestamp: TimeInterval = 0

    private let overshootHorizontalMargin: CGFloat = 36.0
    private let overshootBottomMargin:     CGFloat = 24.0

    private var expandedWatchdogTimer: Timer?
    private var interactiveOutsideSince: Date?
    private var hasEnteredInteractiveCard: Bool = false

    private var isMissionControlPresenting: Bool = false
    private var lastMissionControlCheckTime: TimeInterval = 0
    private var cachedMissionControlState: Bool = false
    private var missionControlMonitorTimer: Timer?
    private var missionControlEnterGraceDeadline: TimeInterval = 0

    /// Fast, throttled check for Mission Control active state, syncing transitions automatically.
    func isMissionControlActive() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastMissionControlCheckTime < 0.08 {
            return cachedMissionControlState
        }
        lastMissionControlCheckTime = now
        let active = SkyLightSpaceBridge.shared.isMissionControlActive()
        cachedMissionControlState = active
        if active != isMissionControlPresenting {
            setMissionControlPresenting(active)
        }
        return cachedMissionControlState
    }

    // MARK: - Init / Deinit

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init()
        setupWindow(viewModel: viewModel)
        setupMouseHoverMonitors()
        observeScreenChanges()
        startMissionControlMonitor()
    }

    deinit {
        idleHoverDwellWorkItem?.cancel()
        expandedWatchdogTimer?.invalidate()
        missionControlMonitorTimer?.invalidate()
        collapseCanvasWorkItem?.cancel()
        screenTransferTimer?.invalidate()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor  { NSEvent.removeMonitor(localMouseMonitor) }
        if let scrollLocalMonitor { NSEvent.removeMonitor(scrollLocalMonitor) }
        if let globalKeyMonitor   { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor    { NSEvent.removeMonitor(localKeyMonitor) }
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
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
        window.canHide                 = true
        window.hidesOnDeactivate       = false
        window.collectionBehavior      = [
            .canJoinAllSpaces,
            .stationary,
            .transient,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let rootView = NotchContainerView(viewModel: viewModel)
        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onScrollWheel = { [weak self] event in
            guard let self = self else { return }
            if self.handleMouseWheelOnHorizontalScrollView(event) {
                return
            }
            self.handleScrollOrSwipeEvent(event)
        }
        hostingView.onSwipe = { [weak self] event in
            self?.handleScrollOrSwipeEvent(event)
        }
        hostingView.onMouseMoved = { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleTrackedMouseEvent(event)
            }
        }
        hostingView.onMouseEntered = { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleTrackedMouseEvent(event)
            }
        }
        hostingView.onMouseExited = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                let mouseLoc = NSEvent.mouseLocation
                let screen = ScreenHelper.targetScreen
                let clickHitRect = self.effectiveClickHitRect(for: screen)
                let isInsideCard = clickHitRect.contains(mouseLoc)

                let isInsideCorridor: Bool
                if self.isWithinTransitionGrace && self.hoverRetentionSize != .zero {
                    let retentionEnvelope = CGSize(
                        width: max(self.activePillSize.width, self.hoverRetentionSize.width),
                        height: max(self.activePillSize.height, self.hoverRetentionSize.height)
                    )
                    isInsideCorridor = NotchPositionCalculator.expandedFrame(
                        size: retentionEnvelope,
                        screen: screen
                    ).insetBy(dx: -18, dy: -18).contains(mouseLoc)
                } else {
                    isInsideCorridor = false
                }

                if !isInsideCard && !isInsideCorridor {
                    if self.viewModel?.isHoveringSlider == true {
                        self.viewModel?.isHoveringSlider = false
                    }
                    if self.isMouseInside {
                        self.isMouseInside = false
                        self.hoverRetentionSize = .zero
                        self.transitionGraceDeadline = .distantPast
                        self.window.ignoresMouseEvents = true
                        self.viewModel?.setHovered(false)
                    }
                }
            }
        }
        window.contentView = hostingView
        window.orderFrontRegardless()
        pinWindowAcrossDesktops()
    }

    /// Pins the notch panel into a window-server level space so it behaves like a fixed system
    /// element: it never slides with desktop-switch animations and is simply "there" on every desktop.
    private func pinWindowAcrossDesktops() {
        guard let window, window.windowNumber > 0 else { return }
        SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: window.windowNumber)
    }

    // MARK: - Mouse Hover & Active Display Tracking

    private func setupMouseHoverMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleTrackedMouseEvent(event)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleTrackedMouseEvent(event)
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self = self, event.keyCode == 53 else { return event } // 53 = ESC
            if let vm = self.viewModel, vm.isExpanded, !vm.isShowingOnboardingOrGreeting {
                vm.collapseToIdleOrCompact()
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self = self, event.keyCode == 53 else { return } // 53 = ESC
            MainActor.assumeIsolated {
                if let vm = self.viewModel, vm.isExpanded, !vm.isShowingOnboardingOrGreeting {
                    vm.collapseToIdleOrCompact()
                }
            }
        }

        scrollLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .swipe]
        ) { [weak self] event in
            var shouldConsume = false
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if self.handleMouseWheelOnHorizontalScrollView(event) {
                    shouldConsume = true
                    return
                }
                self.handleScrollOrSwipeEvent(event)
            }
            return shouldConsume ? nil : event
        }
    }

    private func handleTrackedMouseEvent(_ event: NSEvent) {
        if isMissionControlActive() {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
            }
            if isMouseInside {
                isMouseInside = false
                hoverRetentionSize = .zero
                viewModel?.setHovered(false)
            }
            return
        }

        checkScreenTransfer(for: NSEvent.mouseLocation, isClick: event.type == .leftMouseUp || event.type == .leftMouseDown)
        // Prevent false hover-exit collapse on the old screen while dwelling or transferring to a new display
        guard pendingScreenCandidate == nil, !isTransferringScreen else { return }
        evaluateMouseHover()

        if event.type == .leftMouseUp {
            if let vm = viewModel, vm.isInteractingWithControl {
                vm.isInteractingWithControl = false
            }
        }
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
            self.window.orderFrontRegardless()
            self.pinWindowAcrossDesktops()

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

    // MARK: - 2-Finger Trackpad Gesture & Scroll View Handling

    private func effectiveLocationInWindow(for event: NSEvent) -> NSPoint {
        if let eventWindow = event.window, eventWindow == self.window {
            return event.locationInWindow
        }
        return window.convertPoint(fromScreen: NSEvent.mouseLocation)
    }

    private func findScrollView(at locationInWindow: NSPoint, in view: NSView) -> NSScrollView? {
        let localPoint = view.convert(locationInWindow, from: nil)
        guard view.bounds.contains(localPoint) else { return nil }

        for sub in view.subviews.reversed() {
            if let found = findScrollView(at: locationInWindow, in: sub) {
                return found
            }
        }

        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        return nil
    }

    private func isCursorOverScrollableContent(at locationInWindow: NSPoint, isHorizontal: Bool) -> Bool {
        guard let contentView = window.contentView else { return false }
        guard let scrollView = findScrollView(at: locationInWindow, in: contentView) else { return false }

        if isHorizontal {
            let docW = scrollView.documentView?.frame.width ?? 0
            let clipW = scrollView.contentView.frame.width
            // If the document content is wider than the visible clip area, horizontal scrolling is active
            return scrollView.hasHorizontalScroller || docW > (clipW + 2.0)
        } else {
            let docH = scrollView.documentView?.frame.height ?? 0
            let clipH = scrollView.contentView.frame.height
            return scrollView.hasVerticalScroller || docH > (clipH + 2.0)
        }
    }

    @discardableResult
    private func handleMouseWheelOnHorizontalScrollView(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel else { return false }
        guard let contentView = window.contentView else { return false }

        let loc = effectiveLocationInWindow(for: event)
        guard let scrollView = findScrollView(at: loc, in: contentView) else { return false }

        let docW = scrollView.documentView?.frame.width ?? 0
        let clipW = scrollView.contentView.frame.width
        let docH = scrollView.documentView?.frame.height ?? 0
        let clipH = scrollView.contentView.frame.height

        let canScrollHorizontally = scrollView.hasHorizontalScroller || docW > (clipW + 2.0)
        let canScrollVertically = scrollView.hasVerticalScroller || docH > (clipH + 2.0)

        // Only handle horizontal-only scroll views (e.g. Clipboard carousel, Shelf items)
        guard canScrollHorizontally && !canScrollVertically else { return false }

        // If the event already has significant horizontal travel (e.g. trackpad 2-finger horizontal swipe
        // or dedicated horizontal thumb wheel), let native AppKit/SwiftUI handle it
        if abs(event.scrollingDeltaX) > 0.5 || abs(event.deltaX) > 0.5 {
            return false
        }

        // Must have vertical scroll wheel activity
        guard abs(event.scrollingDeltaY) > 0.01 || abs(event.deltaY) > 0.01 else {
            return false
        }

        let clipView = scrollView.contentView
        guard let docView = scrollView.documentView else { return false }

        let maxScrollX = max(0.0, docView.frame.width - clipView.bounds.width)
        guard maxScrollX > 0 else { return true }

        let rawDelta: CGFloat
        if event.hasPreciseScrollingDeltas {
            rawDelta = event.scrollingDeltaY
        } else if abs(event.scrollingDeltaY) > 0.1 {
            rawDelta = event.scrollingDeltaY * 2.5
        } else {
            rawDelta = event.deltaY * 36.0
        }

        let currentX = clipView.bounds.origin.x
        let targetX = min(max(0.0, currentX - rawDelta), maxScrollX)

        if abs(targetX - currentX) > 0.01 {
            clipView.scroll(to: NSPoint(x: targetX, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clipView)
        }

        return true
    }

    private func handleScrollOrSwipeEvent(_ event: NSEvent) {
        guard event.timestamp != lastProcessedEventTimestamp else { return }
        lastProcessedEventTimestamp = event.timestamp

        guard let vm = viewModel, vm.isExpanded else {
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
            return
        }

        // Dedicated 3-finger system swipe gesture always works unless actively scrubbing
        if event.type == .swipe {
            guard !vm.isInteractingWithControl && !vm.isHoveringSlider else { return }
            if event.deltaX < 0 {
                vm.switchToSquareMenu()
            } else if event.deltaX > 0 {
                vm.restoreFromSquareMenu()
            }
            return
        }

        guard event.type == .scrollWheel else { return }

        // 1. If user is currently dragging or hovering a slider/control, suppress all card-level gesture switching
        guard !vm.isInteractingWithControl && !vm.isHoveringSlider else {
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
            return
        }

        // 2. Check if the cursor is directly over an active horizontal scroll view (e.g. Clipboard carousel, Shelf strip)
        // If so, the scroll wheel event belongs entirely to the scroll view, NOT to the card navigation!
        let loc = effectiveLocationInWindow(for: event)
        if isCursorOverScrollableContent(at: loc, isHorizontal: true) {
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
            return
        }

        if event.phase == .began {
            accumulatedScrollX = 0.0
            accumulatedScrollY = 0.0
            isHorizontalSwipeTriggered = false
        }

        // Ignore inertial momentum tail events after fingers leave the trackpad
        guard event.momentumPhase == [] else { return }

        if event.phase == .changed || event.phase == .began || (event.phase == [] && event.hasPreciseScrollingDeltas) {
            accumulatedScrollX += event.scrollingDeltaX
            accumulatedScrollY += event.scrollingDeltaY

            guard !isHorizontalSwipeTriggered else { return }

            let absX = abs(accumulatedScrollX)
            let absY = abs(accumulatedScrollY)
            let threshold: CGFloat = 48.0

            // Require clear horizontal dominance: horizontal travel must be at least 1.4× vertical travel
            if absX > threshold && absX > (absY * 1.40) {
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
            .insetBy(dx: -18, dy: -18)
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

    /// Computes the exact screen bounding rect for hit-testing and outside-click dismissal,
    /// taking into account satellite orbs and expanded margins.
    func effectiveClickHitRect(for screen: NSScreen) -> NSRect {
        let effectiveSize: CGSize
        if isWindowExpanded {
            effectiveSize = CGSize(
                width: max(activePillSize.width, max(viewModel?.pillSize.width ?? 0, viewModel?.expandedContentSize.width ?? 0)),
                height: max(activePillSize.height, max(viewModel?.pillSize.height ?? 0, viewModel?.expandedContentSize.height ?? 0))
            )
        } else {
            effectiveSize = activePillSize
        }

        let pillScreenRect = NotchPositionCalculator.expandedFrame(
            size: effectiveSize,
            screen: screen
        )
        var clickHitRect = pillScreenRect.insetBy(dx: -18, dy: -18)
        if viewModel?.hasSecondaryLiveActivity == true {
            clickHitRect.size.width += (SatelliteOrbView.diameter + 18.0)
        }
        if viewModel?.hasLeftSatelliteOrb == true {
            clickHitRect.origin.x -= (SatelliteOrbView.diameter + 18.0)
            clickHitRect.size.width += (SatelliteOrbView.diameter + 18.0)
        }
        return clickHitRect
    }

    private func evaluateMouseHover() {
        if isScreenLocked || isMissionControlActive() {
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

        if !isInteractive {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
            }
            guard let vm = viewModel, vm.isNotchEnabled, !vm.isNotchTemporarilyHidden else {
                idleHoverDwellWorkItem?.cancel()
                idleHoverDwellWorkItem = nil
                return
            }
            let overNotch = isMouseOverPhysicalNotch()

            if overNotch {
                if idleHoverDwellWorkItem == nil && !isMouseInside {
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self, !self.isInteractive, self.isMouseOverPhysicalNotch() else { return }
                        self.isMouseInside = true
                        self.viewModel?.setHovered(true)
                    }
                    idleHoverDwellWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
                }
            } else {
                idleHoverDwellWorkItem?.cancel()
                idleHoverDwellWorkItem = nil
                if isMouseInside {
                    isMouseInside = false
                    vm.setHovered(false)
                }
            }
            return
        }
        let screen = ScreenHelper.targetScreen

        // Keep hover and hit-testing active while the user is dragging (e.g. volume slider or satellite orb)
        if isMouseInside && (NSEvent.pressedMouseButtons & 1) != 0 {
            let mouseLoc = NSEvent.mouseLocation
            let clickHitRect = effectiveClickHitRect(for: screen)
            if clickHitRect.insetBy(dx: -40, dy: -40).contains(mouseLoc) {
                window.ignoresMouseEvents = false
                return
            }
        }

        let mouseLoc = NSEvent.mouseLocation
        let clickHitRect = effectiveClickHitRect(for: screen)
        let insideClickRect = clickHitRect.contains(mouseLoc)

        // Unified Spatial Hover Evaluation:
        // 1. Direct hit on current card bounds
        // 2. OR cursor in transit corridor during an inter-card grace period
        let hoverInside: Bool
        if insideClickRect {
            hoverInside = true
            // Entered the new card: transition corridor has fulfilled its purpose!
            if isWithinTransitionGrace {
                transitionGraceDeadline = .distantPast
                hoverRetentionSize = .zero
            }
        } else if isWithinTransitionGrace && hoverRetentionSize != .zero {
            let expandedWidth  = viewModel?.isExpanded == true ? max(viewModel?.pillSize.width ?? 0, viewModel?.expandedContentSize.width ?? 0) : 0
            let expandedHeight = viewModel?.isExpanded == true ? max(viewModel?.pillSize.height ?? 0, viewModel?.expandedContentSize.height ?? 0) : 0
            let retentionEnvelope = CGSize(
                width: max(max(activePillSize.width, hoverRetentionSize.width), expandedWidth),
                height: max(max(activePillSize.height, hoverRetentionSize.height), expandedHeight)
            )
            var retentionRect = NotchPositionCalculator.expandedFrame(
                size: retentionEnvelope,
                screen: screen
            ).insetBy(dx: -20, dy: -20)
            if viewModel?.hasSecondaryLiveActivity == true {
                retentionRect.size.width += (SatelliteOrbView.diameter + 20.0)
            }
            if viewModel?.hasLeftSatelliteOrb == true {
                retentionRect.origin.x -= (SatelliteOrbView.diameter + 20.0)
                retentionRect.size.width += (SatelliteOrbView.diameter + 20.0)
            }
            hoverInside = retentionRect.contains(mouseLoc)
            if !hoverInside {
                // Deliberately moved outside even the corridor -> clear grace immediately
                transitionGraceDeadline = .distantPast
                hoverRetentionSize = .zero
            }
        } else {
            hoverInside = false
            hoverRetentionSize = .zero
        }

        if window.ignoresMouseEvents != !hoverInside {
            window.ignoresMouseEvents = !hoverInside
        }

        // State Sanitizer: If the cursor has exited, clear stale slider hover!
        if !hoverInside && self.viewModel?.isHoveringSlider == true {
            self.viewModel?.isHoveringSlider = false
        }

        // Dynamic Proximity Dodge for macOS Menu Bar:
        // When in floating capsule mode, DynamicNotch floats detached below the menu bar,
        // so menu bar dodging is not needed (menu bar is 100% click-through).
        let isFloating = NotchPositionCalculator.isFloatingCapsule(for: screen)
        if !isFloating {
            // NEVER dodge menu bar during Onboarding or Welcome Greeting!
            // The modal greeting/onboarding must always be 100% visible and centered.
            if viewModel?.isShowingOnboardingOrGreeting == true {
                viewModel?.setMenuBarDodging(false)
            } else {
                let menuBarHeight = NotchPositionCalculator.effectiveNotchHeight(for: screen)
                let menuBarBottomY = screen.frame.maxY - menuBarHeight
                let isAtTopMenuBarHeight = mouseLoc.y >= (menuBarBottomY - 2.0)

                let isOverSystemMenuBar: Bool
                if viewModel?.isExpanded == true {
                    // When expanded, the notch is an active, open interactive overlay.
                    // It must never dodge or disappear when expanded!
                    isOverSystemMenuBar = false
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
            }
        } else {
            viewModel?.setMenuBarDodging(false)
        }

        guard hoverInside != isMouseInside else {
            if hoverInside { hasEnteredInteractiveCard = true }
            if viewModel?.isExpanded == true {
                startExpandedWatchdog()
            }
            return
        }
        isMouseInside = hoverInside
        if hoverInside { hasEnteredInteractiveCard = true }
        if viewModel?.isExpanded == true {
            startExpandedWatchdog()
        }

        self.viewModel?.setHovered(hoverInside)
    }

    // MARK: - Expanded Hover Watchdog (Guarantees auto-collapse even when WindowServer drops global mouseMoved events)

    private func startExpandedWatchdog() {
        guard expandedWatchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 0.28, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                guard let vm = self.viewModel, vm.isExpanded, !vm.isShowingOnboardingOrGreeting else {
                    self.stopExpandedWatchdog()
                    return
                }
                // Persistent interactive action cards (Clipboard, Shelf, Timer Setup, Camera Mirror,
                // Quick Actions menu, Notes...) follow a dedicated fallback policy: if the regular
                // hover-exit path never fired (e.g. cards opened by shortcut while the cursor was elsewhere,
                // or dropped global mouse events), collapse once the cursor has stayed outside long enough.
                if vm.isInteractiveActionCardActive {
                    self.evaluateInteractiveCardFallback(vm: vm)
                    return
                }
                self.interactiveOutsideSince = nil

                // The hover watchdog strictly applies only to hover-expanded Live Activities (e.g. music/timer expanded on hover)
                guard vm.activeLiveActivity != nil && vm.currentAlert == nil else { return }

                let mouseLoc = NSEvent.mouseLocation
                let screen = ScreenHelper.targetScreen

                let clickHitRect = self.effectiveClickHitRect(for: screen)
                let isInsideCard = clickHitRect.contains(mouseLoc)

                let isInsideCorridor: Bool
                if self.isWithinTransitionGrace && self.hoverRetentionSize != .zero {
                    let expandedWidth  = max(vm.pillSize.width, vm.expandedContentSize.width)
                    let expandedHeight = max(vm.pillSize.height, vm.expandedContentSize.height)
                    let retentionEnvelope = CGSize(
                        width: max(max(self.activePillSize.width, self.hoverRetentionSize.width), expandedWidth),
                        height: max(max(self.activePillSize.height, self.hoverRetentionSize.height), expandedHeight)
                    )
                    var retentionRect = NotchPositionCalculator.expandedFrame(
                        size: retentionEnvelope,
                        screen: screen
                    ).insetBy(dx: -20, dy: -20)
                    if vm.hasSecondaryLiveActivity {
                        retentionRect.size.width += (SatelliteOrbView.diameter + 20.0)
                    }
                    if vm.hasLeftSatelliteOrb {
                        retentionRect.origin.x -= (SatelliteOrbView.diameter + 20.0)
                        retentionRect.size.width += (SatelliteOrbView.diameter + 20.0)
                    }
                    isInsideCorridor = retentionRect.contains(mouseLoc)
                } else {
                    isInsideCorridor = false
                }

                if !isInsideCard && !isInsideCorridor {
                    if vm.isHoveringSlider {
                        vm.isHoveringSlider = false
                    }
                    self.isMouseInside = false
                    self.hoverRetentionSize = .zero
                    self.transitionGraceDeadline = .distantPast
                    self.window.ignoresMouseEvents = true
                    vm.collapseToIdleOrCompact()
                    self.stopExpandedWatchdog()
                }
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        expandedWatchdogTimer = timer
    }

    private func stopExpandedWatchdog() {
        expandedWatchdogTimer?.invalidate()
        expandedWatchdogTimer = nil
        interactiveOutsideSince = nil
    }

    /// Whether the notch panel currently owns keyboard focus (active typing session).
    var isPanelKeyWindow: Bool {
        window?.isKeyWindow == true
    }

    /// Fallback auto-collapse for interactive action cards. Never fires during onboarding,
    /// typing sessions, drags, Mission Control, screen hand-offs or transition grace periods.
    private func evaluateInteractiveCardFallback(vm: NotchViewModel) {
        guard !isTransferringScreen,
              pendingScreenCandidate == nil,
              !isMissionControlActive(),
              !isWithinTransitionGrace,
              (NSEvent.pressedMouseButtons & 1) == 0,
              !vm.shouldSuppressAutoCollapse,
              vm.pendingTransitionTarget == nil else {
            interactiveOutsideSince = nil
            return
        }

        let mouseLoc = NSEvent.mouseLocation
        let screen = ScreenHelper.targetScreen
        if effectiveClickHitRect(for: screen).contains(mouseLoc) {
            hasEnteredInteractiveCard = true
            interactiveOutsideSince = nil
            return
        }

        let now = Date()
        guard let since = interactiveOutsideSince else {
            interactiveOutsideSince = now
            return
        }
        // Cursor visited the card and left -> short delay. Never visited -> generous delay.
        let required: TimeInterval = hasEnteredInteractiveCard ? 0.6 : 3.5
        if now.timeIntervalSince(since) >= required {
            interactiveOutsideSince = nil
            isMouseInside = false
            hoverRetentionSize = .zero
            window.ignoresMouseEvents = true
            vm.collapseToIdleOrCompact()
        }
    }

    // MARK: - 3-State Canvas Transitions (Zero window.setFrame Calls!)

    /// Called at the start of Phase 1 when shrinking the current menu/wings into the physical notch
    /// before emerging the next action. Preserves the current hover envelope so the temporary
    /// retraction into `hiddenSize` does not trigger a false mouse-exit event.
    func beginRetractTransition() {
        let screen = ScreenHelper.targetScreen
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        grantTransitionGrace(duration: 1.8)

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
        transitionGrace: TimeInterval = 0.0,
        completion: (() -> Void)? = nil
    ) {
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        if transitionGrace > 0 {
            grantTransitionGrace(duration: transitionGrace)
        }

        if (preserveHoverRetention && isWithinTransitionGrace) || (isWithinTransitionGrace && hoverRetentionSize != .zero) {
            hoverRetentionSize = CGSize(
                width: max(hoverRetentionSize.width, max(activePillSize.width, size.width)),
                height: max(hoverRetentionSize.height, max(activePillSize.height, size.height))
            )
        } else {
            hoverRetentionSize = .zero
        }

        isInteractive    = true
        isWindowExpanded = true
        activePillSize   = size
        startExpandedWatchdog()
        evaluateMouseHover()
        completion?()
    }

    /// State 2: Show compact side wings (LiveActivity or compact alert active, mouse not hovering).
    func collapseToCompact(completion: (() -> Void)? = nil) {
        let screen = ScreenHelper.targetScreen
        stopExpandedWatchdog()
        idleHoverDwellWorkItem?.cancel()
        idleHoverDwellWorkItem = nil
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        interactiveOutsideSince = nil
        hasEnteredInteractiveCard = false
        transitionGraceDeadline = .distantPast
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
        stopExpandedWatchdog()
        idleHoverDwellWorkItem?.cancel()
        idleHoverDwellWorkItem = nil
        collapseCanvasWorkItem?.cancel()
        collapseCanvasWorkItem = nil

        interactiveOutsideSince   = nil
        hasEnteredInteractiveCard = false
        transitionGraceDeadline   = .distantPast
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
        viewModel?.collapseToIdleOrCompact()

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

    // MARK: - Screen & Space Change Observers

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

        // macOS Active Space / Desktop Change
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name:     NSWorkspace.activeSpaceDidChangeNotification,
            object:   nil
        )

        // Distributed Mission Control / Exposé Notifications
        let exposeEnterNames = [
            "com.apple.expose.front",
            "com.apple.expose.awake",
            "com.apple.expose.enter",
            "com.apple.dock.missioncontrol",
            "com.apple.showdesktop.enter"
        ]
        for name in exposeEnterNames {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(missionControlEnterReceived),
                name:     NSNotification.Name(name),
                object:   nil
            )
        }

        let exposeExitNames = [
            "com.apple.expose.exit",
            "com.apple.showdesktop.exit"
        ]
        for name in exposeExitNames {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(missionControlExitReceived),
                name:     NSNotification.Name(name),
                object:   nil
            )
        }
    }

    private func startMissionControlMonitor() {
        missionControlMonitorTimer?.invalidate()
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollMissionControlState()
            }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        missionControlMonitorTimer = timer
    }

    private func pollMissionControlState() {
        guard !isScreenLocked else { return }
        let now = CACurrentMediaTime()
        let active = SkyLightSpaceBridge.shared.isMissionControlActive()
        if !active && isMissionControlPresenting && now < missionControlEnterGraceDeadline {
            return
        }
        lastMissionControlCheckTime = now
        cachedMissionControlState = active
        if active != isMissionControlPresenting {
            setMissionControlPresenting(active)
        }
    }

    func notifyMissionControlLaunching() {
        missionControlEnterGraceDeadline = CACurrentMediaTime() + 0.55
        setMissionControlPresenting(true)
    }

    private func setMissionControlPresenting(_ presenting: Bool) {
        guard presenting != isMissionControlPresenting else { return }
        isMissionControlPresenting = presenting
        cachedMissionControlState = presenting

        if presenting {
            missionControlEnterGraceDeadline = max(missionControlEnterGraceDeadline, CACurrentMediaTime() + 0.35)
            idleHoverDwellWorkItem?.cancel()
            idleHoverDwellWorkItem = nil
            stopExpandedWatchdog()
            setKeyFocus(false)
            window.ignoresMouseEvents = true
            isMouseInside = false
            hoverRetentionSize = .zero
            transitionGraceDeadline = .distantPast
            viewModel?.onMissionControlEntered()
        } else {
            window.orderFrontRegardless()
            pinWindowAcrossDesktops()
            viewModel?.onMissionControlExited()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.evaluateMouseHover()
            }
        }
    }

    @objc private func activeSpaceChanged() {
        MainActor.assumeIsolated {
            // Keep the panel pinned and in front on the newly active desktop (no re-appear lag).
            self.window.orderFrontRegardless()
            self.pinWindowAcrossDesktops()
            self.pollMissionControlState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.pollMissionControlState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                self?.pollMissionControlState()
            }
            guard !self.isMissionControlPresenting,
                  let vm = self.viewModel,
                  vm.isExpanded else { return }
            if !vm.isShowingOnboardingOrGreeting {
                vm.collapseToIdleOrCompact()
            }
        }
    }

    @objc private func missionControlEnterReceived() {
        MainActor.assumeIsolated {
            self.setMissionControlPresenting(true)
        }
    }

    @objc private func missionControlExitReceived() {
        MainActor.assumeIsolated {
            self.setMissionControlPresenting(false)
        }
    }

    @objc func screenParametersChanged() {
        ScreenHelper.refreshTargetScreen()
        let screen = ScreenHelper.targetScreen
        let canvasFrame = NotchPositionCalculator.fixedCanvasFrame(for: screen)
        if window.frame != canvasFrame {
            window.setFrame(canvasFrame, display: true)
        }
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
