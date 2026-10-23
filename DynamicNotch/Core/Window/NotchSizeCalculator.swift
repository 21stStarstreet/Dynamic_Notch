// NotchSizeCalculator.swift
// DynamicNotch / Core / Window
//
// Runtime dynamic sizing engine for the expanded notch window.
//
// Horizontal Budget
// ─────────────────
// In Expanded mode, `NotchShape` has outward top ears of `expandedTopEarRadius = 14pt`
// on each side, and `NotchContainerView` adds `18pt` inner margin inside each
// vertical wall (`14 + 18 = 32pt` per side, `64pt` total horizontal padding).
// Every content type's intrinsic width is summed with `horizontalPadding (64pt)`
// and clamped to `[minExpandedWidth, screen.width × 0.60]`.

import AppKit

@MainActor
struct NotchSizeCalculator {

    // MARK: - Layout Constants

    /// Horizontal padding for rich LiveActivity cards:
    /// 28pt left (14pt ear + 14pt inner margin) + 28pt right = 56pt total.
    static let liveActivityHorizontalPadding: CGFloat = 56.0

    /// Horizontal padding for compact system alerts & HUDs:
    /// 26pt left (12pt ear + 14pt inner margin) + 26pt right = 52pt total.
    static let alertHorizontalPadding: CGFloat = 52.0

    /// Dimensions for the 2-finger swipe Quick Action Menu capsule (dynamically computed)
    static var quickActionMenuWidth: CGFloat {
        QuickActionMenuGeometryEngine.calculate().totalBodyWidth
    }
    static var quickActionMenuBodyHeight: CGFloat {
        QuickActionMenuGeometryEngine.calculate().totalBodyHeight
    }

    static let maxScreenFraction: CGFloat = 0.60

    private static let titleFont    = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let mediumFont   = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    private static let subtitleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let badgeFont    = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)

    // MARK: - Public API

    static func dynamicSize(
        for content: NotchState.ContentType,
        screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    ) -> CGSize {
        let isFloating      = NotchPositionCalculator.isFloatingCapsule(for: screen)
        let baseNotchWidth  = NotchPositionCalculator.notchBaseWidth(for: screen)
        let compactWidth    = NotchPositionCalculator.compactFrame(for: screen).width
        let maxWidth        = screen.frame.width * maxScreenFraction
        let topCutoutHeight = isFloating ? 14.0 : NotchPositionCalculator.effectiveNotchHeight(for: screen)

        let (rawWidth, bodyHeight) = intrinsicSize(for: content)
        let totalHeight = bodyHeight + topCutoutHeight

        if content.prefersCompactPresentation && !VolumeHUDViewModel.shared.isAudioRouteExpanded {
            // Keep the exact horizontal width of the compact state when expanding on hover!
            return CGSize(width: ceil(compactWidth), height: ceil(totalHeight))
        }

        let hPadding: CGFloat
        let minWidth: CGFloat

        if case .clipboard = content {
            hPadding = 54.0
            minWidth = max(baseNotchWidth + 50.0, 260.0)
        } else if case .shelf = content {
            hPadding = 48.0
            minWidth = max(baseNotchWidth + 60.0, 360.0)
        } else if case .externalDrive = content {
            hPadding = 48.0
            minWidth = max(baseNotchWidth + 60.0, 370.0)
        } else if case .calendarEvent = content {
            hPadding = 48.0
            minWidth = max(baseNotchWidth + 60.0, 360.0)
        } else if case .calendarAlert = content {
            hPadding = 52.0
            minWidth = max(baseNotchWidth + 50.0, 330.0)
        } else if case .hotspot = content {
            hPadding = 48.0
            minWidth = max(baseNotchWidth + 60.0, 360.0)
        } else if case .hotspotLowBattery = content {
            hPadding = 52.0
            minWidth = max(baseNotchWidth + 50.0, 330.0)
        } else if case .noInternet = content {
            hPadding = 54.0
            minWidth = max(baseNotchWidth + 50.0, 320.0)
        } else if case .quickNote = content {
            hPadding = 48.0
            minWidth = max(baseNotchWidth + 60.0, 380.0)
        } else if case .quickNoteSaved = content {
            hPadding = 52.0
            minWidth = max(baseNotchWidth + 50.0, 300.0)
        } else if case .quickReminder = content {
            hPadding = 48.0
            minWidth = max(baseNotchWidth + 60.0, 380.0)
        } else if case .quickReminderSaved = content {
            hPadding = 52.0
            minWidth = max(baseNotchWidth + 50.0, 300.0)
        } else if case .accessibilityPermissionRequired = content {
            hPadding = 0.0
            minWidth = max(baseNotchWidth + 40.0, 276.0)
        } else if case .spotifyAuthorized = content {
            hPadding = 24.0
            minWidth = max(baseNotchWidth + 24.0, 220.0)
        } else if case .timerSetup = content {
            hPadding = 52.0
            minWidth = max(baseNotchWidth + 50.0, 348.0)
        } else if case .timer = content {
            hPadding = 52.0
            minWidth = max(baseNotchWidth + 50.0, 348.0)
        } else if case .screenshot = content {
            hPadding = 120.0
            minWidth = max(baseNotchWidth + 140.0, 364.0)
        } else if case .onboarding = content {
            hPadding = 0.0
            minWidth = max(baseNotchWidth + 80.0, 340.0)
        } else if case .bluetoothConnected(let name) = content, AirPodsModel(deviceName: name).supportsFullAnimation {
            hPadding = 64.0
            minWidth = max(baseNotchWidth + 110.0, 340.0)
        } else if content.isLiveActivity {
            hPadding = liveActivityHorizontalPadding
            minWidth = max(compactWidth + 44.0, 348.0)
        } else if case .emptySquareMenu = content {
            let metrics = QuickActionMenuGeometryEngine.calculate(screen: screen)
            hPadding = 0.0
            minWidth = metrics.totalBodyWidth
            let menuHeight = isFloating ? metrics.floatingBodyHeight : (metrics.totalBodyHeight + topCutoutHeight)
            let clampedWidth = min(maxWidth, max(minWidth, rawWidth + hPadding))
            return CGSize(width: ceil(clampedWidth), height: ceil(menuHeight))
        } else if case .cameraMirror = content {
            hPadding = 0.0
            minWidth = 280.0
        } else {
            hPadding = alertHorizontalPadding
            minWidth = max(baseNotchWidth + 64.0, 248.0)
        }

        let clampedWidth = min(maxWidth, max(minWidth, rawWidth + hPadding))

        return CGSize(width: ceil(clampedWidth), height: ceil(totalHeight))
    }

    /// Expanded size when the user hovers over the notch while no active alert/media is playing.
    static func standbyExpandedSize(
        screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    ) -> CGSize {
        let isFloating      = NotchPositionCalculator.isFloatingCapsule(for: screen)
        let compactWidth    = NotchPositionCalculator.idleFrame(for: screen).width
        let topCutoutHeight = isFloating ? 14.0 : NotchPositionCalculator.effectiveNotchHeight(for: screen)
        let targetWidth     = max(compactWidth + 60.0, 356.0)
        return CGSize(
            width: ceil(targetWidth),
            height: ceil(66.0 + topCutoutHeight)
        )
    }

    // MARK: - Per-Content Proportional Layout

    /// Returns `(rawContentWidth, bodyHeightBelowCutout)` before horizontal padding and clamping.
    /// Every `bodyHeightBelowCutout` is strictly derived from:
    ///   `topClearance + elementHeight + bottomConcentricMargin`
    private static func intrinsicSize(
        for content: NotchState.ContentType
    ) -> (CGFloat, CGFloat) {

        switch content {

        // ── Now Playing (48×48 Album Art + 3-line Track Stack + Transport Controls) ──
        // Height: 7pt top + 51pt content + 12pt bottom = 70pt below cutout.
        // When Lyrics are expanded: 70pt base + 8pt spacing + 112pt lyrics drawer + 10pt bottom = 200pt below cutout.
        case .nowPlaying(let info):
            let titleW    = measureText(info.title,  font: titleFont) + 26
            let artistW   = measureText(info.artist, font: subtitleFont)
            let textBlock = min(max(titleW, artistW, 148), 215)
            let baseRaw   = 48 + 12 + textBlock + 12 + 138

            if NowPlayingViewModel.shared.isLyricsExpanded {
                return (baseRaw, 200)
            } else if NowPlayingViewModel.shared.isAudioRouteExpanded {
                let deviceCount = max(1, AudioDeviceManager.shared.outputDevices.count)
                let drawerHeight = min(CGFloat(deviceCount) * 38.0 + 48.0, 190.0)
                return (baseRaw, 70 + drawerHeight)
            } else {
                return (baseRaw, 70)
            }

        // ── Download (Phase 2 Faz 4: 34×34 Badge + 2-Row Name/Folder & Speed/Progress Stack) ──
        // Height: 7pt top + 42pt content + 11pt bottom = 60pt below cutout.
        case .download(let item):
            let nameW     = min(max(measureText(item.filename, font: mediumFont), 130), 210)
            let subtitleStr = item.totalBytes > 0
                ? "\(item.sourceFolderName) • 999.9 MB / 999.9 MB"
                : "\(item.sourceFolderName) • 999.9 MB"
            let subtitleW = min(measureText(subtitleStr, font: subtitleFont), 200)
            let leadingW  = max(nameW, subtitleW)
            let speedW    = measureText("128.5 MB/s", font: badgeFont)
            let percentW  = measureText("%100", font: badgeFont)
            let trailingW = max(speedW, percentW)
            let raw       = 34 + 11 + leadingW + 16 + trailingW
            return (raw, 60)

        // ── Battery (Phase 2 Faz 1: Distinct Charging, Low+Toggle, Full+Badge Layouts) ──
        // Charging: 260pt total width (208 raw + 52 hPadding), 42pt body height.
        // Battery Low: 320pt total width (268 raw + 52 hPadding), 62pt body height (2-line + toggle).
        // Full Battery: 280pt total width (228 raw + 52 hPadding), 52pt body height (2-line + badge).
        case .batteryCharging:
            return (208, 42)

        case .batteryLow:
            return (268, 62)

        case .batteryFull:
            return (228, 52)

        // ── Bluetooth (Phase 2 Faz 3: 34×34 Badge + Status/Device Stack + 32×32 CircularBatteryView) ──
        // Height: 9pt top + 34pt badge + 9pt bottom = 52pt below cutout.
        case .bluetoothConnected(let name):
            let model = AirPodsModel(deviceName: name)
            if model.supportsFullAnimation {
                return (264, 218)
            } else {
                let actionLabel = "Bağlandı"
                let nameW   = min(measureText(name, font: titleFont), 190)
                let actionW = measureText(actionLabel, font: subtitleFont)
                let raw     = 34 + 12 + max(nameW, actionW) + 12 + 32
                return (raw, 52)
            }

        case .bluetoothDisconnected(let name):
            let actionLabel = "Bağlantı Kesildi"
            let nameW   = min(measureText(name, font: titleFont), 190)
            let actionW = measureText(actionLabel, font: subtitleFont)
            let raw     = 34 + 12 + max(nameW, actionW) + 12 + 32
            return (raw, 52)

        // ── Wi-Fi (Phase 2 Faz 5: 34×34 Badge + 2-Row Status/SSID Stack + Indicator Dot) ──
        // Height: 9pt top + 34pt badge + 9pt bottom = 52pt below cutout.
        case .wifiConnected(let ssid):
            let headerText = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "WiFi ağına bağlanıldı" : "Connected to Wi-Fi"
            let headerW = measureText(headerText, font: subtitleFont)
            let ssidW   = min(measureText(ssid.isEmpty ? "Wi-Fi Ağı" : ssid, font: titleFont), 220)
            let textW   = max(headerW, ssidW)
            let raw     = 34 + 12 + textW + 12 + 8
            return (raw, 52)

        case .wifiDisconnected:
            let headerW = measureText("Bağlantı Kesildi", font: subtitleFont)
            let subW    = measureText("Wi-Fi Kapalı", font: titleFont)
            let textW   = max(headerW, subW)
            let raw     = 34 + 12 + textW + 12 + 8
            return (raw, 52)

        // ── VPN (Phase 2 Faz 5: 34×34 Badge + 2-Row Status/Tunnel + Live Uptime Pill) ──
        // Height: 9pt top + 34pt badge + 9pt bottom = 52pt below cutout.
        case .vpnConnected(let tunnelName, _):
            let headerW = measureText("VPN Bağlandı", font: subtitleFont)
            let nameW   = min(measureText(tunnelName.isEmpty ? "Güvenli Tünel" : tunnelName, font: titleFont), 190)
            let textW   = max(headerW, nameW)
            let raw     = 34 + 12 + textW + 12 + 66
            return (raw, 52)

        // ── Focus / Do Not Disturb (34×34 Badge + Title/Subtitle) ───────────────────
        // Height: 5pt top + 34pt badge + 6pt bottom = 45pt below cutout.
        case .focusChanged(let isActive):
            let titleW = measureText("Rahatsız Etmeyin", font: mediumFont)
            let subW   = measureText(isActive ? "Odak modu etkin" : "Odak modu kapatıldı", font: subtitleFont)
            let raw    = 34 + 12 + max(titleW, subW) + 10
            return (raw, 45)

        // ── Audio Mute / Unmute (Interactive VolumeHUDView) ─────────────────────────
        // Height: 52pt below cutout (matches .volumeChange).
        case .muted(let isMuted):
            if VolumeHUDViewModel.shared.isAudioRouteExpanded {
                let deviceCount = max(2, AudioDeviceManager.shared.outputDevices.count)
                let rightPaneHeight = CGFloat(deviceCount) * 36.0 + 34.0
                let routeBodyHeight = min(max(108.0, rightPaneHeight) + 22.0, 180.0)
                return (510, routeBodyHeight)
            }
            let titleW = measureText(isMuted ? "Sessize Alındı" : "Ses Açıldı", font: mediumFont)
            let subW   = measureText(isMuted ? "Sistem sesi kapatıldı" : "Sistem sesi etkin", font: subtitleFont)
            let raw    = 34 + 12 + max(titleW, subW) + 10
            return (raw, 68)

        // ── Volume HUD (Phase 2 Faz 2: Output Device Header + Icon/Progress/Level) ──
        // Height: 68pt below cutout (2-row layout). Width dynamically adapts to device name.
        case .volumeChange(let vol):
            if VolumeHUDViewModel.shared.isAudioRouteExpanded {
                let deviceCount = max(2, AudioDeviceManager.shared.outputDevices.count)
                let rightPaneHeight = CGFloat(deviceCount) * 36.0 + 34.0
                let routeBodyHeight = min(max(108.0, rightPaneHeight) + 22.0, 180.0)
                return (510, routeBodyHeight)
            }
            let deviceFont   = NSFont.systemFont(ofSize: 12, weight: .medium)
            let deviceName   = VolumeObserver.currentOutputDeviceName
            let headerWidth: CGFloat
            if vol <= 0.005 {
                let mutedW = measureText("Sessize Alındı", font: deviceFont)
                let subW   = measureText(deviceName, font: subtitleFont)
                headerWidth = min(mutedW + 10 + subW, 250)
            } else {
                headerWidth = min(measureText(deviceName, font: deviceFont), 250)
            }
            let bottomRowW: CGFloat = 22 + 10 + 140 + 10 + 28 // 210pt
            let raw = max(headerWidth + 28, bottomRowW)
            return (raw, 68)

        // ── Brightness HUD (Apple-grade screen header + icon/progress/level) ────────
        // Height: 52pt below cutout (2-row layout). Width dynamically adapts to screen name.
        case .brightnessChange:
            let screenFont = NSFont.systemFont(ofSize: 12, weight: .medium)
            let rawName = NSScreen.main?.localizedName ?? "Ekran Parlaklığı"
            let screenName: String = {
                if rawName.isEmpty || rawName.lowercased().contains("built-in") {
                    return Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Ekran Parlaklığı" : "Display Brightness"
                }
                return rawName
            }()
            let headerWidth = min(measureText(screenName, font: screenFont), 250)
            let bottomRowW: CGFloat = 22 + 10 + 140 + 10 + 28 // 210pt
            let raw = max(headerWidth, bottomRowW)
            return (raw, 52)

        // ── Keyboard Brightness HUD (Apple-grade keyboard header + icon/progress/level) ──
        // Height: 52pt below cutout (2-row layout). Width adapts to localized header.
        case .keyboardBrightnessChange:
            let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
            let isTurkish = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
            let title = isTurkish ? "Klavye Aydınlatması" : "Keyboard Brightness"
            let headerWidth = min(measureText(title, font: titleFont), 250)
            let bottomRowW: CGFloat = 22 + 10 + 140 + 10 + 28 // 210pt
            let raw = max(headerWidth, bottomRowW)
            return (raw, 52)

        // ── Screen Recording Live Activity ──────────────────────────────────────────
        // Height: 48pt below cutout.
        case .screenRecording:
            return (280, 48)

        // ── Timer Live Activity ─────────────────────────────────────────────────────
        // Height: 80pt below cutout (12pt top margin + 56pt content + 12pt bottom margin).
        // 42x42pt tactile buttons, snug proportional side margins (26pt) and balanced middle gap.
        case .timer:
            // Fixed raw width 296pt (+ 52pt hPadding = 348pt fixed notch width)
            // Shrunk from the bottom: 64pt body height below cutout, preserving element position
            return (296, 64)

        // ── No Internet Connection System Alert ─────────────────────────────────────
        // Height: 72pt below cutout. Symmetrical 3-column layout with stacked action buttons on right.
        // Proportional margins: 15pt wall side distance, 15pt bottom margin, 7pt top clearance.
        // Body height = 7pt top + 50pt content + 15pt bottom = 72pt.
        case .noInternet:
            return (320, 72)

        // ── Quick Note Composer ───────────────────────────────────────────────────
        // Height: 148pt below cutout (7pt top margin + 126pt content + 14pt concentric bottom margin).
        // Perfectly proportional, eliminating bottom excess while keeping smooth 20pt corner radius.
        case .quickNote:
            return (352, 148)

        // ── Quick Note Saved HUD ──────────────────────────────────────────────────
        // Height: 52pt below cutout (standard system HUD).
        case .quickNoteSaved(let title):
            let titleW = measureText(title.isEmpty ? "Yeni Not" : title, font: titleFont)
            let raw = max(260.0, min(titleW + 120.0, 360.0))
            return (raw, 52)

        // ── Quick Reminder Composer ───────────────────────────────────────────────
        // Height: 132pt below cutout (7pt top margin + 112pt content + 13pt concentric bottom margin).
        // Perfectly proportional, eliminating bottom excess while keeping smooth 20pt corner radius.
        case .quickReminder:
            return (368, 132)

        // ── Quick Reminder Saved HUD ──────────────────────────────────────────────
        // Height: 52pt below cutout (standard system HUD).
        case .quickReminderSaved(let title):
            let titleW = measureText(title.isEmpty ? "Yeni Anımsatıcı" : title, font: titleFont)
            let raw = max(260.0, min(titleW + 120.0, 360.0))
            return (raw, 52)

        // ── Accessibility Permission Action Card ─────────────────────────────────
        // Height: 180pt below cutout. Symmetrical squarish Apple card (~1.25:1 aspect ratio)
        // with concentric 26pt corners and snug, balanced 16pt bottom margin.
        case .accessibilityPermissionRequired:
            return (276, 180)

        // ── Spotify Authorized Success Checkmark HUD ──────────────────────────────
        // Height: 86pt below cutout. Symmetrical Apple-grade animated vector checkmark HUD,
        // perfectly centered with proportional 24pt vertical margins concentric with bottom curvature.
        case .spotifyAuthorized:
            return (220, 86)

        // ── Quick Action Menu (2-Finger Swipe Gesture) ───────────────────────────
        // Dimensions dynamically derived via QuickActionMenuGeometryEngine based on
        // item count, icon size, corner curvature, and safe tangent margins.
        case .emptySquareMenu:
            let targetScreen = ScreenHelper.targetScreen
            let metrics = QuickActionMenuGeometryEngine.calculate(screen: targetScreen)
            let bodyH = NotchPositionCalculator.isFloatingCapsule(for: targetScreen) ? metrics.floatingBodyHeight : metrics.totalBodyHeight
            return (metrics.totalBodyWidth, bodyH)

        // ── Camera Mirror Modal (Live Face / Hair Video Check) ─────────────────────
        // Height: 184pt below cutout. 280pt width.
        case .cameraMirror:
            return (280, 184)

        // ── Timer Setup Modal ──────────────────────────────────────────────────────
        // Height: 72pt below cutout (9pt top margin + 54pt content + 9pt bottom margin).
        // Symmetrical Apple Dynamic Notch Timer interface, identical in height and width to Timer Live Activity.
        case .timerSetup:
            return (296, 72)

        // ── Clipboard History Manager ──────────────────────────────────────────────
        // Height: 112pt below cutout. Symmetrical, balanced Apple Liquid Glass card layout.
        // Proportional margins: 18pt sides, 15pt bottom, 7pt top clearance below cutout.
        // Body height = 7pt top + 22pt header + 8pt gap + 60pt card + 15pt bottom = 112pt.
        case .clipboard(let items):
            let count = items.count
            let rawWidth: CGFloat
            if count <= 0 {
                rawWidth = 240
            } else if count == 1 {
                rawWidth = 264
            } else if count == 2 {
                rawWidth = 336
            } else if count == 3 {
                rawWidth = 422
            } else {
                rawWidth = 440
            }
            return (rawWidth, 112)

        // ── Screenshot Capture Alert (AirPods-style Vertical Layout) ──────────────
        // Height: ~238pt below cutout (header + 114pt hero stage + circular action dock + proportional bottom margin)
        // Width: 244pt raw width (AirPods-grade balanced proportion)
        case .screenshot:
            return (244, 238)

        // ── Temporary File Shelf / Tray (Phase 3 Drag & Drop) ──────────────────────
        // Height: 106pt below cutout when empty (providing concentric 16pt+ bottom margin),
        //         138pt below cutout when populated with item cards.
        case .shelf:
            let itemCount = ShelfManager.shared.items.count
            if itemCount == 0 {
                return (356, 106)
            } else if itemCount == 1 {
                return (356, 138)
            } else if itemCount == 2 {
                return (380, 138)
            } else {
                return (410, 138)
            }

        // ── External Drive (USB / SSD / SD / DMG Live Activity & Card) ──────────────
        // Height: Header + rows + bottom margin. Single drive = 86pt, dual = 144pt.
        case .externalDrive(let drives):
            let count = max(1, drives.count)
            let rowHeight: CGFloat = 56.0
            let headerHeight: CGFloat = 22.0
            let bodyHeight = min(CGFloat(count) * rowHeight + headerHeight + 22.0, 240.0)
            let rawWidth: CGFloat = count > 1 ? 380.0 : 360.0
            return (rawWidth, bodyHeight)

        // ── External Drive Ejected Alert ───────────────────────────────────────────
        case .externalDriveEjected(let name, _):
            let titleW = measureText("Güvenle Çıkarıldı", font: mediumFont)
            let subW   = measureText("\(name) artık çıkarılabilir", font: subtitleFont)
            let raw    = 34 + 12 + max(titleW, subW) + 12 + 24
            return (raw, 52)

        // ── Calendar Event (Live Activity Card) ────────────────────────────────────
        case .calendarEvent(let event):
            let hasNext = CalendarManager.shared.todayEvents.contains { $0.id != event.id && $0.startDate > event.startDate }
            let bodyHeight: CGFloat = hasNext ? 146.0 : 122.0
            let titleW = measureText(event.title, font: titleFont)
            let rawWidth = max(340.0, min(titleW + 90.0, 420.0))
            return (rawWidth, bodyHeight)

        // ── Calendar Event Alert (Transient HUD) ───────────────────────────────────
        case .calendarAlert(let event):
            let titleW = measureText(event.title, font: titleFont)
            let raw = max(310.0, min(titleW + 150.0, 390.0))
            return (raw, 56)

        // ── Personal Hotspot Live Activity Card ────────────────────────────────────
        case .hotspot(let hotspot):
            let nameW = measureText(hotspot.deviceName, font: mediumFont)
            let rawWidth = max(360.0, min(nameW + 170.0, 430.0))
            return (rawWidth, 142)

        // ── Personal Hotspot Low Battery Alert (Transient HUD) ────────────────────
        case .hotspotLowBattery(let hotspot):
            let nameW = measureText(hotspot.deviceName, font: mediumFont)
            let raw = max(320.0, min(nameW + 150.0, 400.0))
            return (raw, 56)

        // ── Onboarding Presentation (First Launch & Welcome Experience) ──────────
        case .onboarding(let step):
            let isNotchless = !NotchDetector.hasPhysicalNotch(on: NSScreen.main ?? NSScreen.screens[0])
            let size = step.dynamicSize(baseWidth: 160, isNotchless: isNotchless)
            return (size.width, size.height)

        case .welcomeGreeting:
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let isNotchless = !NotchDetector.hasPhysicalNotch(on: screen)
            let baseWidth = isNotchless ? 140.0 : NotchPositionCalculator.notchBaseWidth(for: screen)
            let topCutout = NotchPositionCalculator.effectiveNotchHeight(for: screen)
            let w = max(baseWidth + 80, 260)
            return (w, topCutout + 64)
        }
    }

    // MARK: - Text Measurement Helper

    static func measureText(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }
}

// MARK: - Quick Action Menu Geometry & Spacing Engine (Apple HIG Dynamic Bounds)

@MainActor
struct QuickActionMenuMetrics {
    let itemCount: Int
    let pageCount: Int
    let iconSize: CGFloat
    let itemWidth: CGFloat
    let itemContentHeight: CGFloat
    let itemSpacing: CGFloat
    let horizontalPadding: CGFloat
    let topClearanceBelowCutout: CGFloat
    let floatingTopPadding: CGFloat
    let bottomPadding: CGFloat
    let pageContentWidth: CGFloat
    let totalBodyWidth: CGFloat
    let totalBodyHeight: CGFloat
    let floatingBodyHeight: CGFloat
}

@MainActor
struct QuickActionMenuGeometryEngine {

    /// Standard Apple Control Center squircle icon dimension (46 × 46 pt)
    static let standardIconSize: CGFloat = 46.0

    /// Computes full dynamic geometry, margins, and proportional spacing.
    /// - Parameters:
    ///   - screen: Current NSScreen displaying the notch (defaults to ScreenHelper.targetScreen).
    ///   - itemCount: Number of action items per page (default: 5).
    ///   - pageCount: Number of carousel pages (default: 2).
    /// - Returns: Complete `QuickActionMenuMetrics` value with all derived bounds.
    static func calculate(
        screen: NSScreen = ScreenHelper.targetScreen,
        itemCount: Int = 5,
        pageCount: Int = 2
    ) -> QuickActionMenuMetrics {
        let isFloating = NotchPositionCalculator.isFloatingCapsule(for: screen)
        let baseNotchWidth = NotchPositionCalculator.notchBaseWidth(for: screen)

        // 1. Dynamic Text Measurement across all Quick Action labels
        let labels = [
            "Hızlı Not", "Anımsatıcı", "Pano", "Zamanlayıcı", "Ses Çıkışı",
            "Alıntı & OCR", "Ayna", "Odak Modu", "Disk Çıkar", "Takvim"
        ]
        let labelFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let maxLabelW = labels.map { NotchSizeCalculator.measureText($0, font: labelFont) }.max() ?? 60.0

        // 2. Item Metrics (Icon 46pt, Gap 6pt, Label 14pt)
        let iconSize: CGFloat = standardIconSize
        let iconToLabelGap: CGFloat = 6.0
        let labelHeight: CGFloat = 14.0
        let itemContentHeight: CGFloat = iconSize + iconToLabelGap + labelHeight // 66.0 pt

        // Item slot width: must comfortably fit the widest label ("Zamanlayıcı" ~62pt)
        // with generous breathing room (minimum 66.0 pt)
        let itemWidth: CGFloat = max(standardIconSize + 18.0, ceil(maxLabelW + 6.0)) // ~66.0 pt

        // 3. Tangent Safe Curvature Bounds (Corner Radius: 24pt)
        let cornerRadius: CGFloat = 24.0
        // Generous side border margin ensures outer icons never collide with curved corners:
        let minHorizontalMargin: CGFloat = max(cornerRadius * 1.05, 26.0) // 26.0 pt

        // Base inter-item spacing (comfortable, spacious rhythm)
        let count = max(1, itemCount)
        let baseSpacing: CGFloat = 12.0

        // 4. Content Width & Target Total Width
        let rawContentWidth = (CGFloat(count) * itemWidth) + (CGFloat(max(0, count - 1)) * baseSpacing)
        let rawTotalWidth = rawContentWidth + (minHorizontalMargin * 2.0)

        // Minimum width constrained by hardware cutout + safety ears
        let minAllowedWidth = max(baseNotchWidth + 60.0, 380.0)
        let maxAllowedWidth = screen.frame.width * NotchSizeCalculator.maxScreenFraction

        let targetWidth = min(maxAllowedWidth, max(minAllowedWidth, rawTotalWidth))

        // Proportional Spacing Distribution (if wider than baseline)
        let extraDelta = max(0.0, targetWidth - rawTotalWidth)
        let horizontalPadding: CGFloat
        let itemSpacing: CGFloat

        if extraDelta > 0 && count > 1 {
            horizontalPadding = minHorizontalMargin + (extraDelta * 0.35 / 2.0)
            let remainingSpaceForGaps = extraDelta * 0.65
            itemSpacing = baseSpacing + (remainingSpaceForGaps / CGFloat(count - 1))
        } else {
            horizontalPadding = minHorizontalMargin
            itemSpacing = baseSpacing
        }

        let pageContentWidth = (CGFloat(count) * itemWidth) + (CGFloat(max(0, count - 1)) * itemSpacing)

        // 5. Vertical Rhythm & Clearances
        // Clearance below hardware cutout (when attached to physical notch):
        let topClearanceBelowCutout: CGFloat = 14.0

        // Top clearance when floating:
        let floatingTopPadding: CGFloat = 16.0

        // Bottom clearance concentric with 24pt squircle curvature:
        let bottomPadding: CGFloat = 14.0

        // Pagination section allocation
        let hasPagination = pageCount > 1
        let paginationSectionHeight: CGFloat = hasPagination ? 15.0 : 0.0 // 10.0 gap + 5.0 dots

        // Total body height below cutout (for physical notch)
        let totalBodyHeight = topClearanceBelowCutout + itemContentHeight + paginationSectionHeight + bottomPadding // 14 + 66 + 15 + 14 = 109.0 pt

        // Floating body height (for floating capsule)
        let floatingBodyHeight = floatingTopPadding + itemContentHeight + paginationSectionHeight + bottomPadding // 16 + 66 + 15 + 14 = 111.0 pt

        return QuickActionMenuMetrics(
            itemCount: count,
            pageCount: pageCount,
            iconSize: iconSize,
            itemWidth: ceil(itemWidth),
            itemContentHeight: ceil(itemContentHeight),
            itemSpacing: ceil(itemSpacing * 10.0) / 10.0,
            horizontalPadding: ceil(horizontalPadding * 10.0) / 10.0,
            topClearanceBelowCutout: ceil(topClearanceBelowCutout),
            floatingTopPadding: ceil(floatingTopPadding),
            bottomPadding: ceil(bottomPadding),
            pageContentWidth: ceil(pageContentWidth),
            totalBodyWidth: ceil(targetWidth),
            totalBodyHeight: ceil(totalBodyHeight),
            floatingBodyHeight: ceil(floatingBodyHeight)
        )
    }
}
