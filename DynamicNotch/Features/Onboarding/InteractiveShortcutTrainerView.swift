// InteractiveShortcutTrainerView.swift
// DynamicNotch / Features / Onboarding / Views
//
// Apple-grade shortcut trainer embedded directly into the Dynamic Notch
// onboarding flow. Allows users to test essential global shortcuts (Quick Note, Calendar,
// Timer, External Drives, and Hide/Show Notch) one by one with live keystroke illumination,
// physical keycap spring dynamics, and an animated standalone vector checkmark completion.

import SwiftUI
import AppKit

// MARK: - Notification for Hotkey Interception Bridge

extension Notification.Name {
    static let notchShortcutTriggered = Notification.Name("DynamicNotch.shortcutTriggered")
}

// MARK: - Interactive Shortcut Item Model

struct InteractiveShortcutItem: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let gradientColors: [Color]
    let keyLetter: String
    let keyCode: UInt16
    let actionKey: String
}

// MARK: - Apple Checkmark Mask Path
// Precise stroke centerline matching Apple's SF Symbol "checkmark" geometry.

struct AppleCheckmarkMaskPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Precise centerline coordinates following Apple's SF Symbol "checkmark" at bold weight:
        // Left leg starts top-left, sweeps down to vertex, then long right leg sweeps up to top-right.
        let start = CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.40)
        let vertex = CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.82)
        let end = CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.10)

        path.move(to: start)
        path.addLine(to: vertex)
        path.addLine(to: end)
        return path
    }
}

// MARK: - Animated Vector Checkmark View
// Native Apple SF Symbol checkmark revealed via a high-velocity initial stroke
// that smoothly decelerates into the final tip. Zero blur, zero glow, zero background plate.

struct AnimatedVectorCheckmarkView: View {
    @State private var strokeProgress: CGFloat = 0.0
    @State private var isFullyDrawn: Bool = false

    private let appleGreen = Color(nsColor: .systemGreen)

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(appleGreen)
            .mask {
                if isFullyDrawn {
                    Rectangle()
                } else {
                    AppleCheckmarkMaskPath()
                        .trim(from: 0, to: strokeProgress)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .frame(width: 44, height: 38)
            .onAppear {
                strokeProgress = 0.0
                isFullyDrawn = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    withAnimation(.timingCurve(0.15, 0.95, 0.20, 1.0, duration: 0.48)) {
                        strokeProgress = 1.0
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.54) {
                    isFullyDrawn = true
                }
            }
    }
}

// MARK: - InteractiveShortcutTrainerView

struct InteractiveShortcutTrainerView: View {

    var onProceed: (() -> Void)? = nil
    var onAllCompletedChanged: ((Bool) -> Void)? = nil

    @State private var currentIndex: Int = 0
    @State private var completedKeys: Set<String> = []
    @State private var isOptionPressed: Bool = false
    @State private var isShiftPressed: Bool = false
    @State private var isTargetKeyPressed: Bool = false
    @State private var isSuccessBurst: Bool = false
    @State private var isAllCompleted: Bool = false
    @State private var isCopied: Bool = false

    @State private var localMonitor: Any? = nil
    @State private var globalMonitor: Any? = nil

    private let shortcuts: [InteractiveShortcutItem] = [
        InteractiveShortcutItem(
            id: "quickNote",
            name: "Hızlı Not",
            subtitle: "Çentikte anında Apple Notu oluşturun ve kaydedin",
            symbol: "note.text",
            gradientColors: [Color(red: 0.98, green: 0.76, blue: 0.28), Color(red: 0.86, green: 0.54, blue: 0.10)],
            keyLetter: "N",
            keyCode: 45, // kVK_ANSI_N
            actionKey: "N"
        ),
        InteractiveShortcutItem(
            id: "quickReminder",
            name: "Hızlı Anımsatıcı",
            subtitle: "Apple Anımsatıcılar'a çentikten doğrudan görev ekleyin",
            symbol: "checklist",
            gradientColors: [Color(red: 0.35, green: 0.65, blue: 1.0), Color(red: 0.15, green: 0.45, blue: 0.90)],
            keyLetter: "R",
            keyCode: 15, // kVK_ANSI_R
            actionKey: "R"
        ),
        InteractiveShortcutItem(
            id: "clipboard",
            name: "Pano Geçmişi",
            subtitle: "Kopyalanan son metin ve içerikleri çentikte görüntüleyin",
            symbol: "doc.on.clipboard.fill",
            gradientColors: [Color(red: 0.65, green: 0.40, blue: 0.95), Color(red: 0.45, green: 0.20, blue: 0.85)],
            keyLetter: "V",
            keyCode: 9, // kVK_ANSI_V
            actionKey: "V"
        ),
        InteractiveShortcutItem(
            id: "calendar",
            name: "Takvim Etkinlikleri",
            subtitle: "Günün toplantılarını ve takvim etkinliklerini görün",
            symbol: "calendar",
            gradientColors: [Color(red: 1.0, green: 0.32, blue: 0.32), Color(red: 0.90, green: 0.18, blue: 0.24)],
            keyLetter: "C",
            keyCode: 8, // kVK_ANSI_C
            actionKey: "C"
        ),
        InteractiveShortcutItem(
            id: "timer",
            name: "Zamanlayıcı & Geri Sayım",
            subtitle: "Hızlı zamanlayıcı ve odaklanma süresi başlatın",
            symbol: "timer",
            gradientColors: [Color(red: 1.0, green: 0.62, blue: 0.10), Color(red: 0.95, green: 0.45, blue: 0.05)],
            keyLetter: "T",
            keyCode: 17, // kVK_ANSI_T
            actionKey: "T"
        ),
        InteractiveShortcutItem(
            id: "externalDrive",
            name: "Harici Diskler",
            subtitle: "Bağlı USB sürücüleri izleyin ve güvenle çıkarın",
            symbol: "externaldrive.fill",
            gradientColors: [Color(red: 0.20, green: 0.82, blue: 0.75), Color(red: 0.10, green: 0.65, blue: 0.70)],
            keyLetter: "E",
            keyCode: 14, // kVK_ANSI_E
            actionKey: "E"
        ),
        InteractiveShortcutItem(
            id: "hotspot",
            name: "Kişisel Erişim Noktası",
            subtitle: "iPhone Hotspot bağlantısını ve şarjını çentikte takip edin",
            symbol: "personalhotspot",
            gradientColors: [Color(red: 0.25, green: 0.85, blue: 0.45), Color(red: 0.10, green: 0.65, blue: 0.30)],
            keyLetter: "P",
            keyCode: 35, // kVK_ANSI_P
            actionKey: "P"
        ),
        InteractiveShortcutItem(
            id: "hideNotch",
            name: "Çentiği Gizle / Göster",
            subtitle: "Çentiği dilediğiniz an geçici olarak gizleyin veya açın",
            symbol: "eye.slash.fill",
            gradientColors: [Color(red: 0.40, green: 0.45, blue: 0.95), Color(red: 0.65, green: 0.35, blue: 0.90)],
            keyLetter: "H",
            keyCode: 4, // kVK_ANSI_H
            actionKey: "H"
        )
    ]

    private var currentItem: InteractiveShortcutItem {
        shortcuts[currentIndex]
    }

    private var isCurrentCompleted: Bool {
        completedKeys.contains(currentItem.id)
    }

    var body: some View {
        Group {
            if isAllCompleted {
                completionCelebrationView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94)),
                        removal: .opacity
                    ))
            } else {
                shortcutTrainerView
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 1.04))
                    ))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            setupMonitors()
            NotchViewModel.shared?.setKeyFocus(true)
        }
        .onDisappear {
            teardownMonitors()
            NotchViewModel.shared?.setKeyFocus(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchShortcutTriggered)) { notif in
            guard !isAllCompleted else { return }
            guard let key = notif.userInfo?["key"] as? String else { return }
            if key.uppercased() == currentItem.actionKey.uppercased() {
                triggerSuccess(for: currentItem.id)
            }
        }
    }

    // MARK: - Shortcut Trainer State View

    private var shortcutTrainerView: some View {
        VStack(spacing: 8) {

            // MARK: - Top Meta Row (Clean Step Counter - No 0/5 denendi)
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Kısayol \(currentIndex + 1) / \(shortcuts.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.80))
                .padding(.horizontal, 4)

                Spacer()
            }
            .padding(.horizontal, 2)

            // MARK: - Hero Feature Card (Icon + Title + Subtitle)
            HStack(spacing: 10) {
                // Feature Squircle Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: currentItem.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(color: currentItem.gradientColors[0].opacity(0.35), radius: 4, y: 1.5)

                    Image(systemName: currentItem.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(currentItem.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        if isCurrentCompleted {
                            HStack(spacing: 2.5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Denendi")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(Color(red: 0.20, green: 0.85, blue: 0.45))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.20, green: 0.85, blue: 0.45).opacity(0.16))
                            )
                        }
                    }

                    Text(currentItem.subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Previous / Next Mini Arrows
                HStack(spacing: 3) {
                    Button {
                        navigate(direction: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(currentIndex > 0 ? 0.75 : 0.25))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex == 0)

                    Button {
                        navigate(direction: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(currentIndex < shortcuts.count - 1 ? 0.75 : 0.25))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex == shortcuts.count - 1)
                }
            }
            .padding(.horizontal, 2)

            // MARK: - Interactive Keycaps Tray (No "Test Et" Button)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isSuccessBurst
                                    ? Color(red: 0.20, green: 0.85, blue: 0.45).opacity(0.70)
                                    : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                    )

                HStack(spacing: 8) {
                    // Option Keycap
                    AppleKeycapView(
                        symbol: "⌥",
                        label: "Option",
                        isPressed: isOptionPressed,
                        isSuccess: isSuccessBurst,
                        accentColor: currentItem.gradientColors[0]
                    )

                    Text("+")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))

                    // Shift Keycap
                    AppleKeycapView(
                        symbol: "⇧",
                        label: "Shift",
                        isPressed: isShiftPressed,
                        isSuccess: isSuccessBurst,
                        accentColor: currentItem.gradientColors[0]
                    )

                    Text("+")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))

                    // Target Letter Keycap (N, C, T, E, H)
                    AppleKeycapView(
                        symbol: currentItem.keyLetter,
                        label: nil,
                        isPressed: isTargetKeyPressed || (isOptionPressed && isShiftPressed && isSuccessBurst),
                        isSuccess: isSuccessBurst,
                        accentColor: currentItem.gradientColors[0]
                    )

                    Spacer(minLength: 6)

                    // Success Feedback Indicator
                    if isSuccessBurst {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.20, green: 0.85, blue: 0.45))
                            Text("Harika!")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.20, green: 0.85, blue: 0.45))
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .onTapGesture {
                // Allows clicking on the keycap tray to test without needing a "Test Et" button
                triggerSuccess(for: currentItem.id)
            }

            // MARK: - Mini Pagination Dots Row
            HStack(spacing: 5) {
                ForEach(0..<shortcuts.count, id: \.self) { idx in
                    Circle()
                        .fill(
                            completedKeys.contains(shortcuts[idx].id)
                                ? Color(red: 0.20, green: 0.85, blue: 0.45)
                                : (idx == currentIndex ? Color.white : Color.white.opacity(0.25))
                        )
                        .frame(width: idx == currentIndex ? 7 : 5, height: idx == currentIndex ? 7 : 5)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                currentIndex = idx
                            }
                        }
                }
            }
            .padding(.top, 1)
        }
    }

    // MARK: - Completion Celebration View
    // Pure animated vector checkmark without any background plate, followed by copy & proceed actions.

    private var completionCelebrationView: some View {
        VStack(spacing: 9) {
            // Standalone Animated Vector Checkmark (like Welcome handwriting, NO background plate)
            AnimatedVectorCheckmarkView()
                .padding(.top, 2)

            // Heading & Subtitle
            VStack(spacing: 2) {
                Text("Tüm Kısayollar Başarıyla Denendi!")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Artık çentik özelliklerini klavyenizden tek dokunuşla yönetebilirsiniz.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            // Action Buttons: [ Tüm Kısayolları Kopyala ] and [ Geç ]
            HStack(spacing: 10) {
                // 1. Copy All Shortcuts Button
                Button {
                    copyAllShortcuts()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))

                        Text(isCopied ? "Kopyalandı!" : "Tüm kısayolları kopyala")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isCopied ? Color(red: 0.20, green: 0.85, blue: 0.45) : .white.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isCopied ? Color(red: 0.20, green: 0.85, blue: 0.45).opacity(0.16) : Color.white.opacity(0.10))
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isCopied ? Color(red: 0.20, green: 0.85, blue: 0.45).opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                        }
                    )
                }
                .buttonStyle(.plain)

                // 2. Proceed / Skip Button ("Geç")
                Button {
                    onProceed?()
                } label: {
                    HStack(spacing: 5) {
                        Text("Geç")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.20, green: 0.85, blue: 0.45),
                                            Color(red: 0.15, green: 0.70, blue: 0.35)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        }
                    )
                    .shadow(color: Color(red: 0.20, green: 0.85, blue: 0.45).opacity(0.35), radius: 6, y: 1.5)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Navigation

    private func navigate(direction: Int) {
        let newIdx = currentIndex + direction
        guard newIdx >= 0 && newIdx < shortcuts.count else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            currentIndex = newIdx
            isSuccessBurst = false
            isTargetKeyPressed = false
        }
    }

    // MARK: - Success Trigger & Transition

    private func triggerSuccess(for id: String) {
        guard !isSuccessBurst else { return }

        isTargetKeyPressed = true
        isSuccessBurst = true
        completedKeys.insert(id)

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // Automatically advance to the next shortcut after 0.75s or finish if all done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isSuccessBurst = false
                isTargetKeyPressed = false
                if completedKeys.count == shortcuts.count {
                    isAllCompleted = true
                    onAllCompletedChanged?(true)
                } else if currentIndex + 1 < shortcuts.count {
                    currentIndex += 1
                }
            }
        }
    }

    // MARK: - Copy All Shortcuts to Clipboard

    private func copyAllShortcuts() {
        let text = """
DynamicNotch Klavye Kısayolları:
• ⌥ + ⇧ + N  ➔  Hızlı Not (Apple Notları)
• ⌥ + ⇧ + R  ➔  Hızlı Anımsatıcı (Apple Anımsatıcılar)
• ⌥ + ⇧ + V  ➔  Pano Geçmişi (Clipboard)
• ⌥ + ⇧ + C  ➔  Takvim Etkinlikleri
• ⌥ + ⇧ + T  ➔  Zamanlayıcı & Geri Sayım
• ⌥ + ⇧ + E  ➔  Harici Diskler
• ⌥ + ⇧ + P  ➔  Kişisel Erişim Noktası (Hotspot)
• ⌥ + ⇧ + H  ➔  Çentiği Gizle / Göster
"""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isCopied = false
            }
        }
    }

    // MARK: - Keyboard Monitoring

    private func setupMonitors() {
        // Local Monitor: captures key events when notch panel is key window
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handleKeyEvent(event)
            return event
        }

        // Global Monitor: captures modifier flags even if another app is active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { event in
            DispatchQueue.main.async {
                self.isOptionPressed = event.modifierFlags.contains(.option)
                self.isShiftPressed = event.modifierFlags.contains(.shift)
            }
        }
    }

    private func teardownMonitors() {
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard !isAllCompleted else { return }

        DispatchQueue.main.async {
            self.isOptionPressed = event.modifierFlags.contains(.option)
            self.isShiftPressed = event.modifierFlags.contains(.shift)

            if event.type == .keyDown {
                let isOptShift = event.modifierFlags.contains(.option) && event.modifierFlags.contains(.shift)
                if isOptShift && event.keyCode == self.currentItem.keyCode {
                    self.triggerSuccess(for: self.currentItem.id)
                }
            }
        }
    }
}

// MARK: - Apple Keycap View

struct AppleKeycapView: View {
    let symbol: String
    let label: String?
    let isPressed: Bool
    let isSuccess: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))

            if let label = label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
        }
        .foregroundColor(
            isSuccess
                ? Color(red: 0.08, green: 0.28, blue: 0.12)
                : (isPressed ? .white : .white.opacity(0.88))
        )
        .frame(height: 25)
        .padding(.horizontal, label != nil ? 7 : 8)
        .background(
            ZStack {
                if isSuccess {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.90, blue: 0.50), Color(red: 0.20, green: 0.75, blue: 0.38)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.80), lineWidth: 1)
                        )
                } else if isPressed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.90), accentColor.opacity(0.60)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.70), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            }
        )
        .shadow(
            color: isSuccess
                ? Color.green.opacity(0.45)
                : (isPressed ? accentColor.opacity(0.40) : Color.black.opacity(0.25)),
            radius: isSuccess || isPressed ? 4 : 2,
            y: isPressed ? 0.5 : 1
        )
        .scaleEffect(isPressed ? 0.94 : (isSuccess ? 1.04 : 1.0))
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isPressed)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSuccess)
    }
}
