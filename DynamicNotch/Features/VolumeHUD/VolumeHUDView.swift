// VolumeHUDView.swift
// DynamicNotch / Features / VolumeHUD
//
// Apple-grade Volume HUD with interactive volume scrub bar,
// mute toggle, and horizontal expanding audio route switcher drawer
// featuring both Output and Input (Microphone) controls when expanded.

import SwiftUI

struct VolumeHUDView: View {

    let volume: Float
    var isMuted: Bool = false
    var deviceName: String = VolumeObserver.currentOutputDeviceName
    var onToggleMute: (() -> Void)? = nil
    var onSetVolume: ((Float) -> Void)? = nil

    @ObservedObject private var hudVM = VolumeHUDViewModel.shared
    @ObservedObject private var audioManager = AudioDeviceManager.shared

    @State private var isDraggingBar: Bool = false
    @State private var isHoveringBar: Bool = false
    @State private var isHoveringRouteButton: Bool = false

    @State private var isDraggingInputBar: Bool = false
    @State private var isHoveringInputBar: Bool = false

    private var isEffectiveMuted: Bool {
        isMuted || volume <= 0.005
    }

    private var numericLevel: Int {
        isEffectiveMuted ? 0 : Int(round(min(max(volume, 0.0), 1.0) * 100))
    }

    private var displayDeviceName: String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mac Hoparlörleri" : trimmed
    }

    private var displayInputDeviceName: String {
        let name = audioManager.currentDefaultInputDevice?.name ?? "Dahili Mikrofon"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Dahili Mikrofon" : trimmed
    }

    private var isEffectiveInputMuted: Bool {
        audioManager.isInputMuted || audioManager.inputVolume <= 0.005
    }

    private var numericInputLevel: Int {
        isEffectiveInputMuted ? 0 : Int(round(min(max(audioManager.inputVolume, 0.0), 1.0) * 100))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Pane: Persistent volume controls + Input volume controls when expanded
            volumeControlsView
                .frame(width: hudVM.isAudioRouteExpanded ? 230 : nil)

            // Right Pane: Exact AudioRoutePickerView as in Now Playing (slides in horizontally)
            if hudVM.isAudioRouteExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 0.75)
                    .padding(.horizontal, 14)
                    .transition(.opacity)

                AudioRoutePickerView(accentColor: Color(red: 0.20, green: 0.60, blue: 1.0))
                    .frame(width: 250)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var volumeControlsView: some View {
        VStack(alignment: .leading, spacing: hudVM.isAudioRouteExpanded ? 6 : 9) {
            // MARK: - Output Section
            VStack(alignment: .leading, spacing: 6) {
                // Top Row: Active Output Device Name + Audio Route Button
                HStack(alignment: .center, spacing: 6) {
                    Text(isEffectiveMuted ? "Sessize Alındı" : displayDeviceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.notchTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if isEffectiveMuted {
                        Text(displayDeviceName)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(.notchSubtitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    audioRouteButton
                }

                // Output Row: Speaker Icon + Interactive Scrubber Bar + Numeric Level
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        onToggleMute?()
                    } label: {
                        Image(systemName: volumeIcon)
                            .font(.system(size: 15.0, weight: .semibold))
                            .foregroundColor(isEffectiveMuted ? .notchRed : .white)
                            .frame(width: 22, alignment: .leading)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    InteractiveVolumeSliderBar(
                        progress: isEffectiveMuted ? 0.0 : Double(volume),
                        tint: isEffectiveMuted ? .notchRed : .white,
                        backgroundColor: isEffectiveMuted
                            ? Color.notchRed.opacity(0.28)
                            : Color.white.opacity(0.18),
                        isHighlighted: isDraggingBar || isHoveringBar,
                        onScrub: { newLevel in
                            isDraggingBar = true
                            onSetVolume?(newLevel)
                        },
                        onScrubEnded: {
                            isDraggingBar = false
                        }
                    )
                    .frame(height: 16)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHoveringBar = hovering
                        }
                    }

                    Text("\(numericLevel)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(isEffectiveMuted ? .notchRed : .gray)
                        .frame(width: 28, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }

            // MARK: - Input Section (Microphone Volume Control when Route Drawer is open)
            if hudVM.isAudioRouteExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.75)
                    .padding(.vertical, 2)
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 6) {
                    // Input Header Row: Device Name + Mic Indicator
                    HStack(alignment: .center, spacing: 6) {
                        Text(isEffectiveInputMuted ? "Mikrofon Sessizde" : displayInputDeviceName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.notchTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        Text("GİRİŞ")
                            .font(.system(size: 9.0, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.70))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(Color.white.opacity(0.12))
                            )
                    }

                    // Input Slider Row: Mic Icon + Input Slider Bar + Numeric Level
                    HStack(alignment: .center, spacing: 10) {
                        Button {
                            audioManager.toggleInputMute()
                        } label: {
                            Image(systemName: isEffectiveInputMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 14.0, weight: .semibold))
                                .foregroundColor(isEffectiveInputMuted ? .notchRed : .white)
                                .frame(width: 22, alignment: .leading)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)

                        InteractiveVolumeSliderBar(
                            progress: isEffectiveInputMuted ? 0.0 : Double(audioManager.inputVolume),
                            tint: isEffectiveInputMuted ? .notchRed : .white,
                            backgroundColor: isEffectiveInputMuted
                                ? Color.notchRed.opacity(0.28)
                                : Color.white.opacity(0.18),
                            isHighlighted: isDraggingInputBar || isHoveringInputBar,
                            onScrub: { newLevel in
                                isDraggingInputBar = true
                                audioManager.setDefaultInputVolume(newLevel)
                            },
                            onScrubEnded: {
                                isDraggingInputBar = false
                            }
                        )
                        .frame(height: 16)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHoveringInputBar = hovering
                            }
                        }

                        Text("\(numericInputLevel)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(isEffectiveInputMuted ? .notchRed : .gray)
                            .frame(width: 28, alignment: .trailing)
                            .contentTransition(.numericText())
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    private var audioRouteButton: some View {
        Button {
            hudVM.toggleAudioRoute()
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(hudVM.isAudioRouteExpanded ? Color(red: 0.20, green: 0.60, blue: 1.0) : .white.opacity(isHoveringRouteButton ? 1.0 : 0.65))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(hudVM.isAudioRouteExpanded ? Color(red: 0.20, green: 0.60, blue: 1.0).opacity(0.22) : Color.white.opacity(isHoveringRouteButton ? 0.16 : 0.06))
                )
                .scaleEffect(isHoveringRouteButton ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringRouteButton = isHovering
            }
        }
    }

    private var volumeIcon: String {
        if isEffectiveMuted { return "speaker.slash.fill" }
        if volume < 0.33    { return "speaker.wave.1.fill" }
        if volume < 0.66    { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Interactive Volume Slider Bar

/// Interactive GPU Canvas volume slider bar that supports direct clicking and horizontal dragging.
private struct InteractiveVolumeSliderBar: View {
    let progress: Double
    let tint: Color
    let backgroundColor: Color
    let isHighlighted: Bool
    let onScrub: (Float) -> Void
    let onScrubEnded: () -> Void

    var body: some View {
        Canvas { context, size in
            let barHeight: CGFloat = isHighlighted ? 7.0 : 5.0
            let yOffset = (size.height - barHeight) / 2.0
            let radius = barHeight / 2.0
            let bgRect = CGRect(x: 0, y: yOffset, width: size.width, height: barHeight)

            context.fill(
                Path(roundedRect: bgRect, cornerRadius: radius),
                with: .color(backgroundColor)
            )

            let clamped = CGFloat(min(max(progress, 0.0), 1.0))
            let fillWidth = max(0, size.width * clamped)
            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: yOffset, width: fillWidth, height: barHeight)
                context.fill(
                    Path(roundedRect: fillRect, cornerRadius: radius),
                    with: .color(tint)
                )
            }
        }
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let width = max(geo.size.width, 1)
                                let normalized = Float(min(max(value.location.x / width, 0.0), 1.0))
                                onScrub(normalized)
                            }
                            .onEnded { _ in
                                onScrubEnded()
                            }
                    )
            }
        )
    }
}
