// NotchContentRouter.swift
// DynamicNotch / Core / Notch
//
// Maps the current NotchState to the corresponding feature SwiftUI View when
// the notch is expanded (either via mouse hover or a transient Alert).

import SwiftUI

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

// MARK: - Quick Action Menu View (Proportionally Spaced Apple Action Dock)

struct SquareActionMenuView: View {

    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 16) {
            // 1. Notlar (Apple Notes)
            SquareActionItemView(
                title: "Hızlı Not",
                helpText: "Hızlı Not Ekle (⌥⇧N)"
            ) {
                AppleNotesSymbolView()
            } action: {
                viewModel.toggleQuickNote()
            }

            // 2. Anımsatıcı (Apple Reminders)
            SquareActionItemView(
                title: "Anımsatıcı",
                helpText: "Hızlı Anımsatıcı Ekle (⌥⇧R)"
            ) {
                AppleRemindersSymbolView()
            } action: {
                viewModel.toggleQuickReminder()
            }

            // 3. Ses Çıkışı (Apple Sound Route)
            SquareActionItemView(
                title: "Ses Çıkışı",
                helpText: "Ses Giriş ve Çıkışları"
            ) {
                AppleSoundSymbolView()
            } action: {
                viewModel.openAudioRoutePicker()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Square Action Item View (Symbol + Typography Label)

struct SquareActionItemView<SymbolContent: View>: View {

    let title: String
    let helpText: String
    @ViewBuilder let symbol: () -> SymbolContent
    let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        } label: {
            VStack(spacing: 5) {
                symbol()
                    .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.06 : 1.0))

                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(isHovered ? .white : .white.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(width: 66)
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
