// NotchContainer.swift
// DynamicNotch / UI / Components
//
// Root SwiftUI container hosted inside NotchWindowController's NotchHostingView.
//
// 3-State Visual Architecture
// ───────────────────────────
// 1. Completely Hidden (`!viewModel.hasActiveContent`):
//    • Renders with 0 opacity behind the physical camera cutout — nothing is
//      shown on screen when there is no active action.
// 2. Compact Mode (`viewModel.hasActiveContent && !viewModel.isExpanded`):
//    • Displays ONLY `CompactNotchWingsView` flanking the physical camera cutout
//      (e.g. mini album art on left, live audio visualizer on right).
// 3. Expanded Mode (`viewModel.hasActiveContent && viewModel.isExpanded`):
//    • Triggered on mouse hover (over an active LiveActivity) or on an Alert.
//    • Displays the full expanded card below the physical camera cutout.

import SwiftUI
import AppKit

struct NotchContainerView: View {

    @ObservedObject var viewModel: NotchViewModel

    @State private var orbDragOffset: CGFloat = 0.0
    @State private var isDraggingOrb: Bool = false
    @State private var isHoveringOrb: Bool = false
    @State private var leftOrbDragOffset: CGFloat = 0.0
    @State private var isDraggingLeftOrb: Bool = false
    @State private var isHoveringLeftOrb: Bool = false

    private var screen: NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private var isFloating: Bool {
        NotchPositionCalculator.isFloatingCapsule(for: screen)
    }

    private var floatingTopOffset: CGFloat {
        NotchPositionCalculator.floatingTopOffset(for: screen)
    }

    private var topCutoutClearance: CGFloat {
        isFloating ? 0.0 : NotchPositionCalculator.effectiveNotchHeight(for: screen)
    }

    private var physicalCutoutWidth: CGFloat {
        NotchPositionCalculator.notchBaseWidth(for: screen)
    }

    private var isDisplayingAlert: Bool {
        viewModel.displayedContent?.isAlert == true
    }

    private var effectivePillSize: CGSize {
        if viewModel.isMenuBarDodging {
            return NotchPositionCalculator.hiddenFrame(for: screen).size
        }
        return viewModel.pillSize
    }

    private var topEarRadius: CGFloat {
        if viewModel.isMenuBarDodging {
            return 6.0
        }
        if viewModel.isExpanded {
            switch viewModel.displayedContent {
            case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
                return 40.0
            case .screenshot:
                return 38.0
            case .clipboard, .noInternet, .shelf, .quickNote, .quickReminder:
                return 12.0
            case .onboarding, .emptySquareMenu:
                return 14.0
            case .timer, .timerSetup:
                return NotchPositionCalculator.expandedTopEarRadius
            default:
                break
            }
            if viewModel.displayedContent?.prefersCompactPresentation == true && !VolumeHUDViewModel.shared.isAudioRouteExpanded {
                return NotchPositionCalculator.compactTopEarRadius
            }
            return isDisplayingAlert ? 12.0 : NotchPositionCalculator.expandedTopEarRadius
        } else if viewModel.hasActiveContent && !viewModel.isCompactWingsSwappingOut {
            return NotchPositionCalculator.compactTopEarRadius
        } else {
            return 6.0
        }
    }

    private var bottomCornerRadius: CGFloat {
        if viewModel.isMenuBarDodging {
            return 10.0
        }
        if viewModel.isExpanded {
            switch viewModel.displayedContent {
            case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
                return 48.0
            case .screenshot:
                return 44.0
            case .accessibilityPermissionRequired:
                return 26.0
            case .clipboard, .noInternet, .quickReminder, .quickNote:
                return 20.0
            case .shelf, .externalDrive:
                return 22.0
            case .externalDriveEjected:
                return 18.0
            case .timer, .timerSetup, .onboarding, .emptySquareMenu:
                return 24.0
            case .volumeChange, .muted:
                return VolumeHUDViewModel.shared.isAudioRouteExpanded ? 24.0 : 18.0
            case .brightnessChange, .screenRecording:
                return 16.0
            case .download:
                return 19.0
            case .some(let content) where content.isAlert:
                return 17.0
            default:
                return 21.0
            }
        } else if viewModel.hasActiveContent && !viewModel.isCompactWingsSwappingOut {
            return 12.0
        } else {
            return 10.0
        }
    }

    private var capsuleCornerRadius: CGFloat {
        if isFloating {
            if !viewModel.isExpanded {
                return effectivePillSize.height / 2.0
            }
            return bottomCornerRadius
        }
        return bottomCornerRadius
    }

    private var expandedTopPadding: CGFloat {
        if isFloating {
            switch viewModel.displayedContent {
            case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
                return 16.0
            case .screenshot:
                return 20.0
            case .quickNote, .quickReminder:
                return 13.0
            case .quickNoteSaved, .quickReminderSaved:
                return 12.0
            case .spotifyAuthorized, .accessibilityPermissionRequired:
                return 16.0
            case .clipboard, .noInternet, .shelf, .externalDrive, .externalDriveEjected, .hotspot:
                return 16.0
            case .timer:
                return 12.0
            case .timerSetup:
                return 14.0
            case .volumeChange, .muted:
                return 15.0
            case .onboarding:
                return 18.0
            case .welcomeGreeting:
                return 12.0
            case .emptySquareMenu:
                return 10.0
            case .nowPlaying:
                return 12.0
            default:
                return isDisplayingAlert ? 12.0 : 14.0
            }
        }

        switch viewModel.displayedContent {
        case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
            return topCutoutClearance + 6.0
        case .screenshot:
            return topCutoutClearance + 12.0
        case .clipboard, .noInternet, .shelf, .externalDrive, .externalDriveEjected, .quickNote, .quickReminder:
            return topCutoutClearance + 7.0
        case .timer, .timerSetup:
            return topCutoutClearance + 9.0
        case .volumeChange, .muted:
            return topCutoutClearance + 7.0
        case .onboarding:
            return topCutoutClearance + 12.0
        case .welcomeGreeting:
            return topCutoutClearance + 6.0
        case .spotifyAuthorized:
            return topCutoutClearance + 24.0
        case .accessibilityPermissionRequired:
            return topCutoutClearance + 12.0
        case .emptySquareMenu:
            return topCutoutClearance + 8.0
        default:
            return topCutoutClearance + (isDisplayingAlert ? 5.0 : 7.0)
        }
    }

    private var expandedBottomPadding: CGFloat {
        switch viewModel.displayedContent {
        case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
            return 16.0
        case .screenshot:
            return 32.0
        case .quickNote, .quickReminder:
            return 13.0
        case .quickNoteSaved, .quickReminderSaved:
            return 12.0
        case .spotifyAuthorized:
            return 24.0
        case .accessibilityPermissionRequired:
            return 16.0
        case .clipboard, .noInternet, .shelf, .externalDrive, .externalDriveEjected, .hotspot:
            return 16.0
        case .timer:
            return 0.0
        case .emptySquareMenu:
            return 12.0
        case .timerSetup:
            return 9.0
        case .volumeChange, .muted:
            return 15.0
        case .onboarding:
            return 20.0
        case .welcomeGreeting:
            return 8.0
        case .nowPlaying:
            return 12.0
        default:
            return isDisplayingAlert ? 8.0 : 11.0
        }
    }

    private var expandedHorizontalPadding: CGFloat {
        switch viewModel.displayedContent {
        case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
            return 36.0
        case .screenshot:
            return 60.0
        case .clipboard, .noInternet:
            // 12.0 (top ear radius / straight wall offset) + 15.0 (margin) = 27.0pt.
            // Exactly matches the 15.0pt bottom margin!
            return 27.0
        case .accessibilityPermissionRequired:
            return 22.0
        case .shelf, .externalDrive, .hotspot, .quickNote, .quickReminder, .spotifyAuthorized:
            return 24.0
        case .timer, .timerSetup:
            return 26.0
        case .onboarding:
            return 32.0
        case .welcomeGreeting:
            return 24.0
        case .emptySquareMenu:
            return 20.0
        default:
            if viewModel.displayedContent?.prefersCompactPresentation == true && !VolumeHUDViewModel.shared.isAudioRouteExpanded {
                return NotchPositionCalculator.compactTopEarRadius + 14.0
            } else if isDisplayingAlert {
                return 26.0
            } else {
                return NotchPositionCalculator.expandedTopEarRadius + 14.0
            }
        }
    }

    private var expandedContentAlignment: Alignment {
        switch viewModel.displayedContent {
        case .bluetoothConnected(let name) where AirPodsModel(deviceName: name).supportsFullAnimation:
            return .top
        case .screenshot:
            return .top
        case .clipboard, .noInternet, .timer, .timerSetup, .shelf, .hotspot, .onboarding, .welcomeGreeting, .quickNote, .quickReminder, .accessibilityPermissionRequired, .spotifyAuthorized:
            return .top
        case .nowPlaying:
            return .top
        case .emptySquareMenu:
            return .top
        default:
            return .center
        }
    }

    private var collapsedContentScaleX: CGFloat {
        let targetW   = max(viewModel.pillSize.width, 1)
        let expandedW = max(viewModel.expandedContentSize.width, 1)
        return min(0.92, max(0.42, targetW / expandedW))
    }

    private var collapsedContentScaleY: CGFloat {
        let targetH   = max(viewModel.pillSize.height, 1)
        let expandedH = max(viewModel.expandedContentSize.height, 1)
        return min(0.75, max(0.30, targetH / expandedH))
    }

    var body: some View {
        ZStack(alignment: .top) {
            mainNotchCard
                .offset(y: isFloating ? floatingTopOffset : 0)

            // SATELLITE ORB: Flanking secondary Live Activity (120 FPS lockstep sync with notch width!)
            if viewModel.hasSecondaryLiveActivity, let secondary = viewModel.secondaryLiveActivity {
                SatelliteOrbView(
                    content: secondary,
                    isDragging: isDraggingOrb
                )
                .scaleEffect(isDraggingOrb ? 0.92 : (isHoveringOrb ? 1.04 : ((viewModel.isCompactWingsSwappingOut || viewModel.isMenuBarDodging) ? 0.35 : 1.0)))
                .opacity((viewModel.isCompactWingsSwappingOut || viewModel.isMenuBarDodging) ? 0.0 : 1.0)
                .offset(
                    x: (effectivePillSize.width / 2.0) + (isFloating ? 8.0 : NotchPositionCalculator.orbGap) + (SatelliteOrbView.diameter / 2.0) + orbDragOffset,
                    y: (isFloating ? floatingTopOffset : 0) + (isFloating ? ((effectivePillSize.height - SatelliteOrbView.diameter) / 2.0) : max(2.0, (topCutoutClearance - SatelliteOrbView.diameter) / 2.0))
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringOrb = hovering
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingOrb = true
                            let dx = value.translation.width
                            if dx < 0 {
                                // Dragging left towards notch center
                                let maxDrag: CGFloat = -42.0
                                if dx < maxDrag {
                                    let excess = dx - maxDrag
                                    orbDragOffset = maxDrag + (excess * 0.20)
                                } else {
                                    orbDragOffset = dx
                                }
                            } else {
                                // Rubber band resistance if dragging right
                                orbDragOffset = dx * 0.18
                            }
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let totalTravel = hypot(dx, dy)
                            let predictedDx = value.predictedEndTranslation.width
                            let swapThreshold: CGFloat = -16.0

                            isDraggingOrb = false

                            let isTap = totalTravel < 8.0
                            let isDragToCenter = dx <= swapThreshold || predictedDx <= swapThreshold

                            if isTap || isDragToCenter {
                                // Clicked / tapped or dragged into notch -> Swap activities with Apple fluid spring!
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                                    orbDragOffset = 0.0
                                    viewModel.swapLiveActivities()
                                }
                            } else {
                                // Rebound back to rest position
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                    orbDragOffset = 0.0
                                }
                            }
                        }
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.18, anchor: .leading)
                            .combined(with: .offset(x: -16, y: 0))
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.18, anchor: .leading)
                            .combined(with: .offset(x: -16, y: 0))
                            .combined(with: .opacity)
                    )
                )
            }

            // LEFT SATELLITE ORB: Flanking left side for concurrent Alert or Secondary Live Activity
            if viewModel.hasLeftSatelliteOrb, let leftContent = viewModel.leftSatelliteContent {
                SatelliteOrbView(
                    content: leftContent,
                    isDragging: isDraggingLeftOrb
                )
                .scaleEffect(isDraggingLeftOrb ? 0.92 : (isHoveringLeftOrb ? 1.04 : ((viewModel.isCompactWingsSwappingOut || viewModel.isMenuBarDodging) ? 0.35 : 1.0)))
                .opacity((viewModel.isCompactWingsSwappingOut || viewModel.isMenuBarDodging) ? 0.0 : 1.0)
                .offset(
                    x: -((effectivePillSize.width / 2.0) + (isFloating ? 8.0 : NotchPositionCalculator.orbGap) + (SatelliteOrbView.diameter / 2.0)) + leftOrbDragOffset,
                    y: (isFloating ? floatingTopOffset : 0) + (isFloating ? ((effectivePillSize.height - SatelliteOrbView.diameter) / 2.0) : max(2.0, (topCutoutClearance - SatelliteOrbView.diameter) / 2.0))
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringLeftOrb = hovering
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingLeftOrb = true
                            let dx = value.translation.width
                            if dx > 0 {
                                // Dragging right towards notch center
                                let maxDrag: CGFloat = 42.0
                                if dx > maxDrag {
                                    let excess = dx - maxDrag
                                    leftOrbDragOffset = maxDrag + (excess * 0.20)
                                } else {
                                    leftOrbDragOffset = dx
                                }
                            } else {
                                // Rubber band resistance if dragging left
                                leftOrbDragOffset = dx * 0.18
                            }
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let dist = sqrt(dx * dx + dy * dy)
                            let isTap = dist < 4.0
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                leftOrbDragOffset = 0.0
                                isDraggingLeftOrb = false
                            }
                            if isTap || dx > 24.0 {
                                viewModel.promoteLeftSatelliteToMainNotch()
                            }
                        }
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.18, anchor: .trailing)
                            .combined(with: .offset(x: 16, y: 0))
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.18, anchor: .trailing)
                            .combined(with: .offset(x: 16, y: 0))
                            .combined(with: .opacity)
                    )
                )
            }
        }
        .animation(
            .spring(response: 0.24, dampingFraction: 0.88),
            value: viewModel.hasSecondaryLiveActivity
        )
        .animation(
            .spring(response: 0.24, dampingFraction: 0.88),
            value: viewModel.hasLeftSatelliteOrb
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mainNotchCard: some View {
        ZStack(alignment: .top) {
            // Pure black Dynamic Notch silhouette sized directly to `pillSize`
            // so the path morphs at a locked 120 FPS without ZStack size jumps.
            if isFloating {
                DynamicIslandShape(cornerRadius: capsuleCornerRadius)
                    .fill(Color.black)
                    .overlay(
                        DynamicIslandRimShape(cornerRadius: capsuleCornerRadius)
                            .stroke(rimStrokeColor, lineWidth: 0.85)
                    )
                    .frame(
                        width: effectivePillSize.width,
                        height: effectivePillSize.height
                    )
                    .shadow(
                        color: .black.opacity((viewModel.isExpanded && !viewModel.isMenuBarDodging) ? 0.45 : (viewModel.hasActiveContent ? 0.28 : 0.0)),
                        radius: viewModel.isExpanded ? 16 : 8,
                        x: 0,
                        y: viewModel.isExpanded ? 8 : 4
                    )
            } else {
                NotchShape(
                    cornerRadius: bottomCornerRadius,
                    topEarRadius: topEarRadius
                )
                .fill(Color.black)
                .overlay(
                    NotchRimShape(
                        topEarRadius: topEarRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                    .stroke(
                        rimStrokeColor,
                        lineWidth: 0.85
                    )
                )
                .frame(
                    width: effectivePillSize.width,
                    height: effectivePillSize.height
                )
                .shadow(
                    color: .black.opacity((viewModel.isExpanded && !viewModel.isMenuBarDodging) ? 0.42 : 0.0),
                    radius: 12,
                    x: 0,
                    y: 5
                )
            }

            // COMPACT LAYER: Small left & right icons beside the physical notch or inside floating capsule
            CompactNotchWingsView(
                viewModel: viewModel,
                cutoutWidth: physicalCutoutWidth,
                barHeight: isFloating ? effectivePillSize.height : (topCutoutClearance + NotchPositionCalculator.compactVerticalExtension),
                isFloating: isFloating
            )
            .padding(.horizontal, isFloating ? 2.0 : NotchPositionCalculator.compactTopEarRadius)
            .frame(
                width: isFloating ? effectivePillSize.width : NotchPositionCalculator.compactFrame(for: screen).width,
                height: isFloating ? effectivePillSize.height : (topCutoutClearance + NotchPositionCalculator.compactVerticalExtension),
                alignment: .center
            )
            .allowsHitTesting(!viewModel.isScreenLocked && !viewModel.isExpanded && viewModel.hasActiveContent && !viewModel.isMenuBarDodging)

            // EXPANDED LAYER: Full interactive card or alert banner below the camera cutout.
            NotchContentRouter(viewModel: viewModel)
                .padding(.top, expandedTopPadding)
                .padding(.bottom, expandedBottomPadding)
                .padding(.horizontal, expandedHorizontalPadding)
                .frame(
                    width: viewModel.expandedContentSize.width,
                    height: viewModel.expandedContentSize.height,
                    alignment: expandedContentAlignment
                )
                .scaleEffect(
                    x: viewModel.isExpanded ? 1.0 : collapsedContentScaleX,
                    y: viewModel.isExpanded ? 1.0 : collapsedContentScaleY,
                    anchor: .top
                )
                .offset(y: viewModel.isExpanded ? 0 : -10)
                .opacity((viewModel.isExpanded && !viewModel.isMenuBarDodging) ? 1.0 : 0.0)
                .allowsHitTesting(!viewModel.isScreenLocked && viewModel.isExpanded && !viewModel.isMenuBarDodging)
        }
        .frame(
            width: effectivePillSize.width,
            height: effectivePillSize.height,
            alignment: .top
        )
        .clipShape(
            isFloating
                ? AnyShape(DynamicIslandShape(cornerRadius: capsuleCornerRadius))
                : AnyShape(NotchShape(cornerRadius: bottomCornerRadius, topEarRadius: topEarRadius))
        )
        .contentShape(
            isFloating
                ? AnyShape(DynamicIslandShape(cornerRadius: capsuleCornerRadius))
                : AnyShape(NotchShape(cornerRadius: bottomCornerRadius, topEarRadius: topEarRadius))
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    guard viewModel.isExpanded else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) * 1.25 {
                        if dx < -22 {
                            viewModel.switchToSquareMenu()
                        } else if dx > 22 {
                            viewModel.restoreFromSquareMenu()
                        }
                    }
                }
        )
        .opacity(viewModel.isNotchVisible ? 1.0 : 0.0)
        .contextMenu {
            let drives = ExternalDriveManager.shared.mountedDrives
            if !drives.isEmpty {
                Button {
                    viewModel.toggleExternalDriveManager()
                } label: {
                    Label("Harici Sürücüler (⌥⇧E)", systemImage: "externaldrive.fill")
                }
                Divider()
                ForEach(drives) { drive in
                    Menu {
                        Button("Finder'da Aç") {
                            ExternalDriveManager.shared.openInFinder(drive: drive)
                        }
                        Button("Güvenle Çıkar") {
                            ExternalDriveManager.shared.eject(drive: drive)
                        }
                    } label: {
                        Label("\(drive.name) (\(drive.availableCapacityFormatted) boş)", systemImage: drive.driveType.iconName)
                    }
                }
                if drives.count > 1 {
                    Button("Tümünü Çıkar") {
                        ExternalDriveManager.shared.ejectAll()
                    }
                }
                Divider()
            }
            Button {
                viewModel.onOpenSettings?()
            } label: {
                Label("Ayarlar...", systemImage: "gearshape")
            }
        }
    }

    private var rimStrokeColor: Color {
        if viewModel.isExpanded {
            if case .batteryLow = viewModel.displayedContent {
                return Color.notchRed.opacity(0.35)
            }
            if case .timer = viewModel.displayedContent {
                return Color(red: 0.975, green: 0.565, blue: 0.187).opacity(0.55)
            }
            if case .noInternet = viewModel.displayedContent {
                return Color(red: 0.98, green: 0.58, blue: 0.12).opacity(0.40)
            }
            return Color.white.opacity(0.14)
        } else if viewModel.hasActiveContent && !viewModel.isCompactWingsSwappingOut {
            if case .timer = viewModel.displayedCompactActivity {
                return Color(red: 0.975, green: 0.565, blue: 0.187).opacity(0.28)
            }
            if case .noInternet = viewModel.displayedCompactActivity {
                return Color(red: 0.98, green: 0.58, blue: 0.12).opacity(0.30)
            }
            return Color.white.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Compact Wings View (Left & Right Mini Icons Beside the Physical Notch)

struct CompactNotchWingsView: View {

    @ObservedObject var viewModel: NotchViewModel
    let cutoutWidth: CGFloat
    let barHeight: CGFloat
    var isFloating: Bool = false

    private let wingWidth: CGFloat = NotchPositionCalculator.compactWingWidth

    private var isShowingLockWings: Bool {
        (viewModel.isScreenLocked || viewModel.isLockScreenUnlocking)
            && viewModel.currentAlert == nil
    }

    private var isShowingWings: Bool {
        viewModel.hasActiveContent
            && !viewModel.isExpanded
            && !viewModel.isCompactWingsSwappingOut
            && !viewModel.isMenuBarDodging
            && (viewModel.displayedCompactActivity != nil || viewModel.isScreenLocked || viewModel.isLockScreenUnlocking)
    }

    private var activityContent: NotchState.ContentType? {
        viewModel.displayedCompactActivity ?? viewModel.activeLiveActivity
    }

    var body: some View {
        HStack(spacing: 0) {
            leftWingContent
                .id(activityContent?.kindIdentifier ?? "empty-left")
                .transition(.scale(scale: 0.70).combined(with: .opacity))
                .frame(width: isFloating ? 28 : wingWidth, height: barHeight, alignment: .center)
                .padding(.leading, isFloating ? 10 : 0)
                .scaleEffect(isShowingWings ? 1.0 : 0.45, anchor: .trailing)
                .offset(x: isShowingWings ? 0 : (isFloating ? -8 : wingWidth * 0.78))
                .opacity(isShowingWings ? 1.0 : 0.0)

            if !isFloating {
                Spacer(minLength: cutoutWidth)
                    .frame(width: cutoutWidth)
            } else {
                Spacer(minLength: 0)
            }

            rightWingContent
                .id(activityContent?.kindIdentifier ?? "empty-right")
                .transition(.scale(scale: 0.70).combined(with: .opacity))
                .frame(width: isFloating ? 28 : wingWidth, height: barHeight, alignment: .center)
                .padding(.trailing, isFloating ? 10 : 0)
                .scaleEffect(isShowingWings ? 1.0 : 0.45, anchor: .leading)
                .offset(x: isShowingWings ? 0 : (isFloating ? 8 : -wingWidth * 0.78))
                .opacity(isShowingWings ? 1.0 : 0.0)
        }
    }

    @ViewBuilder
    private var leftWingContent: some View {
        if isShowingLockWings {
            Image(systemName: viewModel.isLockScreenUnlocking ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(viewModel.isLockScreenUnlocking ? .notchGreen : .white)
                .contentTransition(.symbolEffect(.replace))
        } else {
            switch activityContent {
            case .nowPlaying(let info):
                AlbumArtView(
                    image: info.artwork,
                    isPlaying: info.isPlaying,
                    size: 19,
                    cornerRadius: 5
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.mediaObserver.openActiveMediaApp(for: info)
                }

        case .download(let item):
            ZStack {
                Circle()
                    .fill(Color.notchBlue.opacity(0.20))
                    .frame(width: 20, height: 20)

                Image(systemName: DownloadProgressView.fileIcon(for: item.filename))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.notchBlue)
            }

        case .batteryCharging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.notchGreen)

        case .batteryFull:
            Image(systemName: "battery.100.bolt")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.notchGreen)

        case .bluetoothConnected(let name):
            ZStack {
                Circle()
                    .fill(Color.notchBlue.opacity(0.22))
                    .frame(width: 20, height: 20)

                BluetoothDeviceIconView(deviceName: name, fontSize: 11.5)
                    .foregroundColor(.notchBlue)
            }

        case .bluetoothDisconnected(let name):
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.22))
                    .frame(width: 20, height: 20)

                BluetoothDeviceIconView(deviceName: name, fontSize: 11.5)
                    .foregroundColor(.gray)
            }

        case .wifiConnected:
            Image(systemName: "wifi")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.notchGreen)

        case .wifiDisconnected:
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.notchRed)

        case .vpnConnected:
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.notchIndigo)

        case .focusChanged(let isActive):
            ZStack {
                Circle()
                    .fill((isActive ? Color.notchIndigo : Color.gray).opacity(0.22))
                    .frame(width: 20, height: 20)

                Image(systemName: isActive ? "moon.fill" : "moon")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(isActive ? .notchIndigo : .gray)
            }

        case .muted(let isMuted):
            let vol = viewModel.volumeObserver.volume
            let isEffectiveMuted = isMuted || vol <= 0.005
            Image(systemName: volumeIcon(for: vol, isMuted: isEffectiveMuted))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isEffectiveMuted ? .notchRed : .white)
                .contentTransition(.symbolEffect(.replace))

        case .volumeChange(let vol):
            let isEffectiveMuted = vol <= 0.005
            Image(systemName: volumeIcon(for: vol, isMuted: isEffectiveMuted))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isEffectiveMuted ? .notchRed : .white)
                .contentTransition(.symbolEffect(.replace))

        case .brightnessChange(let b):
            Image(systemName: brightnessIcon(for: b))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))

        case .keyboardBrightnessChange(let b):
            Image(systemName: b <= 0.01 ? "keyboard" : "keyboard.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))

        case .screenRecording:
            ScreenRecordingWingDot()

        case .timer(let item):
            let isUrgent = item.remaining <= 60.0
            let tintColor: Color = item.isExpired ? .notchRed : (isUrgent ? .notchRed : .notchOrange)
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.20))
                    .frame(width: 20, height: 20)

                Image(systemName: item.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(tintColor)
            }

        case .noInternet:
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Color(red: 0.98, green: 0.58, blue: 0.12))

        case .clipboard:
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))

        case .shelf:
            ZStack {
                Circle()
                    .fill(Color(red: 0.22, green: 0.62, blue: 1.0).opacity(0.20))
                    .frame(width: 20, height: 20)

                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color(red: 0.22, green: 0.62, blue: 1.0))
            }

        case .externalDrive(let drives):
            if let drive = drives.first {
                ZStack {
                    Circle()
                        .fill(drive.driveType.accentColor.opacity(0.20))
                        .frame(width: 20, height: 20)

                    Image(systemName: drive.driveType.iconName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(drive.driveType.accentColor)
                }
            }

        case .externalDriveEjected:
            ZStack {
                Circle()
                    .fill(Color.notchGreen.opacity(0.20))
                    .frame(width: 20, height: 20)

                Image(systemName: "eject.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.notchGreen)
            }

        case .calendarEvent(let event), .calendarAlert(let event):
            ZStack {
                Circle()
                    .fill((event.conferencePlatform?.accentColor ?? event.calendarColor).opacity(0.20))
                    .frame(width: 20, height: 20)

                Image(systemName: event.conferencePlatform?.iconName ?? "calendar")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(event.conferencePlatform?.accentColor ?? event.calendarColor)
            }

        case .hotspot, .hotspotLowBattery:
            Image(systemName: "personalhotspot")
                .font(.system(size: 13.0, weight: .semibold))
                .foregroundColor(.notchGreen)

        default:
            EmptyView()
        }
    }
}

    @ViewBuilder
    private var rightWingContent: some View {
        if isShowingLockWings {
            Text(viewModel.isLockScreenUnlocking
                ? (Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Açıldı" : "Unlocked")
                : (Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Kilitli" : "Locked"))
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(viewModel.isLockScreenUnlocking ? .notchGreen : .white.opacity(0.88))
                .lineLimit(1)
                .contentTransition(.numericText())
        } else {
            switch activityContent {
            case .nowPlaying(let info):
                AudioVisualizerView(
                    isPlaying: info.isPlaying,
                    tint: info.accentColor,
                    trackInfo: info,
                    isCompact: true
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.mediaObserver.openActiveMediaApp(for: info)
                }

        case .download(let item):
            if item.totalBytes > 0 {
                Text("%\(Int(round(item.progress * 100)))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.notchBlue)
                    .contentTransition(.numericText())
            } else {
                Text(DownloadObserver.formatCompactBytes(item.downloadedBytes))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.notchBlue)
                    .lineLimit(1)
            }

        case .batteryCharging:
            Text("%\(viewModel.batteryObserver.percentage)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(.notchGreen)

        case .batteryFull:
            Text("%100")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.notchGreen)

        case .bluetoothConnected(let name):
            if let battery = viewModel.bluetoothObserver.batteryPercentage(for: name) {
                CircularBatteryView(percentage: battery, size: 19, lineWidth: 2.0)
            } else {
                Text("Bağlı")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.notchBlue)
            }

        case .bluetoothDisconnected:
            Text("Kesildi")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.65))

        case .wifiConnected:
            Text(Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Bağlandı" : "Connected")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.notchGreen)
                .lineLimit(1)

        case .wifiDisconnected:
            Text(Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Kesildi" : "Disconnected")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.notchRed)
                .lineLimit(1)

        case .vpnConnected(_, let date):
            VPNUptimeView(connectedDate: date, isCompact: true)

        case .focusChanged(let isActive):
            Text(isActive ? "Açık" : "Kapalı")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(isActive ? .notchIndigo : .white.opacity(0.65))

        case .muted(let isMuted):
            let vol = viewModel.volumeObserver.volume
            let isEffectiveMuted = isMuted || vol <= 0.005
            Text(isEffectiveMuted ? (Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Sessiz" : "Mute") : "%\(Int(round(vol * 100)))")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(isEffectiveMuted ? .notchRed : .white.opacity(0.90))

        case .volumeChange(let vol):
            let isEffectiveMuted = vol <= 0.005
            Text(isEffectiveMuted ? (Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Sessiz" : "Mute") : "%\(Int(round(vol * 100)))")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(isEffectiveMuted ? .notchRed : .white.opacity(0.90))

        case .brightnessChange(let b):
            Text("%\(Int(round(b * 100)))")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.90))
                .contentTransition(.numericText())

        case .keyboardBrightnessChange(let b):
            Text("%\(Int(round(b * 100)))")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.90))
                .contentTransition(.numericText())

        case .screenRecording(let startDate):
            TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                let hours = Int(elapsed) / 3600
                let minutes = (Int(elapsed) % 3600) / 60
                let seconds = Int(elapsed) % 60
                let formatted = hours > 0
                    ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                    : String(format: "%02d:%02d", minutes, seconds)
                Text(formatted)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.notchRed)
                    .lineLimit(1)
                    .offset(y: 2.0)
            }

        case .timer(let item):
            let isUrgent = item.remaining <= 60.0
            let tintColor: Color = item.isExpired ? .notchRed : (isUrgent ? .notchRed : .notchOrange)
            TimelineView(.animation(minimumInterval: 0.25, paused: item.isPaused)) { context in
                let rem = item.isPaused
                    ? (item.remainingWhenPaused ?? item.remaining)
                    : max(0, item.endDate.timeIntervalSince(context.date))
                let hours = Int(rem) / 3600
                let minutes = (Int(rem) % 3600) / 60
                let seconds = Int(rem) % 60
                let formatted = hours >= 1
                    ? String(format: "%02d:%02d", hours, minutes)
                    : String(format: "%02d:%02d", minutes, seconds)
                Text(formatted)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(tintColor)
                    .lineLimit(1)
                    .opacity(item.isPaused ? 0.60 : 1.0)
                    .offset(y: 2.0)
            }

        case .noInternet:
            Text(Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Çevrimdışı" : "Offline")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.98, green: 0.58, blue: 0.12))

        case .clipboard(let items):
            Text("\(items.count)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))

        case .shelf:
            Text("\(ShelfManager.shared.items.count)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.22, green: 0.62, blue: 1.0))

        case .externalDrive(let drives):
            if let drive = drives.first {
                if drives.count > 1 {
                    Text("\(drives.count) Sürücü")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(drive.driveType.accentColor)
                } else {
                    Text(drive.availableCapacityFormatted)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(drive.driveType.accentColor)
                        .lineLimit(1)
                }
            }

        case .externalDriveEjected:
            Text("Çıkarıldı")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.notchGreen)

        case .calendarEvent(let event):
            Text(event.compactCountdownString)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(event.isHappeningNow ? .notchGreen : (event.conferencePlatform?.accentColor ?? event.calendarColor))
                .lineLimit(1)

        case .calendarAlert(let event):
            Text(event.compactCountdownString)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(event.conferencePlatform?.accentColor ?? event.calendarColor)
                .lineLimit(1)

        case .hotspot(let hotspot), .hotspotLowBattery(let hotspot):
            Text(hotspot.percentageFormatted)
                .font(.system(size: 12.0, weight: .bold, design: .rounded))
                .foregroundColor(hotspot.batteryColor)
                .lineLimit(1)

        default:
            EmptyView()
        }
    }
}

    private func volumeIcon(for volume: Float, isMuted: Bool) -> String {
        if isMuted || volume <= 0.005 { return "speaker.slash.fill" }
        if volume < 0.33              { return "speaker.wave.1.fill" }
        if volume < 0.66              { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func brightnessIcon(for brightness: Float) -> String {
        if brightness <= 0.01 {
            return "sun.min"
        } else if brightness < 0.50 {
            return "sun.min.fill"
        } else {
            return "sun.max.fill"
        }
    }
}
