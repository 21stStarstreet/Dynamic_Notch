// NotchViewModel.swift
// DynamicNotch / Core / Notch
//
// Central coordinator for all system observers, hover-to-expand interaction,
// and the Priority Queue engine.
//
// 3-State Visibility Rules
// ────────────────────────
// 1. Nothing Active (`activeLiveActivity == nil && currentAlert == nil`):
//    • `hasActiveContent = false`, `isExpanded = false`
//    • Completely invisible behind the physical notch (`hiddenFrame`); zero side
//      icons, zero hover reaction.
//
// 2. LiveActivity Active & Not Hovered (`activeLiveActivity != nil && !isHovered`):
//    • `hasActiveContent = true`, `isExpanded = false`
//    • Compact mode (`compactFrame`): small icons appear on the left and right
//      sides of the physical notch.
//    • Moving the mouse onto the notch expands it (`isExpanded = true`) to show
//      full controls; moving the mouse away collapses it back to compact wings.
//
// 3. Transient Alert Active (`currentAlert != nil`):
//    • `hasActiveContent = true`, `isExpanded = true`
//    • Expands for `defaultDuration` seconds, then returns to Compact mode (if a
//      LiveActivity is active) or hides completely (if nothing is active).

import SwiftUI
import Combine
import AppKit

@MainActor
final class NotchViewModel: ObservableObject {

    static private(set) weak var shared: NotchViewModel?

    // MARK: - Published State

    @Published private(set) var state:            NotchState = .idle
    @Published private(set) var isNotchVisible:   Bool       = false
    @Published private(set) var hasActiveContent: Bool       = false
    @Published private(set) var isExpanded:       Bool       = false
    @Published private(set) var isHovered:        Bool       = false
    @Published private(set) var isScreenLocked:   Bool       = false
    @Published private(set) var isLockScreenUnlocking: Bool  = false
    @Published private(set) var pillSize:         CGSize     = {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return NotchPositionCalculator.hiddenFrame(for: screen).size
    }()
    @Published private(set) var expandedContentSize: CGSize  = {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return NotchPositionCalculator.compactFrame(for: screen).size
    }()

    /// Retains the active or outgoing expanded card content during collapse animations
    /// so SwiftUI never tears down the view on frame 0 of a dismissal.
    @Published private(set) var displayedContent: NotchState.ContentType?

    /// Retains the active or outgoing compact wing LiveActivity or Compact Alert during
    /// retraction into the physical notch so side icons smoothly scale and slide inward.
    @Published private(set) var displayedCompactActivity: NotchState.ContentType?

    /// True while an existing compact wing item is smoothly retracting into the physical notch
    /// before a new compact item's wings emerge.
    @Published private(set) var isCompactWingsSwappingOut: Bool = false

    @Published private(set) var activeNowPlaying:     NotchState.ContentType?
    @Published private(set) var activeDownload:       NotchState.ContentType?
    @Published private(set) var activeTimerActivity:  NotchState.ContentType?
    @Published private(set) var activeExternalDriveActivity: NotchState.ContentType?
    @Published private(set) var activeCalendarActivity: NotchState.ContentType?
    @Published private(set) var activeHotspotActivity: NotchState.ContentType?
    @Published private(set) var activeScreenRecordingActivity: NotchState.ContentType?

    // MARK: - System Observers

    let mediaObserver           = MediaObserver()
    let batteryObserver         = BatteryObserver()
    let bluetoothObserver       = BluetoothObserver()
    let networkObserver         = NetworkObserver()
    let downloadObserver        = DownloadObserver()
    let volumeObserver          = VolumeObserver()
    let focusObserver           = FocusObserver()
    let screenRecordingObserver = ScreenRecordingObserver()
    let timerObserver           = TimerObserver()
    let clipboardObserver       = ClipboardObserver()
    let lockScreenObserver      = LockScreenObserver()
    let brightnessObserver      = BrightnessObserver()
    let keyboardBrightnessObserver = KeyboardBrightnessObserver()
    let screenshotObserver      = ScreenshotObserver()

    // MARK: - Window Controller (weak to break retain cycle)

    weak var windowController: NotchWindowController?
    var onOpenSettings: (() -> Void)?

    // MARK: - Priority Queue State

    /// Toggled when the user drags the satellite orb towards the center to swap primary & secondary activities
    @Published var isLiveActivitySwapped: Bool = false

    // MARK: - Satellite Orb State (Concurrent HUDs & Live Activities)

    /// Ephemeral alert actively displayed in the Left Satellite Orb during an overlap collision
    @Published private(set) var leftSatelliteAlert: NotchState.ContentType? = nil
    private var leftSatelliteDismissTimer: AnyCancellable? = nil

    /// Ephemeral alert actively displayed in the Right Satellite Orb
    @Published private(set) var rightSatelliteAlert: NotchState.ContentType? = nil
    private var rightSatelliteDismissTimer: AnyCancellable? = nil

    /// True when either the full multi-step onboarding or the 1-round welcome launch greeting is active.
    var isShowingOnboardingOrGreeting: Bool {
        activeOnboardingStep != nil || currentAlert == .welcomeGreeting || NotchOnboardingManager.shared.isGreetingOrOnboardingActive
    }

    /// Left Satellite Content:
    /// 1. Ephemeral collision alert (HUD) takes top priority (supersedes displaced live activity).
    /// 2. When Onboarding or Welcome Greeting is occupying the main notch:
    ///    - If the Right Orb is already displaying an alert, any active LiveActivity steps into the Left Orb.
    ///    - If the Right Orb is displaying the primary LiveActivity and a 2nd concurrent LiveActivity exists ("dolarsa solda da"),
    ///      the 2nd activity is displayed in the Left Satellite Orb.
    /// 3. If a transient alert is occupying the main notch AND 2 or more persistent live activities exist:
    ///    The secondary persistent activity is displayed in the Left Satellite Orb (while primary rests in Right Orb).
    var leftSatelliteContent: NotchState.ContentType? {
        if let alert = leftSatelliteAlert {
            return alert
        }

        if isShowingOnboardingOrGreeting {
            let candidates = sortedLiveActivities
            if rightSatelliteAlert != nil {
                guard !candidates.isEmpty else { return nil }
                return isLiveActivitySwapped && candidates.count >= 2 ? candidates[1] : candidates[0]
            }

            guard candidates.count >= 2 else { return nil }
            return isLiveActivitySwapped ? candidates[0] : candidates[1]
        }

        if isPresentingAlert {
            let candidates = sortedLiveActivities
            guard candidates.count >= 2 else { return nil }
            return isLiveActivitySwapped ? candidates[0] : candidates[1]
        }

        return nil
    }

    /// True when the Left Satellite Orb should be visible flanking the left side of the notch
    var hasLeftSatelliteOrb: Bool {
        leftSatelliteContent != nil && hasActiveContent && !isScreenLocked && !isNotchTemporarilyHidden
    }

    func showLeftSatellite(content: NotchState.ContentType, duration: TimeInterval = 2.2) {
        guard !isScreenLocked, !isNotchTemporarilyHidden else { return }
        leftSatelliteDismissTimer?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
            leftSatelliteAlert = content
        }
        leftSatelliteDismissTimer = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dismissLeftSatellite()
            }
    }

    func dismissLeftSatellite() {
        leftSatelliteDismissTimer?.cancel()
        leftSatelliteDismissTimer = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            leftSatelliteAlert = nil
        }
    }

    func showRightSatellite(content: NotchState.ContentType, duration: TimeInterval = 2.2) {
        guard !isScreenLocked, !isNotchTemporarilyHidden else { return }
        rightSatelliteDismissTimer?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
            rightSatelliteAlert = content
        }
        rightSatelliteDismissTimer = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dismissRightSatellite()
            }
    }

    func dismissRightSatellite() {
        rightSatelliteDismissTimer?.cancel()
        rightSatelliteDismissTimer = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            rightSatelliteAlert = nil
        }
    }

    func promoteLeftSatelliteToMainNotch() {
        if isShowingOnboardingOrGreeting {
            if leftSatelliteAlert != nil {
                dismissLeftSatellite()
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                    isLiveActivitySwapped.toggle()
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            return
        }

        if let alert = leftSatelliteAlert {
            dismissLeftSatellite()
            presentAlert(alert)
            return
        }
        if isPresentingAlert {
            dismissCurrentAlert()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                isLiveActivitySwapped.toggle()
                if let newPrimary = activeLiveActivity {
                    displayedCompactActivity = newPrimary
                }
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private var sortedLiveActivities: [NotchState.ContentType] {
        [activeScreenRecordingActivity, activeTimerActivity, activeNowPlaying, activeCalendarActivity, activeHotspotActivity, activeExternalDriveActivity, activeDownload]
            .compactMap { $0 }
            .sorted(by: { $0.priority > $1.priority })
    }

    var activeLiveActivity: NotchState.ContentType? {
        let candidates = sortedLiveActivities
        guard !candidates.isEmpty else { return nil }
        if isLiveActivitySwapped && candidates.count >= 2 {
            return candidates[1]
        }
        return candidates[0]
    }

    /// True when an ephemeral alert/HUD (e.g. Volume, Brightness, Battery, Bluetooth, etc.) is actively presenting
    var isPresentingAlert: Bool {
        currentAlert?.isAlert == true
    }

    /// Right Satellite Orb Content:
    /// 1. Ephemeral alert actively displayed in the Right Satellite Orb (e.g. during Onboarding).
    /// 2. When Onboarding is occupying the main notch:
    ///    The dominant persistent LiveActivity (e.g. Now Playing, Timer) rests in the Right Satellite Orb.
    /// 3. When an instant alert is actively displayed in the main notch:
    ///    The dominant persistent LiveActivity steps aside to rest in the Right Satellite Orb.
    /// 4. When the main notch is displaying a primary LiveActivity and a secondary exists:
    ///    The secondary LiveActivity rests in the Right Satellite Orb.
    var secondaryLiveActivity: NotchState.ContentType? {
        if let alert = rightSatelliteAlert {
            return alert
        }

        if isShowingOnboardingOrGreeting {
            let candidates = sortedLiveActivities
            guard !candidates.isEmpty else { return nil }
            if isLiveActivitySwapped && candidates.count >= 2 {
                return candidates[1]
            }
            return candidates[0]
        }

        if isPresentingAlert {
            return activeLiveActivity
        }

        let candidates = sortedLiveActivities
        guard candidates.count >= 2 else { return nil }
        if isLiveActivitySwapped {
            return candidates[0]
        }
        return candidates[1]
    }

    /// True when the Satellite Orb should be visible beside the main notch
    var hasSecondaryLiveActivity: Bool {
        secondaryLiveActivity != nil && hasActiveContent && !isScreenLocked && !isNotchTemporarilyHidden
    }

    /// Swaps primary and secondary concurrent LiveActivities with a fluid Apple spring animation
    func swapLiveActivities() {
        guard hasSecondaryLiveActivity else { return }

        if isShowingOnboardingOrGreeting {
            if rightSatelliteAlert != nil {
                dismissRightSatellite()
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                    isLiveActivitySwapped.toggle()
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            return
        }

        if isPresentingAlert {
            // User interacted with the resting LiveActivity in the orb -> instantly dismiss the momentary alert and restore the LiveActivity to the main notch!
            dismissCurrentAlert()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            return
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
            isLiveActivitySwapped.toggle()
            if let newPrimary = activeLiveActivity {
                if isExpanded {
                    updateExpandedInPlace(to: newPrimary)
                } else {
                    displayedCompactActivity = newPrimary
                }
            }
        }

        // Tactile Apple haptic pulse
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private var alertQueue: [NotchState.ContentType] = []
    @Published private(set) var currentAlert: NotchState.ContentType?
    private var dismissTimer: AnyCancellable?
    private var hoverExitTimer: AnyCancellable?
    private var cleanupWorkItem: DispatchWorkItem?
    private var compactSwapWorkItem: DispatchWorkItem?
    private var pendingTransitionTarget: NotchState.ContentType?
    private var pendingTransitionExpand: Bool = false
    private var alertTriggeredWhileExpanded: Bool = false
    private var liveActivityRetentionTimers: [LiveActivityKind: DispatchWorkItem] = [:]
    private var cancellables = Set<AnyCancellable>()

    private var currentVisibleContent: NotchState.ContentType? {
        guard hasActiveContent else { return nil }
        return isExpanded ? displayedContent : displayedCompactActivity
    }

    // MARK: - UserDefaults Preferences

    var isNotchEnabled: Bool {
        UserDefaults.standard.object(forKey: "notchEnabled") as? Bool ?? true
    }
    private var showNowPlaying: Bool {
        UserDefaults.standard.object(forKey: "showNowPlaying") as? Bool ?? true
    }
    private var showBattery: Bool {
        UserDefaults.standard.object(forKey: "showBattery") as? Bool ?? true
    }
    private var showBluetooth: Bool {
        UserDefaults.standard.object(forKey: "showBluetooth") as? Bool ?? true
    }
    private var showVolume: Bool {
        UserDefaults.standard.object(forKey: "showVolume") as? Bool ?? true
    }
    private var showBrightness: Bool {
        UserDefaults.standard.object(forKey: "showBrightness") as? Bool ?? true
    }
    private var showDownloads: Bool {
        UserDefaults.standard.object(forKey: "showDownloads") as? Bool ?? true
    }
    private var showTimer: Bool {
        UserDefaults.standard.object(forKey: "showTimer") as? Bool ?? true
    }
    private var showClipboard: Bool {
        UserDefaults.standard.object(forKey: "showClipboard") as? Bool ?? true
    }
    var showScreenshots: Bool {
        get { UserDefaults.standard.object(forKey: "showScreenshots") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showScreenshots")
            objectWillChange.send()
        }
    }
    var showKeyboardBrightness: Bool {
        get { UserDefaults.standard.object(forKey: "showKeyboardBrightness") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showKeyboardBrightness")
            objectWillChange.send()
        }
    }
    var showExternalDrives: Bool {
        get { UserDefaults.standard.object(forKey: "showExternalDrives") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showExternalDrives")
            objectWillChange.send()
        }
    }
    var showCalendarEvents: Bool {
        get { UserDefaults.standard.object(forKey: "showCalendarEvents") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showCalendarEvents")
            objectWillChange.send()
        }
    }
    var showHotspotBattery: Bool {
        get { UserDefaults.standard.object(forKey: "showHotspotBattery") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showHotspotBattery")
            objectWillChange.send()
        }
    }
    private var widthMultiplier: CGFloat {
        let val = UserDefaults.standard.double(forKey: "notchWidthMultiplier")
        return val > 0 ? CGFloat(val) : 1.0
    }
    private var selectedExpandAnimation: Animation {
        let style = UserDefaults.standard.string(forKey: "animationStyle") ?? "spring"
        switch style {
        case "ease": return .easeInOut(duration: 0.34)
        case "fast": return .spring(response: 0.28, dampingFraction: 0.84)
        default:     return SpringConfig.expand
        }
    }
    private var selectedCollapseAnimation: Animation {
        let style = UserDefaults.standard.string(forKey: "animationStyle") ?? "spring"
        switch style {
        case "ease": return .easeInOut(duration: 0.34)
        case "fast": return .spring(response: 0.28, dampingFraction: 0.88)
        default:     return SpringConfig.collapse
        }
    }

    // MARK: - Init

    init() {
        Self.shared = self
        if !NotchOnboardingManager.shared.hasSeenOnboarding {
            activeOnboardingStep = .welcome
            currentAlert = .onboarding(.welcome)
        } else {
            currentAlert = .welcomeGreeting
        }
        bindObservers()
    }

    // MARK: - Mouse Hover Handling (Active ONLY when a LiveActivity or Alert is present)

    func setHovered(_ hovering: Bool) {
        guard isNotchEnabled && !isScreenLocked && !isNotchTemporarilyHidden else { return }
        guard activeLiveActivity != nil || currentAlert != nil || pendingTransitionTarget != nil else { return }

        hoverExitTimer?.cancel()
        hoverExitTimer = nil

        if hovering {
            isHovered = true

            // If a 2-phase shrink-then-grow transition is currently in flight,
            // let Phase 1 finish shrinking into the notch and upgrade Phase 2 to expand!
            if pendingTransitionTarget != nil {
                pendingTransitionExpand = true
                if currentAlert != nil && !alertTriggeredWhileExpanded {
                    dismissTimer?.cancel()
                    dismissTimer = nil
                }
                return
            }

            if let alert = currentAlert {
                if !alertTriggeredWhileExpanded {
                    dismissTimer?.cancel()
                    dismissTimer = nil
                }
                if !isExpanded {
                    expandFromIdleOrCompact(for: alert)
                }
            } else if let live = activeLiveActivity {
                if !isExpanded {
                    expandFromIdleOrCompact(for: live)
                } else if let visible = currentVisibleContent,
                          !visible.updatesInPlace(with: live, isExpanded: true) {
                    transitionThroughCutout(to: live, expand: true)
                }
            }
        } else {
            // ONBOARDING & GREETING SHIELD: If onboarding or welcome greeting is active, NEVER collapse or dismiss on hover exit!
            // The user must explicitly press Next / Sürdür or Skip to proceed (or greeting finishes its round).
            if isShowingOnboardingOrGreeting {
                isHovered = false
                return
            }

            hoverExitTimer = Just(())
                .delay(for: .milliseconds(120), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    if self.isShowingOnboardingOrGreeting { return }
                    self.isHovered = false

                    if let target = self.pendingTransitionTarget {
                        if target.isAlert {
                            self.alertTriggeredWhileExpanded = false
                            self.pendingTransitionExpand = !target.prefersCompactPresentation
                            self.scheduleAlertDismiss(duration: 2.0, for: target)
                        } else {
                            self.pendingTransitionExpand = false
                        }
                        return
                    }

                    if self.displayedContent == .emptySquareMenu {
                        self.contentBeforeSquareMenu = nil
                        if self.activeLiveActivity != nil {
                            self.showCompactWings()
                        } else {
                            self.hideCompletely()
                        }
                        return
                    }

                    if let alert = self.currentAlert {
                        if case .onboarding = alert { return }
                        self.alertTriggeredWhileExpanded = false
                        if VolumeHUDViewModel.shared.isAudioRouteExpanded {
                            return
                        }
                        if alert.prefersCompactPresentation {
                            self.collapseAlertToCompactWings(alert)
                            self.scheduleAlertDismiss(duration: 2.0, for: alert)
                        } else {
                            self.scheduleAlertDismiss(duration: 1.5, for: alert)
                        }
                    } else if self.activeLiveActivity != nil {
                        self.showCompactWings()
                    } else {
                        self.hideCompletely()
                    }
                }
        }
    }

    // MARK: - Observer Bindings

    private func bindObservers() {

        // 1. Now Playing (LiveActivity)
        mediaObserver.onAccessibilityPermissionRequired = { [weak self] in
            self?.handleIncoming(.accessibilityPermissionRequired)
        }

        mediaObserver.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if let track, self.showNowPlaying {
                    self.handleIncoming(.nowPlaying(track))
                } else {
                    self.endLiveActivity(ofKind: .nowPlaying)
                }
            }
            .store(in: &cancellables)

        // 1b. Now Playing Synchronized Lyrics Drawer Resize
        NotificationCenter.default.publisher(for: .notchLyricsToggleRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleNowPlayingLyrics()
            }
            .store(in: &cancellables)

        // 1c. Now Playing Audio Route Picker Drawer Resize
        NotificationCenter.default.publisher(for: .notchAudioRouteToggleRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleNowPlayingAudioRoute()
            }
            .store(in: &cancellables)

        // 1d. Volume HUD Audio Route Picker Horizontal Resize
        NotificationCenter.default.publisher(for: VolumeHUDViewModel.notchVolumeAudioRouteToggleRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleVolumeAudioRoute()
            }
            .store(in: &cancellables)

        VolumeHUDViewModel.shared.bind(to: volumeObserver)

        // 2. Battery Events (Alert)
        batteryObserver.$event
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self, self.showBattery else { return }
                switch event {
                case .charging: self.handleIncoming(.batteryCharging)
                case .low:      self.handleIncoming(.batteryLow)
                case .full:     self.handleIncoming(.batteryFull)
                }
            }
            .store(in: &cancellables)

        // 3. Bluetooth Events (Alert)
        bluetoothObserver.$event
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self, self.showBluetooth else { return }
                switch event {
                case .connected(let name):    self.handleIncoming(.bluetoothConnected(name))
                case .disconnected(let name): self.handleIncoming(.bluetoothDisconnected(name))
                }
            }
            .store(in: &cancellables)

        // 4. Volume Changes (Alert - debounced 50ms)
        volumeObserver.$volumeChangeEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] vol in
                guard let self, self.showVolume else { return }
                self.handleIncoming(.volumeChange(vol))
            }
            .store(in: &cancellables)

        // 4b. Mute / Unmute Events (Alert)
        volumeObserver.$muteChangeEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] isMuted in
                guard let self, self.showVolume else { return }
                if isMuted {
                    self.handleIncoming(.muted(true))
                } else {
                    self.handleIncoming(.volumeChange(self.volumeObserver.volume))
                }
            }
            .store(in: &cancellables)

        // 4c. Display Brightness Changes (Alert - debounced 35ms)
        brightnessObserver.$brightnessChangeEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .debounce(for: .milliseconds(35), scheduler: DispatchQueue.main)
            .sink { [weak self] b in
                guard let self, self.showBrightness else { return }
                // Suppress automatic OS brightness adjustments triggered by connecting or
                // disconnecting the power adapter ("Slightly dim display on battery")
                if self.batteryObserver.isWithinPowerTransitionCooldown {
                    return
                }
                self.handleIncoming(.brightnessChange(b))
            }
            .store(in: &cancellables)

        // 4d. Keyboard Backlight Brightness Changes (Alert - debounced 35ms)
        keyboardBrightnessObserver.$brightnessChangeEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .debounce(for: .milliseconds(35), scheduler: DispatchQueue.main)
            .sink { [weak self] b in
                guard let self, self.showKeyboardBrightness else { return }
                self.handleIncoming(.keyboardBrightnessChange(b))
            }
            .store(in: &cancellables)

        // 5. Downloads (LiveActivity)
        downloadObserver.$activeDownloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] downloads in
                guard let self else { return }
                if let first = downloads.first, self.showDownloads {
                    self.handleIncoming(.download(first))
                } else {
                    self.endLiveActivity(ofKind: .download)
                }
            }
            .store(in: &cancellables)

        // 6. Network Events (Wi-Fi / VPN Alert / No Internet)
        networkObserver.$event
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .wifiConnected(let ssid): 
                    self.handleIncoming(.wifiConnected(ssid))
                case .wifiDisconnected:        
                    self.handleIncoming(.wifiDisconnected)
                case .vpnConnected(let tunnelName, let connectedDate):            
                    self.handleIncoming(.vpnConnected(tunnelName, connectedDate))
                case .noInternet:
                    self.handleIncoming(.noInternet)
                case .internetRestored:
                    if self.displayedContent == .noInternet || self.currentAlert == .noInternet {
                        self.dismissCurrentAlert()
                    }
                    let ssid = self.networkObserver.wifiSSID
                    if self.networkObserver.isConnectedToWifi {
                        self.handleIncoming(.wifiConnected(ssid))
                    } else if self.networkObserver.isVPNActive {
                        let tunnel = self.networkObserver.vpnTunnelName
                        let date = self.networkObserver.vpnConnectedDate ?? Date()
                        self.handleIncoming(.vpnConnected(tunnel, date))
                    } else if self.networkObserver.hasInternetConnection {
                        let defaultName = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Wi-Fi Ağı" : "Wi-Fi Network"
                        self.handleIncoming(.wifiConnected(ssid.isEmpty ? defaultName : ssid))
                    }
                }
            }
            .store(in: &cancellables)

        // 7. Screen Recording (LiveActivity)
        screenRecordingObserver.$isRecording
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] isRecording in
                guard let self else { return }
                if isRecording {
                    let startDate = self.screenRecordingObserver.recordingStartDate ?? Date()
                    self.handleIncoming(.screenRecording(startDate))
                } else if self.activeScreenRecordingActivity != nil {
                    self.endLiveActivity(ofKind: .screenRecording)
                }
            }
            .store(in: &cancellables)

        // 8. Do Not Disturb / Focus Mode Changes (Alert)
        focusObserver.$focusChangeEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] isActive in
                guard let self else { return }
                self.handleIncoming(.focusChanged(isActive))
            }
            .store(in: &cancellables)

        // 9. Countdown Timer & Pomodoro (LiveActivity)
        timerObserver.$activeTimer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timerItem in
                guard let self else { return }
                if let timerItem, self.showTimer {
                    self.handleIncoming(.timer(timerItem))
                } else {
                    self.endLiveActivity(ofKind: .timer)
                }
            }
            .store(in: &cancellables)

        // 10. Clipboard History Manager (Alert)
        clipboardObserver.$lastCopiedItem
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.showClipboard else { return }
                let items = self.clipboardObserver.clipboardItems
                guard !items.isEmpty else { return }
                self.handleIncoming(.clipboard(items))
            }
            .store(in: &cancellables)

        // 11. Lock Screen State Observer
        lockScreenObserver.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locked in
                guard let self else { return }
                self.handleScreenLockChanged(locked)
            }
            .store(in: &cancellables)

        // 12. Screenshot Events (Alert)
        screenshotObserver.$screenshotEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] item in
                guard let self, self.showScreenshots else { return }
                self.handleIncoming(.screenshot(item))
            }
            .store(in: &cancellables)

        // 13. External Drives (LiveActivity & Eject Alerts)
        ExternalDriveManager.shared.$mountedDrives
            .receive(on: DispatchQueue.main)
            .sink { [weak self] drives in
                guard let self else { return }
                guard self.showExternalDrives else {
                    self.endLiveActivity(ofKind: .externalDrive)
                    return
                }
                if !drives.isEmpty {
                    self.handleIncoming(.externalDrive(drives))
                } else {
                    self.endLiveActivity(ofKind: .externalDrive)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .externalDriveDidEject)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, self.showExternalDrives else { return }
                let name = note.userInfo?["driveName"] as? String ?? "Harici Sürücü"
                let success = note.userInfo?["success"] as? Bool ?? true
                self.handleIncoming(.externalDriveEjected(name: name, success: success))
            }
            .store(in: &cancellables)

        // 14. Calendar Events (LiveActivity & Imminent Meeting Alerts)
        CalendarManager.shared.$activeOrNextEvent
            .combineLatest(CalendarManager.shared.$isMeetingActiveOrImminent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event, isImminent in
                guard let self else { return }
                guard self.showCalendarEvents, let event else {
                    self.endLiveActivity(ofKind: .calendarEvent)
                    return
                }
                if isImminent {
                    self.handleIncoming(.calendarEvent(event))
                } else {
                    self.endLiveActivity(ofKind: .calendarEvent)
                }
            }
            .store(in: &cancellables)

        CalendarManager.shared.onEventAlertTriggered = { [weak self] event in
            guard let self, self.showCalendarEvents else { return }
            self.handleIncoming(.calendarAlert(event))
        }

        // 15. Hotspot & Tethered iPhone Battery (LiveActivity & Low Battery Alerts)
        HotspotManager.shared.$currentHotspot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hotspot in
                guard let self else { return }
                guard self.showHotspotBattery, let hotspot else {
                    self.endLiveActivity(ofKind: .hotspot)
                    return
                }
                self.handleIncoming(.hotspot(hotspot))
            }
            .store(in: &cancellables)

        HotspotManager.shared.onLowBatteryAlertTriggered = { [weak self] hotspot in
            guard let self, self.showHotspotBattery else { return }
            self.handleIncoming(.hotspotLowBattery(hotspot))
        }
    }

    // MARK: - Routing Entry Point

    func handleIncoming(_ content: NotchState.ContentType) {
        guard isNotchEnabled else { return }

        if content.isLiveActivity {
            processLiveActivity(content)
        } else {
            handleAlertIncoming(content)
        }
    }

    private func isHUDIndicator(_ content: NotchState.ContentType) -> Bool {
        switch content {
        case .volumeChange, .brightnessChange, .keyboardBrightnessChange, .muted:
            return true
        default:
            return false
        }
    }

    private func handleAlertIncoming(_ alert: NotchState.ContentType) {
        // Case 0: ONBOARDING OR WELCOME GREETING ACTIVE
        // When the Onboarding flow or Welcome Greeting is occupying the main notch:
        // Do not interrupt the presentation. Route the incoming alert
        // to the Satellite Orbs: to the right by default, or to the left if the right is full!
        if isShowingOnboardingOrGreeting {
            let duration = alert.defaultDuration ?? 2.2

            // If the Left Satellite is already showing an alert of the SAME kind:
            if let leftAlert = leftSatelliteAlert, leftAlert.kindIdentifier == alert.kindIdentifier {
                showLeftSatellite(content: alert, duration: duration)
                return
            }

            // If the Right Satellite is already showing an alert of the SAME kind:
            if let rightAlert = rightSatelliteAlert, rightAlert.kindIdentifier == alert.kindIdentifier {
                showRightSatellite(content: alert, duration: duration)
                return
            }

            // Check if Right Satellite Orb is occupied (by an active right alert or background live activity):
            let isRightOccupied = (rightSatelliteAlert != nil) || (activeLiveActivity != nil)

            if isRightOccupied {
                // Right is occupied -> show on the LEFT ("dolarsa solda da")!
                showLeftSatellite(content: alert, duration: duration)
            } else {
                // Right is free -> show on the RIGHT!
                showRightSatellite(content: alert, duration: duration)
            }
            return
        }

        // Case 1: If an ephemeral alert is already displayed in the Left Satellite Orb,
        // and this incoming alert is of the SAME kind (e.g. repeated keyboard brightness keystrokes) ->
        // update the Left Satellite Orb in-place and refresh its dismiss timer!
        if let activeLeftAlert = leftSatelliteAlert, activeLeftAlert.kindIdentifier == alert.kindIdentifier {
            showLeftSatellite(content: alert, duration: 2.2)
            return
        }

        // Case 2: If the main notch is currently presenting an alert of the SAME kind
        // (e.g. continuous volume adjustments or continuous keyboard brightness adjustments):
        // It belongs in the main notch! Hand it over to enqueueAlert to update in-place smoothly.
        if let current = currentAlert, current.kindIdentifier == alert.kindIdentifier {
            enqueueAlert(alert)
            return
        }

        // Case 3: If the main notch is currently presenting a DIFFERENT active alert:
        // (e.g. Display Brightness is in main notch, and Keyboard Brightness arrives;
        //  or Volume is in main notch, and Screen/Keyboard Brightness arrives):
        if let current = currentAlert {
            if isHUDIndicator(alert) {
                // If the incoming alert is Keyboard Brightness -> route to Left Satellite Orb!
                if case .keyboardBrightnessChange = alert {
                    showLeftSatellite(content: alert, duration: 2.2)
                    return
                }

                // If the incoming alert is Display Brightness:
                if case .brightnessChange = alert {
                    if case .keyboardBrightnessChange(let kbVal) = current {
                        // Hand keyboard off to left satellite and let display brightness take main notch
                        showLeftSatellite(content: .keyboardBrightnessChange(kbVal), duration: 2.2)
                        currentAlert = nil
                        enqueueAlert(alert)
                        return
                    } else {
                        // Main notch is occupied by another alert (e.g. Volume) -> show Display Brightness on Left Satellite!
                        showLeftSatellite(content: alert, duration: 2.2)
                        return
                    }
                }

                // If the incoming alert is Volume:
                if case .volumeChange = alert, isHUDIndicator(current) {
                    // Hand the existing HUD to Left Satellite and let Volume take the main notch
                    showLeftSatellite(content: current, duration: 2.2)
                    currentAlert = nil
                    enqueueAlert(alert)
                    return
                }
            }
        }

        enqueueAlert(alert)
    }

    // MARK: - LiveActivity Scheduling

    private func processLiveActivity(_ liveActivity: NotchState.ContentType) {
        switch liveActivity {
        case .nowPlaying:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeNowPlaying = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .nowPlaying)
        case .download:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeDownload = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .download)
        case .timer:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeTimerActivity = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .timer)
        case .externalDrive:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeExternalDriveActivity = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .externalDrive)
        case .calendarEvent:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeCalendarActivity = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .calendarEvent)
        case .hotspot:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeHotspotActivity = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .hotspot)
        case .screenRecording:
            withAnimation(.spring(response: 0.44, dampingFraction: 0.70)) {
                activeScreenRecordingActivity = liveActivity
            }
            updateLiveActivityRetentionTimer(for: liveActivity, kind: .screenRecording)
        default:
            break
        }

        guard currentAlert == nil, !isNotchTemporarilyHidden, let active = activeLiveActivity else { return }
        guard !isScreenLocked else { return }

        let effectiveCurrent = pendingTransitionTarget ?? currentVisibleContent
        let shouldExpand     = (isHovered || isExpanded || (pendingTransitionTarget != nil && pendingTransitionExpand)) && !isScreenLocked

        if hasActiveContent {
            if let existing = effectiveCurrent,
               existing.updatesInPlace(with: active, isExpanded: shouldExpand) {
                if pendingTransitionTarget != nil {
                    pendingTransitionTarget = active
                } else if isExpanded && !isScreenLocked {
                    updateExpandedInPlace(to: active)
                } else {
                    updateCompactInPlace(to: active)
                }
            } else {
                transitionThroughCutout(to: active, expand: isHovered && !isScreenLocked)
            }
        } else {
            if isHovered && !isScreenLocked {
                expandFromIdleOrCompact(for: active)
            } else {
                emergeCompactFromIdle(for: active)
            }
        }
    }

    private enum LiveActivityKind: Hashable { case nowPlaying, download, timer, externalDrive, calendarEvent, hotspot, screenRecording }

    /// Centrally enforces the 5-minute retention policy for any LiveActivity that enters
    /// a paused or idle state, while keeping actively running activities alive indefinitely.
    private func updateLiveActivityRetentionTimer(
        for activity: NotchState.ContentType,
        kind: LiveActivityKind
    ) {
        liveActivityRetentionTimers[kind]?.cancel()
        liveActivityRetentionTimers[kind] = nil

        if activity.isLiveActivityPausedOrIdle {
            let work = DispatchWorkItem { [weak self] in
                self?.endLiveActivity(ofKind: kind)
            }
            liveActivityRetentionTimers[kind] = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NotchState.ContentType.liveActivityIdleRetentionDuration,
                execute: work
            )
        }
    }

    private func endLiveActivity(ofKind kind: LiveActivityKind) {
        liveActivityRetentionTimers[kind]?.cancel()
        liveActivityRetentionTimers[kind] = nil

        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
            switch kind {
            case .nowPlaying:
                activeNowPlaying = nil
            case .download:
                activeDownload = nil
            case .timer:
                activeTimerActivity = nil
            case .externalDrive:
                activeExternalDriveActivity = nil
            case .calendarEvent:
                activeCalendarActivity = nil
            case .hotspot:
                activeHotspotActivity = nil
            case .screenRecording:
                activeScreenRecordingActivity = nil
            }

            if sortedLiveActivities.count < 2 {
                isLiveActivitySwapped = false
            }
        }

        guard currentAlert == nil else { return }
        guard !isScreenLocked else { return }

        if let fallbackLive = activeLiveActivity {
            let effectiveCurrent   = pendingTransitionTarget ?? currentVisibleContent
            let mouseOverNotch     = windowController?.isMouseOverPhysicalNotch() ?? false
            if mouseOverNotch {
                isHovered = true
            }
            let shouldExpand       = (isHovered || isExpanded || mouseOverNotch || (pendingTransitionTarget != nil && pendingTransitionExpand)) && !isScreenLocked

            if hasActiveContent {
                if let existing = effectiveCurrent,
                   existing.updatesInPlace(with: fallbackLive, isExpanded: shouldExpand) {
                    if pendingTransitionTarget != nil {
                        pendingTransitionTarget = fallbackLive
                    } else if isExpanded && !isScreenLocked {
                        updateExpandedInPlace(to: fallbackLive)
                    } else if shouldExpand {
                        expandFromIdleOrCompact(for: fallbackLive)
                    } else {
                        updateCompactInPlace(to: fallbackLive)
                    }
                } else {
                    transitionThroughCutout(to: fallbackLive, expand: shouldExpand)
                }
            } else {
                if shouldExpand {
                    expandFromIdleOrCompact(for: fallbackLive)
                } else {
                    emergeCompactFromIdle(for: fallbackLive)
                }
            }
        } else {
            // No LiveActivity and no Alert remaining -> smoothly collapse and hide!
            hideCompletely()
        }
    }

    // MARK: - Alert Presentation & Queue

    private func enqueueAlert(_ alert: NotchState.ContentType) {
        guard !isNotchTemporarilyHidden else { return }
        presentAlert(alert)
    }

    private func presentAlert(_ alert: NotchState.ContentType) {
        let effectiveCurrent   = pendingTransitionTarget ?? currentVisibleContent
        let wasAlreadyExpanded = isExpanded || isHovered || VolumeHUDViewModel.shared.isAudioRouteExpanded || (pendingTransitionTarget != nil && pendingTransitionExpand)
        let isHUDIndicator: Bool = {
            switch alert {
            case .volumeChange, .brightnessChange, .keyboardBrightnessChange, .muted:
                return true
            default:
                return false
            }
        }()
        let shouldExpand       = (!alert.prefersCompactPresentation || wasAlreadyExpanded || VolumeHUDViewModel.shared.isAudioRouteExpanded || (activeLiveActivity != nil && !isHUDIndicator)) && !isScreenLocked
        let duration           = alert.defaultDuration ?? 3.0

        if let current = currentAlert, current != alert {
            // Check if this incoming alert is an in-place update of the active indicator
            // (e.g. continuous volume adjustments of the same indicator)
            let isSameIndicatorUpdate = (effectiveCurrent?.updatesInPlace(with: alert, isExpanded: shouldExpand) == true)
                || current.updatesInPlace(with: alert, isExpanded: shouldExpand)

            let isAudioStateTransition: Bool = {
                switch (current, alert) {
                case (.muted, .volumeChange), (.volumeChange, .muted):
                    return true
                default:
                    return false
                }
            }()

            if !isSameIndicatorUpdate && !isAudioStateTransition {
                // Do not allow an unrelated lower priority alert to interrupt an active higher priority alert!
                if alert.priority < current.priority {
                    return
                }
            }
        }

        currentAlert = alert

        if hasActiveContent {
            if let existing = effectiveCurrent,
               existing.updatesInPlace(with: alert, isExpanded: shouldExpand) {
                // Continuous update of the SAME active indicator (e.g. volume / brightness steps)
                if pendingTransitionTarget != nil {
                    // Phase 1 is currently animating towards cutout; do NOT cancel compactSwapWorkItem!
                    // Updating pendingTransitionTarget ensures Phase 2 will display the freshest value.
                    pendingTransitionTarget = alert
                    pendingTransitionExpand = shouldExpand
                    scheduleAlertDismiss(duration: duration + 0.26, for: alert)
                } else if shouldExpand {
                    compactSwapWorkItem?.cancel()
                    compactSwapWorkItem = nil
                    if isExpanded {
                        updateExpandedInPlace(to: alert)
                    } else {
                        expandFromIdleOrCompact(for: alert)
                    }
                    if !isHovered || alertTriggeredWhileExpanded {
                        if !VolumeHUDViewModel.shared.isAudioRouteExpanded {
                            scheduleAlertDismiss(duration: duration, for: alert)
                        }
                    }
                } else {
                    compactSwapWorkItem?.cancel()
                    compactSwapWorkItem = nil
                    updateCompactInPlace(to: alert)
                    scheduleAlertDismiss(duration: duration, for: alert)
                }
            } else {
                // Distinct action! Smoothly shrink the current menu/wings into the physical notch,
                // disappear, and then grow the new alert!
                compactSwapWorkItem?.cancel()
                compactSwapWorkItem = nil
                alertTriggeredWhileExpanded = wasAlreadyExpanded
                transitionThroughCutout(to: alert, expand: shouldExpand)
                scheduleAlertDismiss(duration: duration + 0.26, for: alert)
            }
        } else {
            compactSwapWorkItem?.cancel()
            compactSwapWorkItem = nil
            alertTriggeredWhileExpanded = false
            let mouseOverNotch = windowController?.isMouseOverPhysicalNotch() ?? false
            if mouseOverNotch {
                isHovered = true
            }
            let shouldExpandHUD = isHUDIndicator ? wasAlreadyExpanded : (shouldExpand || mouseOverNotch)
            if shouldExpandHUD {
                expandFromIdleOrCompact(for: alert)
            } else {
                emergeCompactFromIdle(for: alert)
            }
            scheduleAlertDismiss(duration: duration, for: alert)
        }
    }

    private func scheduleAlertDismiss(duration: TimeInterval, for alert: NotchState.ContentType) {
        if case .onboarding = alert { return }
        if case .welcomeGreeting = alert { return }
        if isShowingOnboardingOrGreeting { return }
        dismissTimer?.cancel()
        dismissTimer = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isShowingOnboardingOrGreeting else { return }
                self.onAlertCompleted()
            }
    }

    private func onAlertCompleted() {
        if isShowingOnboardingOrGreeting {
            return
        }
        if currentAlert == .shelf && !ShelfManager.shared.items.isEmpty {
            // Retain shelf while items are held in the shelf tray
            return
        }
        VolumeHUDViewModel.shared.reset()
        dismissTimer?.cancel()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            currentAlert = nil
        }

        let wasExpandedByHover = alertTriggeredWhileExpanded
        alertTriggeredWhileExpanded = false

        if !alertQueue.isEmpty {
            let next = alertQueue.removeFirst()
            presentAlert(next)
        } else if isScreenLocked {
            returnToLockScreenState()
        } else if let live = activeLiveActivity {
            // Check if cursor is directly on the physical notch at this moment
            let isOverPhysicalNotch = windowController?.isMouseOverPhysicalNotch() ?? false

            // The background LiveActivity should ONLY be expanded if it was ALREADY expanded before the alert,
            // AND the user's cursor is physically resting over the notch right now!
            let shouldExpandLive = !isScreenLocked && wasExpandedByHover && isOverPhysicalNotch
            isHovered = shouldExpandLive

            // Smoothly shrink the finished alert into the physical notch,
            // disappear, and then grow the active LiveActivity (Compact wings by default)!
            transitionThroughCutout(to: live, expand: shouldExpandLive)
        } else {
            // Nothing left at all -> smoothly collapse into the physical notch!
            isHovered = false
            hideCompletely()
        }
    }

    private func returnToLockScreenState() {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size
        let compactSize = NotchPositionCalculator.compactFrame(for: screen).size

        // Phase 1 (0.24s): Smoothly shrink the momentary alert wings into the physical notch
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            isExpanded = false
            isCompactWingsSwappingOut = true
            pillSize = hiddenSize
        }

        // Phase 2 (+0.24s): Once inside the notch, clear the alert's compact activity
        // and emerge the lock screen wings (lock icon + "Kilitli")
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isScreenLocked, self.currentAlert == nil else { return }

            self.displayedCompactActivity = nil
            self.windowController?.collapseToCompact()

            withAnimation(SpringConfig.compactAppear) {
                self.hasActiveContent = true
                self.isNotchVisible = true
                self.isExpanded = false
                self.isCompactWingsSwappingOut = false
                self.pillSize = compactSize
            }
        }
        compactSwapWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: work)
    }

    // MARK: - Lock Screen Handling

    private func handleScreenLockChanged(_ locked: Bool) {
        if locked {
            isScreenLocked = true
            isLockScreenUnlocking = false
            hoverExitTimer?.cancel()
            hoverExitTimer = nil
            isHovered = false
            currentAlert = nil
            alertQueue.removeAll()
            displayedCompactActivity = nil

            windowController?.onScreenLocked()

            let screen = NSScreen.main ?? NSScreen.screens[0]
            let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size
            let compactSize = NotchPositionCalculator.compactFrame(for: screen).size

            let wasActiveAndVisible = hasActiveContent && isNotchVisible && pillSize.width > hiddenSize.width + 10

            if wasActiveAndVisible {
                // Phase 1 (0.24s): Smoothly retract the outgoing action into the physical camera cutout!
                // Outgoing content remains rendered in the wings while sliding inside and shrinking.
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    self.isExpanded = false
                    self.isCompactWingsSwappingOut = true
                    self.pillSize = hiddenSize
                }

                // Phase 2 (+0.24s, inside cutout): Atomically switch to lock screen and emerge lock wings!
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isScreenLocked else { return }
                    self.displayedCompactActivity = nil
                    self.windowController?.collapseToCompact()

                    withAnimation(SpringConfig.compactAppear) {
                        self.hasActiveContent = true
                        self.isNotchVisible = true
                        self.isExpanded = false
                        self.isCompactWingsSwappingOut = false
                        self.pillSize = compactSize
                    }
                }
                compactSwapWorkItem = work
                isScreenLocked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: work)
            } else {
                // Notch was idle/hidden -> directly emerge the lock wings from the camera cutout!
                isScreenLocked = true
                displayedCompactActivity = nil
                windowController?.collapseToCompact()

                withAnimation(SpringConfig.compactAppear) {
                    self.hasActiveContent = true
                    self.isNotchVisible = true
                    self.isExpanded = false
                    self.isCompactWingsSwappingOut = false
                    self.pillSize = compactSize
                }
            }
        } else {
            guard isScreenLocked else { return }

            // 1. Unlocked animation (green lock.open.fill + "Açıldı")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isLockScreenUnlocking = true
            }

            // 2. Vanish into notch effect (Yok olma efekti)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, self.isScreenLocked else { return }

                let screen = NSScreen.main ?? NSScreen.screens[0]
                let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size

                withAnimation(SpringConfig.collapse) {
                    self.isLockScreenUnlocking = false
                    self.isScreenLocked = false
                    self.hasActiveContent = false
                    self.isCompactWingsSwappingOut = true
                    self.displayedCompactActivity = nil
                    self.pillSize = hiddenSize
                }
                self.windowController?.hideToIdle()

                // 3. Emerge active item with animation effect, if present
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                    guard let self else { return }
                    self.isCompactWingsSwappingOut = false
                    self.windowController?.onScreenUnlocked()

                    if self.activeLiveActivity != nil {
                        self.showCompactWings()
                    } else if self.currentAlert != nil {
                        // Let alert resume or finish
                    } else {
                        self.hideCompletely()
                    }
                }
            }
        }
    }

    // MARK: - Unified 2-Phase & Direct Window/Pill Transitions

    private func effectiveTargetSize(for content: NotchState.ContentType, screen: NSScreen) -> CGSize {
        var targetSize = NotchSizeCalculator.dynamicSize(for: content, screen: screen)
        if widthMultiplier != 1.0 && !content.prefersCompactPresentation {
            let baseW = NotchPositionCalculator.compactFrame(for: screen).width + 20
            let maxW  = screen.frame.width * 0.60
            targetSize.width = min(maxW, max(baseW, ceil(targetSize.width * widthMultiplier)))
        }
        return targetSize
    }

    /// Universal 2-Phase Transition between any two distinct actions (`Action A -> Action B`):
    /// Phase 1 (0.26s): Smoothly shrinks the currently visible menu or compact wings AND the black
    ///                  notch background completely into the physical camera cutout (`hiddenSize`).
    /// Phase 2 (+0.26s): Atomically swaps the content while hidden inside the cutout and smoothly
    ///                   grows the new action into Expanded or Compact mode.
    private func transitionThroughCutout(
        to targetContent: NotchState.ContentType,
        expand targetExpanded: Bool
    ) {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil

        pendingTransitionTarget = targetContent
        pendingTransitionExpand = targetExpanded

        let screen     = NSScreen.main ?? NSScreen.screens[0]
        let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size

        windowController?.beginRetractTransition()

        // Phase 1: Shrink outgoing menu/wings + black background into the physical notch.
        // Outgoing `displayedContent`, `displayedCompactActivity`, and `expandedContentSize`
        // remain intact during Phase 1 so the outgoing view scales down cleanly without jumping.
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            isExpanded                = false
            isCompactWingsSwappingOut = true
            pillSize                  = hiddenSize
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let nextContent = self.pendingTransitionTarget ?? self.currentAlert
            guard let nextContent else { return }
            let shouldExpand = self.pendingTransitionExpand
            self.pendingTransitionTarget = nil
            self.pendingTransitionExpand = false
            self.compactSwapWorkItem = nil

            let screen      = NSScreen.main ?? NSScreen.screens[0]
            let compactSize = NotchPositionCalculator.compactFrame(for: screen).size
            let targetSize  = self.effectiveTargetSize(for: nextContent, screen: screen)

            // Swap content and target frame while invisible inside `hiddenSize` (zero layout jump).
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.isNotchVisible           = true
                self.displayedContent         = nextContent
                self.displayedCompactActivity = nextContent
                self.expandedContentSize      = targetSize
                self.state                    = .expanded(nextContent)
            }

            // Phase 2: Grow the new action out of the physical notch!
            let isOverPhysicalNotch = self.windowController?.isMouseOverPhysicalNotch() ?? false
            let finalExpand = (shouldExpand || (isOverPhysicalNotch && self.isHovered)) && !self.isScreenLocked
            if finalExpand {
                self.isHovered = true
                self.windowController?.expand(
                    to: targetSize,
                    preserveHoverRetention: self.activeLiveActivity != nil
                )
                withAnimation(self.selectedExpandAnimation) {
                    self.hasActiveContent          = true
                    self.isExpanded                = true
                    self.isCompactWingsSwappingOut = false
                    self.pillSize                  = targetSize
                }
            } else {
                self.isHovered = isOverPhysicalNotch
                self.windowController?.collapseToCompact()
                withAnimation(SpringConfig.compactAppear) {
                    self.hasActiveContent          = true
                    self.isExpanded                = false
                    self.isCompactWingsSwappingOut = false
                    self.pillSize                  = compactSize
                }
            }
        }

        compactSwapWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: work)
    }

    /// Expands the notch from Idle (`hiddenSize`) or from the SAME item's Compact Wings.
    private func expandFromIdleOrCompact(for content: NotchState.ContentType) {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil
        pendingTransitionTarget = nil
        pendingTransitionExpand = false

        let screen     = NSScreen.main ?? NSScreen.screens[0]
        let targetSize = effectiveTargetSize(for: content, screen: screen)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isNotchVisible           = true
            displayedCompactActivity = content
            displayedContent         = content
            expandedContentSize      = targetSize
            state                    = .expanded(content)
            isCompactWingsSwappingOut = false
        }

        windowController?.expand(
            to: targetSize,
            preserveHoverRetention: activeLiveActivity != nil
        )

        withAnimation(selectedExpandAnimation) {
            hasActiveContent = true
            isExpanded       = true
            pillSize         = targetSize
        }
    }

    /// Emerges compact wings directly from Idle (`hiddenSize`).
    private func emergeCompactFromIdle(for content: NotchState.ContentType) {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil
        pendingTransitionTarget = nil
        pendingTransitionExpand = false

        let screen      = NSScreen.main ?? NSScreen.screens[0]
        let compactSize = NotchPositionCalculator.compactFrame(for: screen).size
        let targetSize  = effectiveTargetSize(for: content, screen: screen)

        // If cursor is already resting over the physical notch area, expand immediately!
        let mouseOverNotch = windowController?.isMouseOverPhysicalNotch() ?? false
        if !isScreenLocked && (isHovered || mouseOverNotch) {
            isHovered = true
            expandFromIdleOrCompact(for: content)
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isNotchVisible            = true
            displayedCompactActivity  = content
            displayedContent          = content
            expandedContentSize       = targetSize
            state                     = .expanded(content)
            isCompactWingsSwappingOut = false
        }

        windowController?.collapseToCompact()

        withAnimation(SpringConfig.compactAppear) {
            hasActiveContent = true
            isExpanded       = false
            pillSize         = compactSize
        }
    }

    /// Updates the currently expanded card in-place when the same feature emits new data
    /// (e.g. volume steps, track progress, download progress).
    private func updateExpandedInPlace(to content: NotchState.ContentType) {
        let screen     = NSScreen.main ?? NSScreen.screens[0]
        let targetSize = effectiveTargetSize(for: content, screen: screen)

        windowController?.expand(
            to: targetSize,
            preserveHoverRetention: activeLiveActivity != nil
        )

        isNotchVisible           = true
        displayedCompactActivity = content
        displayedContent         = content
        state                    = .expanded(content)

        if expandedContentSize != targetSize || pillSize != targetSize {
            withAnimation(selectedExpandAnimation) {
                expandedContentSize = targetSize
                pillSize            = targetSize
            }
        }
    }

    /// Updates the currently visible compact wings in-place when the same feature emits new data.
    private func updateCompactInPlace(to content: NotchState.ContentType) {
        let screen      = NSScreen.main ?? NSScreen.screens[0]
        let compactSize = NotchPositionCalculator.compactFrame(for: screen).size
        let targetSize  = effectiveTargetSize(for: content, screen: screen)

        windowController?.collapseToCompact()

        isNotchVisible            = true
        displayedCompactActivity  = content
        displayedContent          = content
        expandedContentSize       = targetSize
        isCompactWingsSwappingOut = false
        state                     = .expanded(content)
        hasActiveContent          = true
        isExpanded                = false
        pillSize                  = compactSize
    }

    /// Collapses an expanded Compact-First Alert back to its own Compact Wings when the cursor leaves.
    private func collapseAlertToCompactWings(_ alert: NotchState.ContentType) {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil
        pendingTransitionTarget = nil
        pendingTransitionExpand = false

        let screen      = NSScreen.main ?? NSScreen.screens[0]
        let compactSize = NotchPositionCalculator.compactFrame(for: screen).size

        windowController?.collapseToCompact()

        isNotchVisible            = true
        displayedCompactActivity  = alert
        isCompactWingsSwappingOut = false

        withAnimation(selectedCollapseAnimation) {
            state            = .expanded(alert)
            hasActiveContent = true
            isExpanded       = false
            pillSize         = compactSize
        }
    }

    /// Collapses an expanded LiveActivity back to its own Compact Wings when the cursor leaves.
    private func showCompactWings() {
        guard let live = activeLiveActivity else {
            hideCompletely()
            return
        }

        if let visible = currentVisibleContent,
           !visible.updatesInPlace(with: live, isExpanded: false) {
            transitionThroughCutout(to: live, expand: false)
            return
        }

        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil
        pendingTransitionTarget = nil
        pendingTransitionExpand = false
        dismissTimer?.cancel()
        dismissTimer = nil
        currentAlert = nil

        let screen      = NSScreen.main ?? NSScreen.screens[0]
        let compactSize = NotchPositionCalculator.compactFrame(for: screen).size

        windowController?.collapseToCompact()

        isNotchVisible            = true
        displayedCompactActivity  = live
        isCompactWingsSwappingOut = false
        if displayedContent == nil || !isExpanded {
            displayedContent    = live
            expandedContentSize = effectiveTargetSize(for: live, screen: screen)
        }

        let anim = isExpanded ? selectedCollapseAnimation : SpringConfig.compactAppear

        withAnimation(anim) {
            state            = .expanded(live)
            hasActiveContent = true
            isExpanded       = false
            pillSize         = compactSize
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hasActiveContent, !self.isExpanded else { return }
            if let active = self.activeLiveActivity {
                self.displayedContent    = active
                self.expandedContentSize = self.effectiveTargetSize(for: active, screen: screen)
            }
        }
        cleanupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    /// State 1: Smoothly collapse into the physical notch and hide completely.
    private func hideCompletely() {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        compactSwapWorkItem?.cancel()
        compactSwapWorkItem = nil
        pendingTransitionTarget = nil
        pendingTransitionExpand = false
        alertTriggeredWhileExpanded = false
        VolumeHUDViewModel.shared.reset()
        dismissTimer?.cancel()
        dismissTimer = nil
        dismissLeftSatellite()
        currentAlert = nil
        isHovered    = false

        let screen     = NSScreen.main ?? NSScreen.screens[0]
        let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size

        // Keep `displayedContent`, `displayedCompactActivity`, and `isNotchVisible = true`
        // alive while `pillSize` and the inner views smoothly animate into the hardware notch!
        withAnimation(selectedCollapseAnimation) {
            hasActiveContent          = false
            isExpanded                = false
            isCompactWingsSwappingOut = true
            pillSize                  = hiddenSize
        }

        windowController?.hideToIdle()

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasActiveContent else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                self.isNotchVisible = false
            }
            self.isCompactWingsSwappingOut = false
            self.state                     = .idle
            self.displayedContent          = nil
            self.displayedCompactActivity  = nil
        }
        cleanupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    // MARK: - Interactive Volume Control from Expanded HUD

    func setVolumeFromHUD(_ newVolume: Float) {
        let clamped = min(max(newVolume, 0.0), 1.0)
        volumeObserver.setVolume(clamped)

        let updated: NotchState.ContentType = .volumeChange(clamped)
        currentAlert             = updated
        displayedContent         = updated
        displayedCompactActivity = updated
        state                    = .expanded(updated)

        if alertTriggeredWhileExpanded || !isHovered {
            scheduleAlertDismiss(duration: 2.2, for: updated)
        }
    }

    func toggleMuteFromHUD() {
        volumeObserver.toggleMute()
        let updated: NotchState.ContentType = .volumeChange(volumeObserver.volume)
        currentAlert             = updated
        displayedContent         = updated
        displayedCompactActivity = updated
        state                    = .expanded(updated)

        if alertTriggeredWhileExpanded || !isHovered {
            scheduleAlertDismiss(duration: 2.2, for: updated)
        }
    }

    // MARK: - Interactive Brightness Control from Expanded HUD

    func setBrightnessFromHUD(_ newBrightness: Float) {
        let clamped = min(max(newBrightness, 0.0), 1.0)
        brightnessObserver.setBrightness(clamped)

        let updated: NotchState.ContentType = .brightnessChange(clamped)
        currentAlert             = updated
        displayedContent         = updated
        displayedCompactActivity = updated
        state                    = .expanded(updated)

        if alertTriggeredWhileExpanded || !isHovered {
            scheduleAlertDismiss(duration: 2.2, for: updated)
        }
    }

    // MARK: - Interactive Keyboard Brightness Control from Expanded HUD & HotKeys

    func setKeyboardBrightness(_ newBrightness: Float) {
        let clamped = min(max(newBrightness, 0.0), 1.0)
        keyboardBrightnessObserver.setBrightness(clamped)
        handleAlertIncoming(.keyboardBrightnessChange(clamped))
    }

    func setKeyboardBrightnessFromHUD(_ newBrightness: Float) {
        let clamped = min(max(newBrightness, 0.0), 1.0)
        keyboardBrightnessObserver.setBrightness(clamped)

        let updated: NotchState.ContentType = .keyboardBrightnessChange(clamped)
        currentAlert             = updated
        displayedContent         = updated
        displayedCompactActivity = updated
        if isExpanded {
            state = .expanded(updated)
        }

        if alertTriggeredWhileExpanded || !isHovered {
            scheduleAlertDismiss(duration: 2.2, for: updated)
        }
    }

    func stepKeyboardBrightnessUp(fine: Bool = false) {
        keyboardBrightnessObserver.stepUp(fine: fine)
        let current = keyboardBrightnessObserver.brightness
        handleAlertIncoming(.keyboardBrightnessChange(current))
    }

    func stepKeyboardBrightnessDown(fine: Bool = false) {
        keyboardBrightnessObserver.stepDown(fine: fine)
        let current = keyboardBrightnessObserver.brightness
        handleAlertIncoming(.keyboardBrightnessChange(current))
    }

    // MARK: - Synchronized Lyrics & Audio Route Toggles (Atomic Coordinated Springs)

    func toggleNowPlayingLyrics() {
        guard isExpanded, case .nowPlaying = displayedContent, let active = activeNowPlaying else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]

        withAnimation(selectedExpandAnimation) {
            if NowPlayingViewModel.shared.isAudioRouteExpanded {
                NowPlayingViewModel.shared.isAudioRouteExpanded = false
            }
            NowPlayingViewModel.shared.isLyricsExpanded.toggle()
            let targetSize = effectiveTargetSize(for: active, screen: screen)
            expandedContentSize = targetSize
            pillSize            = targetSize
        }

        windowController?.expand(
            to: pillSize,
            preserveHoverRetention: true
        )
    }

    func toggleNowPlayingAudioRoute() {
        guard isExpanded, case .nowPlaying = displayedContent, let active = activeNowPlaying else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]

        withAnimation(selectedExpandAnimation) {
            if NowPlayingViewModel.shared.isLyricsExpanded {
                NowPlayingViewModel.shared.isLyricsExpanded = false
            }
            NowPlayingViewModel.shared.isAudioRouteExpanded.toggle()
            let targetSize = effectiveTargetSize(for: active, screen: screen)
            expandedContentSize = targetSize
            pillSize            = targetSize
        }

        windowController?.expand(
            to: pillSize,
            preserveHoverRetention: true
        )
    }

    func openAudioRoutePicker() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        let alert = NotchState.ContentType.volumeChange(volumeObserver.volume)
        if VolumeHUDViewModel.shared.isAudioRouteExpanded && displayedContent == alert {
            performToggleVolumeAudioRoute(alert: alert)
        } else {
            VolumeHUDViewModel.shared.isAudioRouteExpanded = false
            performToggleVolumeAudioRoute(alert: alert)
        }
    }

    func toggleVolumeAudioRoute() {
        guard let alert = currentAlert else { return }
        switch alert {
        case .volumeChange, .muted:
            performToggleVolumeAudioRoute(alert: alert)
        default:
            break
        }
    }

    private func performToggleVolumeAudioRoute(alert: NotchState.ContentType) {
        let screen = NSScreen.main ?? NSScreen.screens[0]

        withAnimation(selectedExpandAnimation) {
            VolumeHUDViewModel.shared.isAudioRouteExpanded.toggle()
            isExpanded = true
            hasActiveContent = true
            isNotchVisible = true
            displayedContent = alert
            state = .expanded(alert)
            let targetSize = effectiveTargetSize(for: alert, screen: screen)
            expandedContentSize = targetSize
            pillSize            = targetSize
        }

        windowController?.expand(
            to: pillSize,
            preserveHoverRetention: true
        )

        if VolumeHUDViewModel.shared.isAudioRouteExpanded {
            // Suspend dismiss timer while route picker drawer is open!
            dismissTimer?.cancel()
            dismissTimer = nil
        } else {
            // Resume dismiss timer when collapsed
            scheduleAlertDismiss(duration: 2.2, for: alert)
        }
    }

    // MARK: - Manual Dismiss / Reset

    func cancelTimer() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        timerObserver.cancel()
        dismissTimer?.cancel()
        dismissTimer = nil
        pendingTransitionTarget = nil
        currentAlert = nil

        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
            activeTimerActivity = nil
            if sortedLiveActivities.count < 2 {
                isLiveActivitySwapped = false
            }
        }

        if let nowPlaying = activeNowPlaying {
            processLiveActivity(nowPlaying)
        } else {
            hideCompletely()
        }
    }

    func dismissCurrentAlert() {
        guard currentAlert != nil else { return }
        if isShowingOnboardingOrGreeting { return }
        onAlertCompleted()
    }

    func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
            if !NSWorkspace.shared.open(url) {
                if let fallback = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                    NSWorkspace.shared.open(fallback)
                }
            }
        }
        dismissCurrentAlert()
    }

    // MARK: - Onboarding Presentation

    @Published private(set) var activeOnboardingStep: OnboardingStep? = nil

    func presentOnboarding(step: OnboardingStep) {
        dismissTimer?.cancel()
        dismissTimer = nil
        hoverExitTimer?.cancel()
        hoverExitTimer = nil

        activeOnboardingStep = step
        let content = NotchState.ContentType.onboarding(step)
        currentAlert = content

        if isExpanded {
            updateExpandedInPlace(to: content)
        } else {
            expandFromIdleOrCompact(for: content)
        }
    }

    func dismissOnboarding() {
        activeOnboardingStep = nil
        dismissTimer?.cancel()
        dismissTimer = nil
        hoverExitTimer?.cancel()
        hoverExitTimer = nil

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size

        if let live = activeLiveActivity {
            // SÜREĞEN AKSİYON VARSA: 2-Aşamalı Apple Akışkan Geçişi (Retract & Bloom)
            windowController?.beginRetractTransition()

            withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                self.isExpanded = false
                self.isCompactWingsSwappingOut = true
                self.pillSize = hiddenSize
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                guard let self else { return }
                self.currentAlert = nil
                self.dismissRightSatellite()
                self.dismissLeftSatellite()

                let mouseOverNotch = self.windowController?.isMouseOverPhysicalNotch() ?? false
                if !self.isScreenLocked && (self.isHovered || mouseOverNotch) {
                    self.isHovered = true
                    self.isCompactWingsSwappingOut = false
                    self.expandFromIdleOrCompact(for: live)
                } else {
                    let compactSize = NotchPositionCalculator.compactFrame(for: screen).size
                    let targetSize = self.effectiveTargetSize(for: live, screen: screen)

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.isNotchVisible = true
                        self.displayedCompactActivity = live
                        self.displayedContent = live
                        self.expandedContentSize = targetSize
                        self.state = .expanded(live)
                    }

                    self.windowController?.collapseToCompact()

                    withAnimation(SpringConfig.compactAppear) {
                        self.hasActiveContent = true
                        self.isExpanded = false
                        self.isCompactWingsSwappingOut = false
                        self.pillSize = compactSize
                    }
                }
            }
        } else if !alertQueue.isEmpty {
            let next = alertQueue.removeFirst()
            currentAlert = nil
            dismissRightSatellite()
            dismissLeftSatellite()
            presentAlert(next)
        } else {
            hideCompletely()
        }
    }

    // MARK: - Welcome Greeting Presentation (1-Round App Launch Animation)

    func presentWelcomeGreeting() {
        dismissTimer?.cancel()
        dismissTimer = nil
        hoverExitTimer?.cancel()
        hoverExitTimer = nil

        let content = NotchState.ContentType.welcomeGreeting
        currentAlert = content

        if isExpanded {
            updateExpandedInPlace(to: content)
        } else {
            expandFromIdleOrCompact(for: content)
        }
    }

    func dismissWelcomeGreeting() {
        guard currentAlert == .welcomeGreeting else { return }
        dismissTimer?.cancel()
        dismissTimer = nil
        hoverExitTimer?.cancel()
        hoverExitTimer = nil

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let hiddenSize = NotchPositionCalculator.hiddenFrame(for: screen).size

        if let live = activeLiveActivity {
            // SÜREĞEN AKSİYON VARSA: Kusursuz 2-Aşamalı Apple Akışkan Geçişi (Retract & Bloom)
            // Aşama 1 (0.26s): Boşalan welcome kartı ve sağdaki uydu orb'u fiziksel çentiğe çekilir (absorb)
            windowController?.beginRetractTransition()

            withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                self.isExpanded = false
                self.isCompactWingsSwappingOut = true
                self.pillSize = hiddenSize
            }

            // Aşama 2 (0.26s sonra): Fiziksel kamera çentiğinden süreğen canlı etkinlik (müzik vb.) pürüzsüzce doğar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                guard let self else { return }
                self.currentAlert = nil
                self.dismissRightSatellite()
                self.dismissLeftSatellite()

                let mouseOverNotch = self.windowController?.isMouseOverPhysicalNotch() ?? false
                if !self.isScreenLocked && (self.isHovered || mouseOverNotch) {
                    self.isHovered = true
                    self.isCompactWingsSwappingOut = false
                    self.expandFromIdleOrCompact(for: live)
                } else {
                    let compactSize = NotchPositionCalculator.compactFrame(for: screen).size
                    let targetSize = self.effectiveTargetSize(for: live, screen: screen)

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.isNotchVisible = true
                        self.displayedCompactActivity = live
                        self.displayedContent = live
                        self.expandedContentSize = targetSize
                        self.state = .expanded(live)
                    }

                    self.windowController?.collapseToCompact()

                    withAnimation(SpringConfig.compactAppear) {
                        self.hasActiveContent = true
                        self.isExpanded = false
                        self.isCompactWingsSwappingOut = false
                        self.pillSize = compactSize
                    }
                }
            }
        } else if !alertQueue.isEmpty {
            let next = alertQueue.removeFirst()
            currentAlert = nil
            dismissRightSatellite()
            dismissLeftSatellite()
            presentAlert(next)
        } else {
            hideCompletely()
        }
    }

    func dismiss() {
        alertQueue.removeAll()
        activeNowPlaying    = nil
        activeDownload      = nil
        activeTimerActivity = nil
        hideCompletely()
    }

    // MARK: - Simulation & Diagnostic Triggers

    private var simulatedMusicTrackIndex = 0

    func simulateNowPlaying() {
        simulatedMusicTrackIndex = (simulatedMusicTrackIndex % 3) + 1
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let elapsed: Double
        let color: Color

        switch simulatedMusicTrackIndex {
        case 1:
            title = "Veridis Quo"
            artist = "Daft Punk"
            album = "Discovery"
            duration = 345
            elapsed = 142
            color = Color(red: 0.98, green: 0.65, blue: 0.20) // Iconic Discovery Gold
        case 2:
            title = "Cruel Summer"
            artist = "Taylor Swift"
            album = "Lover"
            duration = 178
            elapsed = 42
            color = Color(red: 0.96, green: 0.38, blue: 0.64) // Lover Magenta / Pink
        default:
            title = "Blinding Lights"
            artist = "The Weeknd"
            album = "After Hours"
            duration = 200
            elapsed = 85
            color = Color(red: 0.92, green: 0.24, blue: 0.22) // After Hours Crimson Red
        }

        let sample = NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsed,
            artwork: nil,
            isPlaying: true,
            appName: "Music",
            accentColor: color
        )
        processLiveActivity(.nowPlaying(sample))
    }

    func simulateBatteryLow() {
        batteryObserver.debugTrigger(.low)
    }

    func simulateBatteryCharging() {
        batteryObserver.debugTrigger(.charging)
    }

    func simulateBatteryFull() {
        batteryObserver.debugTrigger(.full)
    }

    func simulateBluetoothConnected() {
        let deviceName = "AirPods Pro (2. Nesil)"
        let simulatedBattery = AirPodsBattery(left: 88, right: 100, caseLevel: 72)
        bluetoothObserver.debugTriggerConnected(name: deviceName, battery: 100, detailedBattery: simulatedBattery)
    }

    func simulateVolumeHUD() {
        handleIncoming(.volumeChange(0.75))
    }

    func simulateBrightnessHUD() {
        handleIncoming(.brightnessChange(0.70))
    }

    func simulateKeyboardBrightnessHUD() {
        let level = keyboardBrightnessObserver.readCurrentBrightness() ?? 0.625
        handleIncoming(.keyboardBrightnessChange(level))
    }

    func simulateDualBrightness() {
        handleIncoming(.brightnessChange(0.75))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.handleIncoming(.keyboardBrightnessChange(0.50))
        }
    }

    func simulateTripleCollision() {
        // 1. Simulate active Now Playing (Music)
        simulateNowPlaying()
        // 2. Start active Timer (5 Dakika)
        timerObserver.startTimer(duration: 300, title: "5 Dakika")

        // 3. 0.4s later: Trigger Volume HUD in the main notch
        // -> Primary Live Activity (Music) steps to Right Satellite Orb
        // -> Secondary Live Activity (Timer) steps to Left Satellite Orb
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { [weak self] in
            self?.handleIncoming(.volumeChange(0.65))

            // 4. 0.7s later: Trigger automatic Display Brightness HUD
            // -> Displaces Timer on the Left Satellite Orb temporarily with Display Brightness!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) { [weak self] in
                self?.handleIncoming(.brightnessChange(0.40))
            }
        }
    }

    private var simulatedMuteState = false

    func simulateMuted() {
        simulatedMuteState.toggle()
        handleIncoming(.muted(simulatedMuteState))
    }

    private var simulatedFocusState = false

    func simulateFocusChanged() {
        simulatedFocusState.toggle()
        handleIncoming(.focusChanged(simulatedFocusState))
    }

    func simulateWifiConnected() {
        let currentSSID = networkObserver.resolveCurrentSSID()
        let ssidToUse = currentSSID.isEmpty ? "Superonline_5G_Fiber" : currentSSID
        handleIncoming(.wifiConnected(ssidToUse))
    }

    func simulateVPNConnected() {
        let sampleDate = Date().addingTimeInterval(-515) // 08:35 uptime
        networkObserver.setSimulatedVPN(tunnelName: "WireGuard (TR-IST)", connectedDate: sampleDate)
        handleIncoming(.vpnConnected("WireGuard (TR-IST)", sampleDate))
    }

    private var simulatedDownloadStep = 0

    func simulateDownload() {
        simulatedDownloadStep = (simulatedDownloadStep % 3) + 1
        let filename: String
        let progress: Double
        let downloaded: Int64
        let total: Int64
        let speed: Double

        switch simulatedDownloadStep {
        case 1:
            filename   = "FinalCutPro_AssetPack_4K.mov"
            progress   = 0.64
            downloaded = 1_374_389_534
            total      = 2_147_483_648
            speed      = 13_421_772.0 // 12.8 MB/s
        case 2:
            filename   = "Xcode_16_Release_Candidate.dmg"
            progress   = 0.82
            downloaded = 4_398_046_511
            total      = 5_368_709_120
            speed      = 25_165_824.0 // 24.0 MB/s
        default:
            filename   = "DynamicNotch_DesignAssets.zip"
            progress   = 0.45
            downloaded = 235_929_600
            total      = 524_288_000
            speed      = 8_388_608.0 // 8.0 MB/s
        }

        let item = DownloadItem(
            id: "sim-download",
            filename: filename,
            progress: progress,
            totalBytes: total,
            downloadedBytes: downloaded,
            speedBytesPerSec: speed,
            sourceFolderName: "Downloads"
        )
        processLiveActivity(.download(item))
    }

    func simulateTimer() {
        timerObserver.startTimer(duration: 120, title: "Çay Molası")
    }

    func simulateNoInternet() {
        networkObserver.simulateNoInternet()
        handleIncoming(.noInternet)
    }

    func simulateAccessibilityPermissionAlert() {
        toggleSpotifyPermissionDialog()
    }

    func simulateScreenshot() {
        screenshotObserver.simulateScreenshot()
    }

    func simulateScreenRecordingToggle() {
        screenRecordingObserver.simulateScreenRecordingToggle()
    }

    // MARK: - Clipboard History Toggle (Cmd + V HotKey)

    func toggleClipboardManager() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        // If clipboard card is already expanded on screen, smoothly toggle it closed!
        if isExpanded {
            if case .clipboard = displayedContent {
                dismissCurrentAlert()
                return
            }
            if let current = currentAlert, case .clipboard = current {
                dismissCurrentAlert()
                return
            }
        }

        let items = clipboardObserver.clipboardItems
        handleIncoming(.clipboard(items))
    }

    func updateClipboardItems(_ newItems: [ClipboardObserver.ClipboardItem]) {
        guard isNotchEnabled && !isScreenLocked else { return }
        guard !newItems.isEmpty else {
            dismissCurrentAlert()
            return
        }
        let updatedContent = NotchState.ContentType.clipboard(newItems)
        currentAlert = updatedContent
        updateExpandedInPlace(to: updatedContent)
    }

    // MARK: - Timer Setup Toggle (Option + Shift + T HotKey)

    func toggleTimerManager() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        // If a countdown timer is already active (running or paused):
        if let activeTimer = timerObserver.activeTimer {
            let timerContent = NotchState.ContentType.timer(activeTimer)

            // If the active timer's expanded card is ALREADY open, smoothly collapse it!
            if isExpanded {
                if case .timer = displayedContent {
                    showCompactWings()
                    return
                }
                // If Timer Setup or an alert is currently showing, dismiss it
                if currentAlert != nil {
                    dismissCurrentAlert()
                }
                // Switch directly to the active timer's expanded card
                dismissTimer?.cancel()
                dismissTimer = nil
                currentAlert = nil
                updateExpandedInPlace(to: timerContent)
                return
            }

            // In compact mode or idle, open the running timer's live activity card!
            expandFromIdleOrCompact(for: timerContent)
            return
        }

        // If no timer is active: toggle Timer Setup modal
        if isExpanded {
            if case .timerSetup = displayedContent {
                dismissCurrentAlert()
                return
            }
            if let current = currentAlert, case .timerSetup = current {
                dismissCurrentAlert()
                return
            }
        }

        handleIncoming(.timerSetup)
    }

    // MARK: - Temporary File Shelf Toggle (Faz 3 Drag & Drop Shelf)

    func toggleShelf() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        if isExpanded {
            if case .shelf = displayedContent {
                dismissShelf()
                return
            }
            if let current = currentAlert, case .shelf = current {
                dismissShelf()
                return
            }
        }

        handleIncoming(.shelf)
    }

    func dismissShelf() {
        guard currentAlert == .shelf else { return }
        dismissTimer?.cancel()
        dismissTimer = nil
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            currentAlert = nil
        }
        isHovered = false
        if let live = activeLiveActivity {
            transitionThroughCutout(to: live, expand: false)
        } else {
            hideCompletely()
        }
    }

    // MARK: - Empty Square Menu (2-Finger Swipe Left / Right Gesture)

    private var contentBeforeSquareMenu: NotchState.ContentType?

    func switchToSquareMenu() {
        guard isNotchEnabled && !isScreenLocked && !isNotchTemporarilyHidden else { return }
        guard isExpanded else { return }
        guard displayedContent != .emptySquareMenu else { return }

        // Remember currently active content so swiping right can restore it seamlessly
        if let current = displayedContent {
            contentBeforeSquareMenu = current
        } else if let live = activeLiveActivity {
            contentBeforeSquareMenu = live
        }

        let screen = ScreenHelper.targetScreen
        let targetSize = effectiveTargetSize(for: .emptySquareMenu, screen: screen)

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        withAnimation(selectedExpandAnimation) {
            state = .expanded(.emptySquareMenu)
            displayedContent = .emptySquareMenu
            expandedContentSize = targetSize
            pillSize = targetSize
        }

        windowController?.expand(
            to: targetSize,
            preserveHoverRetention: true
        )
    }

    func restoreFromSquareMenu() {
        guard isExpanded, displayedContent == .emptySquareMenu else { return }
        guard let previous = contentBeforeSquareMenu ?? activeLiveActivity else {
            if activeLiveActivity != nil {
                showCompactWings()
            } else {
                hideCompletely()
            }
            return
        }

        contentBeforeSquareMenu = nil
        let screen = ScreenHelper.targetScreen
        let targetSize = effectiveTargetSize(for: previous, screen: screen)

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        withAnimation(selectedExpandAnimation) {
            state = .expanded(previous)
            displayedContent = previous
            expandedContentSize = targetSize
            pillSize = targetSize
        }

        windowController?.expand(
            to: targetSize,
            preserveHoverRetention: true
        )
    }

    // MARK: - Quick Note Toggle (Option + Shift + N HotKey)

    func toggleQuickNote() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        if isExpanded {
            if case .quickNote = displayedContent {
                dismissCurrentAlert()
                return
            }
            if let current = currentAlert, case .quickNote = current {
                dismissCurrentAlert()
                return
            }
        }

        handleIncoming(.quickNote)
    }

    func saveQuickNote(text: String) {
        NotesService.shared.createNote(text: text) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let title):
                // Smoothly transition from composer card to confirmation HUD
                self.dismissTimer?.cancel()
                self.dismissTimer = nil
                self.currentAlert = nil
                self.handleIncoming(.quickNoteSaved(title: title))
            case .failure(let error):
                print("[DynamicNotch] Failed to save note to Apple Notes: \(error.localizedDescription)")
                self.dismissCurrentAlert()
            }
        }
    }

    // MARK: - Quick Reminder Toggle (Option + Shift + R HotKey)

    func toggleQuickReminder() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        if isExpanded {
            if case .quickReminder = displayedContent {
                dismissCurrentAlert()
                return
            }
            if let current = currentAlert, case .quickReminder = current {
                dismissCurrentAlert()
                return
            }
        }

        handleIncoming(.quickReminder)
    }

    func saveQuickReminder(text: String, dueOption: ReminderDueOption, isHighPriority: Bool) {
        RemindersService.shared.createReminder(
            title: text,
            dueOption: dueOption,
            isHighPriority: isHighPriority
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let title):
                // Smoothly transition from composer card to confirmation HUD
                self.dismissTimer?.cancel()
                self.dismissTimer = nil
                self.currentAlert = nil
                self.handleIncoming(.quickReminderSaved(title: title))
            case .failure(let error):
                print("[DynamicNotch] Failed to save reminder to Apple Reminders: \(error.localizedDescription)")
                self.dismissCurrentAlert()
            }
        }
    }

    // MARK: - Quick Screenshot & OCR (Quick Actions Dock)

    func triggerQuickScreenshotOCR() {
        guard isNotchEnabled && !isScreenLocked else { return }

        // 1. Temporarily dismiss notch so screen selection is 100% unobstructed
        hideCompletely()

        // 2. Run screencapture asynchronously on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("DynamicNotch_OCR_\(UUID().uuidString).png")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i: interactive select, -r: suppress audio, save to file
            process.arguments = ["-i", "-r", tempURL.path]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }

            guard FileManager.default.fileExists(atPath: tempURL.path),
                  let image = NSImage(contentsOf: tempURL) else {
                // User pressed Esc or cancelled
                return
            }

            // Always write captured image to clipboard
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }

            Task {
                let recognizedText = await VisionOCRService.shared.recognizeText(from: image)

                await MainActor.run {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

                    if let text = recognizedText, !text.isEmpty {
                        // Put recognized text on pasteboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)

                        let item = ScreenshotItem(fileURL: tempURL, thumbnail: image, recognizedText: text)
                        self.handleIncoming(.screenshot(item))
                    } else {
                        let item = ScreenshotItem(fileURL: tempURL, thumbnail: image, recognizedText: nil)
                        self.handleIncoming(.screenshot(item))
                    }
                }
            }
        }
    }

    func toggleCameraMirror() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        if isExpanded {
            if case .cameraMirror = displayedContent {
                showCompactWings()
                return
            }
            if currentAlert != nil {
                dismissCurrentAlert()
            }
            dismissTimer?.cancel()
            dismissTimer = nil
            currentAlert = nil
            updateExpandedInPlace(to: .cameraMirror)
            return
        }

        expandFromIdleOrCompact(for: .cameraMirror)
    }

    func toggleFocusMode() {
        guard isNotchEnabled && !isScreenLocked else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        simulatedFocusState.toggle()
        let newState = simulatedFocusState

        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            tell application "System Events"
                tell its application process "ControlCenter"
                    set focusButtons to (every menu bar item of menu bar 1 whose description contains "Focus" or description contains "Odak" or description contains "Do Not Disturb" or description contains "Rahatsız")
                    if (count of focusButtons) > 0 then
                        click item 1 of focusButtons
                    end if
                end tell
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var errorDict: NSDictionary?
                appleScript.executeAndReturnError(&errorDict)
            }
        }

        handleIncoming(.focusChanged(newState))
    }

    // MARK: - Spotify Permission Dialog Toggle (Option + Shift + S Test HotKey)

    func toggleSpotifyPermissionDialog() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        // If Spotify permission dialog is already displayed, smoothly collapse/dismiss it
        if isExpanded {
            if case .accessibilityPermissionRequired = displayedContent {
                dismissCurrentAlert()
                return
            }
            if let current = currentAlert, case .accessibilityPermissionRequired = current {
                dismissCurrentAlert()
                return
            }
        }

        handleIncoming(.accessibilityPermissionRequired)
    }

    // MARK: - Menu Bar Proximity Dodge (Two-Sided Collision Avoidance)

    /// True when the user moves the mouse into the system menu bar
    /// (left application menus like File/Edit/Help or right status items like Battery/Wi-Fi/Clock).
    /// DynamicNotch politely retracts into the hardware cutout and passes all clicks through to macOS.
    @Published private(set) var isMenuBarDodging: Bool = false
    private var menuBarDodgeDebounceTimer: AnyCancellable? = nil

    func setMenuBarDodging(_ dodging: Bool) {
        menuBarDodgeDebounceTimer?.cancel()
        menuBarDodgeDebounceTimer = nil

        if dodging {
            guard !isMenuBarDodging else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                isMenuBarDodging = true
            }
        } else {
            guard isMenuBarDodging else { return }
            // 180ms gentle settle before un-dodging to prevent jitter when scrubbing menus
            menuBarDodgeDebounceTimer = Just(())
                .delay(for: .milliseconds(180), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        self.isMenuBarDodging = false
                    }
                }
        }
    }

    // MARK: - Global Toggle Hide / Show (Option + Shift + H HotKey)

    @Published var isNotchTemporarilyHidden: Bool = false

    func toggleHideNotch() {
        guard !isScreenLocked else { return }

        if isNotchTemporarilyHidden {
            // Unhide notch -> restore active live activity smoothly
            isNotchTemporarilyHidden = false
            if let active = activeLiveActivity {
                emergeCompactFromIdle(for: active)
            } else {
                // If nothing was playing, briefly show idle compact wings
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let compactSize = NotchPositionCalculator.compactFrame(for: screen).size
                isNotchVisible = true
                withAnimation(SpringConfig.compactAppear) {
                    hasActiveContent = true
                    pillSize = compactSize
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self, self.activeLiveActivity == nil, !self.isExpanded else { return }
                    self.hideCompletely()
                }
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        } else {
            // Hide notch completely into the physical cutout
            isNotchTemporarilyHidden = true
            hideCompletely()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    // MARK: - External Drive Toggle (Option + Shift + E HotKey)

    func toggleExternalDriveManager() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        let drives = ExternalDriveManager.shared.mountedDrives
        guard !drives.isEmpty else {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            return
        }

        let driveContent = NotchState.ContentType.externalDrive(drives)

        if isExpanded {
            if case .externalDrive = displayedContent {
                showCompactWings()
                return
            }
            if currentAlert != nil {
                dismissCurrentAlert()
            }
            dismissTimer?.cancel()
            dismissTimer = nil
            currentAlert = nil
            updateExpandedInPlace(to: driveContent)
            return
        }

        expandFromIdleOrCompact(for: driveContent)
    }

    // MARK: - Calendar Toggle (Option + Shift + C HotKey)

    func toggleCalendarManager() {
        guard isNotchEnabled && !isScreenLocked else { return }
        if isNotchTemporarilyHidden {
            isNotchTemporarilyHidden = false
        }

        if isExpanded {
            if case .calendarEvent = displayedContent {
                showCompactWings()
                return
            }
            if case .calendarAlert = currentAlert {
                dismissCurrentAlert()
                return
            }
        }

        if let event = CalendarManager.shared.activeOrNextEvent {
            let content = NotchState.ContentType.calendarEvent(event)
            if isExpanded {
                dismissTimer?.cancel()
                dismissTimer = nil
                currentAlert = nil
                updateExpandedInPlace(to: content)
            } else {
                expandFromIdleOrCompact(for: content)
            }
            return
        }

        // If no active/upcoming event is detected in EventKit, request access or simulate
        if !CalendarManager.shared.hasAccess {
            CalendarManager.shared.requestAccess { [weak self] granted in
                guard granted, let self else { return }
                if let next = CalendarManager.shared.activeOrNextEvent {
                    self.expandFromIdleOrCompact(for: .calendarEvent(next))
                }
            }
        } else {
            CalendarManager.shared.fetchEvents()
            if let first = CalendarManager.shared.todayEvents.first {
                expandFromIdleOrCompact(for: .calendarEvent(first))
            } else {
                let dummy = CalendarManager.shared.simulateUpcomingMeeting(minutesUntilStart: 10)
                expandFromIdleOrCompact(for: .calendarEvent(dummy))
            }
        }
    }

    func simulateCalendarUpcomingAlert() {
        let dummy = CalendarManager.shared.simulateUpcomingMeeting(minutesUntilStart: 10)
        handleIncoming(.calendarAlert(dummy))
    }

    func simulateCalendarActiveLiveActivity() {
        let dummy = CalendarManager.shared.simulateActiveMeeting()
        handleIncoming(.calendarEvent(dummy))
    }

    // MARK: - Hotspot Actions & Simulation

    func toggleHotspotManager() {
        guard showHotspotBattery else { return }
        if isExpanded {
            if case .hotspot = displayedContent {
                showCompactWings()
                return
            }
            if case .hotspotLowBattery = currentAlert {
                dismissCurrentAlert()
                return
            }
        }

        // Live hardware refresh
        HotspotManager.shared.refreshHotspotState()
        let hotspotToDisplay: HotspotItem
        if let current = HotspotManager.shared.currentHotspot, current.isConnected {
            hotspotToDisplay = current
        } else {
            // ZERO FAKE DATA: Show honest disconnected state with current Wi-Fi network if available!
            hotspotToDisplay = HotspotItem.disconnected(currentWifiSSID: HotspotManager.shared.currentWifiSSID)
        }

        let content = NotchState.ContentType.hotspot(hotspotToDisplay)
        if isExpanded {
            dismissTimer?.cancel()
            dismissTimer = nil
            currentAlert = nil
            updateExpandedInPlace(to: content)
        } else {
            expandFromIdleOrCompact(for: content)
        }
    }

    func simulateHotspotConnected(batteryLevel: Int? = nil) {
        let dummy = HotspotManager.shared.simulateHotspot(batteryLevel: batteryLevel)
        handleIncoming(.hotspot(dummy))
    }

    func simulateHotspotUnknownBattery() {
        let dummy = HotspotManager.shared.simulateHotspotUnknownBattery()
        handleIncoming(.hotspot(dummy))
    }

    func simulateHotspotLowBattery() {
        let dummy = HotspotManager.shared.simulateLowBattery(batteryLevel: 15)
        handleIncoming(.hotspotLowBattery(dummy))
    }

    /// Delegates key window activation to the window controller for keyboard input modals.
    func setKeyFocus(_ enabled: Bool) {
        windowController?.setKeyFocus(enabled)
    }
}
