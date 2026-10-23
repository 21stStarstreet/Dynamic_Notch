// NotchContentRouter.swift
// DynamicNotch / Core / Notch
//
// Maps the current NotchState to the corresponding feature SwiftUI View when
// the notch is expanded (either via mouse hover or a transient Alert).

import SwiftUI
import AVFoundation

struct NotchContentRouter: View {

    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        if let content = viewModel.displayedContent {
            routedView(for: content)
        } else if case .expanded(let content) = viewModel.state {
            routedView(for: content)
        }
    }

    @ViewBuilder
    private func routedView(for content: NotchState.ContentType) -> some View {
        switch content {
        case .nowPlaying(let info):
            NowPlayingView(info: info, observer: viewModel.mediaObserver)

        case .download(let item):
            DownloadProgressView(item: item)

        case .batteryCharging:
            BatteryAlertView(
                type: .charging,
                percentage: viewModel.batteryObserver.percentage
            )

        case .batteryLow:
            BatteryAlertView(
                type: .low,
                percentage: viewModel.batteryObserver.percentage
            )

        case .batteryFull:
            BatteryAlertView(
                type: .full,
                percentage: 100
            )

        case .bluetoothConnected(let name):
            let model = AirPodsModel(deviceName: name)
            if model.supportsFullAnimation {
                AirPodsNotchAlertView(
                    deviceName: name,
                    model: model,
                    battery: viewModel.bluetoothObserver.airPodsBattery(for: name),
                    singleBattery: viewModel.bluetoothObserver.batteryPercentage(for: name)
                )
            } else {
                BluetoothAlertView(
                    deviceName: name,
                    connected: true,
                    batteryPercentage: viewModel.bluetoothObserver.batteryPercentage(for: name)
                )
            }

        case .bluetoothDisconnected(let name):
            BluetoothAlertView(deviceName: name, connected: false)

        case .focusChanged(let isActive):
            FocusAlertView(isActive: isActive)

        case .muted(let isMuted):
            VolumeHUDView(
                volume: viewModel.volumeObserver.volume,
                isMuted: isMuted,
                deviceName: viewModel.volumeObserver.outputDeviceName,
                onToggleMute: { viewModel.toggleMuteFromHUD() },
                onSetVolume: { viewModel.setVolumeFromHUD($0) }
            )

        case .volumeChange(let vol):
            VolumeHUDView(
                volume: vol,
                isMuted: viewModel.volumeObserver.isMuted,
                deviceName: viewModel.volumeObserver.outputDeviceName,
                onToggleMute: { viewModel.toggleMuteFromHUD() },
                onSetVolume: { viewModel.setVolumeFromHUD($0) }
            )

        case .brightnessChange(let b):
            BrightnessHUDView(
                brightness: b,
                screenName: NSScreen.main?.localizedName ?? "Ekran Parlaklığı",
                onSetBrightness: { viewModel.setBrightnessFromHUD($0) }
            )

        case .keyboardBrightnessChange(let b):
            KeyboardBrightnessHUDView(
                brightness: b,
                onSetBrightness: { viewModel.setKeyboardBrightnessFromHUD($0) }
            )

        case .wifiConnected(let ssid):
            NetworkAlertView(ssid: ssid, connected: true, isVPN: false)

        case .wifiDisconnected:
            NetworkAlertView(ssid: nil, connected: false, isVPN: false)

        case .vpnConnected(let name, let date):
            NetworkAlertView(tunnelName: name, connectedDate: date)

        case .screenRecording(let startDate):
            ScreenRecordingLiveActivityView(
                startDate: startDate,
                onStop: { [weak viewModel] in
                    viewModel?.screenRecordingObserver.stopRecording()
                }
            )

        case .timer(let item):
            TimerLiveActivityView(
                item: item,
                observer: viewModel.timerObserver,
                onCancel: {
                    viewModel.cancelTimer()
                }
            )

        case .noInternet:
            NoInternetAlertView(
                onDismiss: { viewModel.dismissCurrentAlert() },
                onSettings: { viewModel.openNetworkSettings() }
            )

        case .clipboard:
            ClipboardView(
                observer: viewModel.clipboardObserver,
                onDismiss: { viewModel.dismissCurrentAlert() },
                onItemsChanged: { newItems in
                    viewModel.updateClipboardItems(newItems)
                }
            )

        case .quickNote:
            QuickNoteComposerView(
                onSave: { noteText in
                    viewModel.saveQuickNote(text: noteText)
                },
                onDismiss: {
                    viewModel.dismissCurrentAlert()
                },
                onSetKeyFocus: { [weak viewModel] enabled in
                    viewModel?.setKeyFocus(enabled)
                }
            )

        case .quickNoteSaved(let title):
            QuickNoteSavedAlertView(
                title: title,
                onDismiss: {
                    viewModel.dismissCurrentAlert()
                }
            )

        case .quickReminder:
            QuickReminderComposerView(
                onSave: { reminderText, dueOption, isHighPriority in
                    viewModel.saveQuickReminder(text: reminderText, dueOption: dueOption, isHighPriority: isHighPriority)
                },
                onDismiss: {
                    viewModel.dismissCurrentAlert()
                },
                onSetKeyFocus: { [weak viewModel] enabled in
                    viewModel?.setKeyFocus(enabled)
                }
            )

        case .quickReminderSaved(let title):
            QuickReminderSavedAlertView(
                title: title,
                onDismiss: {
                    viewModel.dismissCurrentAlert()
                }
            )

        case .timerSetup:
            TimerSetupView(
                observer: viewModel.timerObserver,
                onDismiss: { viewModel.dismissCurrentAlert() },
                onSetKeyFocus: { [weak viewModel] enabled in
                    viewModel?.setKeyFocus(enabled)
                }
            )

        case .screenshot(let item):
            ScreenshotAlertView(
                item: item,
                observer: viewModel.screenshotObserver,
                notchBottomY: viewModel.pillSize.height,
                onDismiss: { viewModel.dismissCurrentAlert() }
            )

        case .shelf:
            ShelfView(
                onDismiss: { viewModel.dismissShelf() }
            )

        case .externalDrive(let drives):
            ExternalDriveView(drives: drives)

        case .externalDriveEjected(let name, let success):
            ExternalDriveEjectedAlertView(driveName: name, success: success)

        case .calendarEvent(let event):
            CalendarEventView(event: event)

        case .calendarAlert(let event):
            CalendarEventAlertView(
                event: event,
                onDismiss: { viewModel.dismissCurrentAlert() }
            )

        case .hotspot(let hotspot):
            HotspotCardView(hotspot: hotspot)

        case .hotspotLowBattery(let hotspot):
            HotspotAlertView(
                hotspot: hotspot,
                onDismiss: { viewModel.dismissCurrentAlert() }
            )

        case .onboarding(let step):
            OnboardingNotchView(
                step: step,
                onStepChange: { nextStep in
                    NotchOnboardingManager.shared.show(step: nextStep)
                },
                onFinish: {
                    NotchOnboardingManager.shared.finishOnboarding()
                }
            )

        case .accessibilityPermissionRequired:
            AccessibilityPermissionAlertView(
                onGrant: { [weak viewModel] in
                    SpotifyAPIService.shared.startAuthFlow()
                    viewModel?.dismissCurrentAlert()
                },
                onDismiss: { [weak viewModel] in
                    viewModel?.dismissCurrentAlert()
                }
            )

        case .spotifyAuthorized:
            SpotifySuccessCheckmarkView()

        case .emptySquareMenu:
            SquareActionMenuView(viewModel: viewModel)

        case .cameraMirror:
            CameraMirrorView(onDismiss: { [weak viewModel] in
                viewModel?.dismissCurrentAlert()
            })

        case .welcomeGreeting:
            WelcomeAnimatedTextView(
                isSingleRound: true,
                onCompletion: {
                    NotchOnboardingManager.shared.finishWelcomeGreeting()
                }
            )
        }
    }
}

// MARK: - Apple Colored App Symbols (Zero Glow, Identical Dimensions 46×46)

struct AppleNotesSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.82, blue: 0.20),
                            Color(red: 0.96, green: 0.65, blue: 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                )

            Image(systemName: "note.text")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleRemindersSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.97),
                            Color(white: 0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.40), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 3.5) {
                    Circle().fill(Color(red: 0.0, green: 0.48, blue: 1.0)).frame(width: 5, height: 5)
                    Capsule().fill(Color.black.opacity(0.32)).frame(width: 18, height: 2.2)
                }
                HStack(spacing: 3.5) {
                    Circle().fill(Color(red: 1.0, green: 0.23, blue: 0.19)).frame(width: 5, height: 5)
                    Capsule().fill(Color.black.opacity(0.32)).frame(width: 18, height: 2.2)
                }
                HStack(spacing: 3.5) {
                    Circle().fill(Color(red: 1.0, green: 0.58, blue: 0.0)).frame(width: 5, height: 5)
                    Capsule().fill(Color.black.opacity(0.32)).frame(width: 18, height: 2.2)
                }
                HStack(spacing: 3.5) {
                    Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 5, height: 5)
                    Capsule().fill(Color.black.opacity(0.32)).frame(width: 18, height: 2.2)
                }
            }
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleSoundSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.56, blue: 0.98),
                            Color(red: 0.05, green: 0.38, blue: 0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                )

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleClipboardSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.72, blue: 0.94),
                            Color(red: 0.02, green: 0.48, blue: 0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleTimerSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.60, blue: 0.0),
                            Color(red: 0.96, green: 0.38, blue: 0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )

            Image(systemName: "timer")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

// MARK: - Phase 3-7 Apple Symbol Views

struct AppleScreenshotSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.69, green: 0.32, blue: 0.87),
                            Color(red: 0.35, green: 0.34, blue: 0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                )

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleMirrorSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.78, blue: 0.35),
                            Color(red: 0.19, green: 0.69, blue: 0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                )

            Image(systemName: "video.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleFocusSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.34, blue: 0.84),
                            Color(red: 0.21, green: 0.20, blue: 0.64)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                )

            Image(systemName: "moon.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleEjectSymbolView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.28, blue: 0.30),
                            Color(red: 0.17, green: 0.17, blue: 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                )

            Image(systemName: "eject.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 46, height: 46)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

struct AppleCalendarSymbolView: View {
    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: Date())
    }

    private var weekdayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: Date()).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(white: 0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                )

            VStack(spacing: 0) {
                // Red top header band
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.23, blue: 0.19))
                    .frame(height: 14)
                    .overlay(
                        Text(weekdayString)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )

                Spacer(minLength: 0)

                // Day number in center
                Text(dayString)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))

                Spacer(minLength: 0)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

// MARK: - Quick Action Menu View (Proportionally Spaced Two-Page Carousel Dock)

struct SquareActionMenuView: View {

    @ObservedObject var viewModel: NotchViewModel
    @State private var selectedPage: Int = 0

    private var metrics: QuickActionMenuMetrics {
        QuickActionMenuGeometryEngine.calculate(screen: ScreenHelper.targetScreen)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Horizontal Carousel Container
            HStack(spacing: 0) {
                pageOne
                    .frame(width: metrics.pageContentWidth)

                pageTwo
                    .frame(width: metrics.pageContentWidth)
            }
            .frame(width: metrics.pageContentWidth, alignment: .leading)
            .offset(x: selectedPage == 0 ? 0 : -metrics.pageContentWidth)
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: selectedPage)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { gesture in
                        if gesture.translation.width < -25 && selectedPage == 0 {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                selectedPage = 1
                            }
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        } else if gesture.translation.width > 25 && selectedPage == 1 {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                selectedPage = 0
                            }
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        } else if gesture.translation.width > 45 && selectedPage == 0 {
                            viewModel.restoreFromSquareMenu()
                        }
                    }
            )

            // Apple Capsule Pagination Dots (● ○)
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        selectedPage = 0
                    }
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Capsule(style: .continuous)
                        .fill(selectedPage == 0 ? Color.white : Color.white.opacity(0.28))
                        .frame(width: selectedPage == 0 ? 14 : 5, height: 5.0)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        selectedPage = 1
                    }
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Capsule(style: .continuous)
                        .fill(selectedPage == 1 ? Color.white : Color.white.opacity(0.28))
                        .frame(width: selectedPage == 1 ? 14 : 5, height: 5.0)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sayfa 1: Günlük Üretkenlik Araçları
    private var pageOne: some View {
        HStack(spacing: metrics.itemSpacing) {
            // 1. Notlar (Apple Notes)
            SquareActionItemView(
                title: "Hızlı Not",
                helpText: "Hızlı Not Ekle (⌥⇧N)",
                itemWidth: metrics.itemWidth
            ) {
                AppleNotesSymbolView()
            } action: {
                viewModel.toggleQuickNote()
            }

            // 2. Anımsatıcı (Apple Reminders)
            SquareActionItemView(
                title: "Anımsatıcı",
                helpText: "Hızlı Anımsatıcı Ekle (⌥⇧R)",
                itemWidth: metrics.itemWidth
            ) {
                AppleRemindersSymbolView()
            } action: {
                viewModel.toggleQuickReminder()
            }

            // 3. Pano Geçmişi (Apple Clipboard)
            SquareActionItemView(
                title: "Pano",
                helpText: "Pano Geçmişi (⌥⇧V)",
                itemWidth: metrics.itemWidth
            ) {
                AppleClipboardSymbolView()
            } action: {
                viewModel.toggleClipboardManager()
            }

            // 4. Zamanlayıcı (Apple Timer / Pomodoro)
            SquareActionItemView(
                title: "Zamanlayıcı",
                helpText: "Zamanlayıcı Kur (⌥⇧T)",
                itemWidth: metrics.itemWidth
            ) {
                AppleTimerSymbolView()
            } action: {
                viewModel.toggleTimerManager()
            }

            // 5. Ses Çıkışı (Apple Sound Route)
            SquareActionItemView(
                title: "Ses Çıkışı",
                helpText: "Ses Giriş ve Çıkışları",
                itemWidth: metrics.itemWidth
            ) {
                AppleSoundSymbolView()
            } action: {
                viewModel.openAudioRoutePicker()
            }
        }
    }

    // MARK: - Sayfa 2: Sistem, Medya & Donanım Araçları
    private var pageTwo: some View {
        HStack(spacing: metrics.itemSpacing) {
            // 1. Ekran Alıntısı & OCR (Faz 3)
            SquareActionItemView(
                title: "Alıntı & OCR",
                helpText: "Ekran Alıntısı & Metin Tanıma",
                itemWidth: metrics.itemWidth
            ) {
                AppleScreenshotSymbolView()
            } action: {
                viewModel.triggerQuickScreenshotOCR()
            }

            // 2. Kamera Aynası (Faz 4)
            SquareActionItemView(
                title: "Ayna",
                helpText: "Hızlı Kamera Kontrolü",
                itemWidth: metrics.itemWidth
            ) {
                AppleMirrorSymbolView()
            } action: {
                viewModel.toggleCameraMirror()
            }

            // 3. Odaklanma Modu (Faz 5)
            SquareActionItemView(
                title: "Odak Modu",
                helpText: "Rahatsız Etmeyin",
                itemWidth: metrics.itemWidth
            ) {
                AppleFocusSymbolView()
            } action: {
                viewModel.toggleFocusMode()
            }

            // 4. Harici Diskleri Çıkar (Faz 6)
            SquareActionItemView(
                title: "Disk Çıkar",
                helpText: "Bağlı Diskleri Güvenle Çıkar",
                itemWidth: metrics.itemWidth
            ) {
                AppleEjectSymbolView()
            } action: {
                viewModel.toggleExternalDriveManager()
            }

            // 5. Takvim & Toplantı (Faz 7)
            SquareActionItemView(
                title: "Takvim",
                helpText: "Yaklaşan Etkinlikler",
                itemWidth: metrics.itemWidth
            ) {
                AppleCalendarSymbolView()
            } action: {
                viewModel.toggleCalendarManager()
            }
        }
    }
}

// MARK: - Square Action Item View (Symbol + Typography Label)

struct SquareActionItemView<SymbolContent: View>: View {

    let title: String
    let helpText: String
    var itemWidth: CGFloat = 66.0
    @ViewBuilder let symbol: () -> SymbolContent
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        } label: {
            VStack(spacing: 6) {
                symbol()
                    .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.06 : 1.0))

                Text(title)
                    .font(.system(size: 10.5, weight: .medium, design: .default))
                    .foregroundColor(isHovered ? .white : .white.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(width: itemWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeOut(duration: 0.08)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Standby Expanded View (Shown on Hover when Idle)

struct StandbyExpandedView: View {

    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Left: Media Quick Control
            Button {
                viewModel.mediaObserver.togglePlayPause()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 42, height: 42)

                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medya Oynatıcı")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Oynatmak için tıkla")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            // Right: Live Battery Pill & Settings Gear
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.batteryObserver.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(viewModel.batteryObserver.isCharging ? .yellow : .green)

                    Text("%\(viewModel.batteryObserver.percentage)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )

                Button {
                    viewModel.onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Screen Recording Views (Live Activity & Compact Wing)

struct ScreenRecordingWingDot: View {
    var size: CGFloat = 8.0
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.notchRed.opacity(isPulsing ? 0.35 : 0.14))
                .frame(width: size + 9.0, height: size + 9.0)
                .scaleEffect(isPulsing ? 1.15 : 0.88)

            Circle()
                .fill(Color.notchRed)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct ScreenRecordingLiveActivityView: View {
    let startDate: Date
    let onStop: () -> Void

    @State private var isHoveringStop = false
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Pulsing recording badge
            ZStack {
                Circle()
                    .fill(Color.notchRed.opacity(pulse ? 0.28 : 0.14))
                    .frame(width: 32, height: 32)
                    .scaleEffect(pulse ? 1.08 : 0.92)

                Circle()
                    .fill(Color.notchRed)
                    .frame(width: 12, height: 12)
            }
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            // Title & Live Elapsed Duration
            VStack(alignment: .leading, spacing: 2) {
                Text("Ekran Kaydediliyor")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(startDate))
                    let hours = Int(elapsed) / 3600
                    let minutes = (Int(elapsed) % 3600) / 60
                    let seconds = Int(elapsed) % 60
                    let formatted = hours > 0
                        ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                        : String(format: "%02d:%02d", minutes, seconds)
                    Text(formatted)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.30))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Tactile Stop Button
            Button(action: onStop) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("Durdur")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isHoveringStop ? Color.notchRed : Color.notchRed.opacity(0.85))
                )
                .shadow(color: Color.notchRed.opacity(isHoveringStop ? 0.45 : 0.20), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringStop = $0 }
        }
    }
}

struct FocusAlertView: View {
    let isActive: Bool

    private var accentColor: Color {
        isActive ? .indigo : .gray
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.22))
                    .frame(width: 34, height: 34)

                Image(systemName: isActive ? "moon.fill" : "moon")
                    .font(.system(size: 17.5, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Rahatsız Etmeyin")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(isActive ? "Odak modu etkin" : "Odak modu kapatıldı")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(isActive ? .indigo.opacity(0.95) : .white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

struct MuteAlertView: View {
    let isMuted: Bool

    private var accentColor: Color {
        isMuted ? .red : .green
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.20))
                    .frame(width: 34, height: 34)

                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 17.5, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(isMuted ? "Sessize Alındı" : "Ses Açıldı")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(isMuted ? "Sistem sesi kapatıldı" : "Sistem sesi etkin")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(isMuted ? .red.opacity(0.90) : .white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Camera Mirror (AVFoundation Live Preview HUD)

final class CameraCaptureManager: NSObject, ObservableObject {
    static let shared = CameraCaptureManager()

    let session = AVCaptureSession()
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var permissionDenied = false

    private var isConfigured = false

    func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
            permissionDenied = false
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    self?.permissionDenied = !granted
                    if granted {
                        self?.startSession()
                    }
                }
            }
        case .denied, .restricted:
            hasPermission = false
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )

        let device = discoverySession.devices.first ?? AVCaptureDevice.default(for: .video)

        if let device = device {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print("[CameraCaptureManager] Unable to add video input: \(error)")
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }

    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.configureSession()
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
}

final class CameraVideoNSView: NSView {
    override func layout() {
        super.layout()
        layer?.frame = bounds
        layer?.sublayers?.forEach { $0.frame = bounds }
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = CameraVideoNSView()
        view.wantsLayer = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}

struct CameraMirrorView: View {
    @ObservedObject private var cameraManager = CameraCaptureManager.shared
    let onDismiss: () -> Void

    @State private var pulseGreen = false

    var body: some View {
        VStack(spacing: 8) {
            // Header bar
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulseGreen ? 1.25 : 0.85)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulseGreen)

                    Text("Kamera Aynası")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    cameraManager.stopSession()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Video Preview Frame
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.black.opacity(0.60))

                if cameraManager.permissionDenied {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.50))

                        Text("Kamera İzni Gerekli")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)

                        Button {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Ayarları Aç")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                } else if cameraManager.isRunning {
                    CameraPreviewLayerView(session: cameraManager.session)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.8)))

                        Text("Kamera Başlatılıyor...")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.60))
                    }
                }
            }
            .frame(width: 250, height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
        }
        .frame(width: 260)
        .onAppear {
            pulseGreen = true
            cameraManager.checkPermissionAndStart()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}

