// AudioRoutePickerView.swift
// DynamicNotch / Features / AudioRoute
//
// Apple-grade Audio Route Picker drawer for switching audio output and input endpoints
// directly from the expanded notch with tactile haptic and visual feedback.

import SwiftUI
import CoreAudio

struct AudioRoutePickerView: View {

    @ObservedObject private var manager = AudioDeviceManager.shared
    var accentColor: Color = Color(red: 0.20, green: 0.60, blue: 1.0) // Apple System Blue fallback
    var onSelected: (() -> Void)? = nil

    @State private var selectedTab: AudioDeviceDirection = .output
    @State private var hoveredDeviceId: AudioObjectID? = nil
    @State private var switchingDeviceId: AudioObjectID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with Direction Segmented Control
            HStack(spacing: 8) {
                Image(systemName: selectedTab == .output ? "airplayaudio" : "mic.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor)
                    .contentTransition(.symbolEffect(.replace))

                Text(selectedTab == .output ? "SES ÇIKIŞI" : "SES GİRİŞİ")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(0.6)

                Spacer()

                // Segmented Tab Picker: [ Çıkış ] [ Giriş ]
                HStack(spacing: 2) {
                    ForEach(AudioDeviceDirection.allCases) { dir in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                selectedTab = dir
                            }
                        } label: {
                            Text(dir.rawValue)
                                .font(.system(size: 9.5, weight: selectedTab == dir ? .semibold : .medium))
                                .foregroundColor(selectedTab == dir ? .white : .white.opacity(0.45))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(
                                    selectedTab == dir
                                        ? Capsule().fill(Color.white.opacity(0.18))
                                        : Capsule().fill(Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // Devices List
            let devices = (selectedTab == .output) ? manager.outputDevices : manager.inputDevices
            VStack(spacing: 4) {
                ForEach(devices) { device in
                    deviceRow(device: device)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deviceRow(device: AudioDeviceItem) -> some View {
        let isSelected = device.isCurrentDefault
        let isHovered = (hoveredDeviceId == device.id)
        let isSwitching = (switchingDeviceId == device.id)

        return Button {
            guard !device.isCurrentDefault else { return }
            switchingDeviceId = device.id

            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                if device.isInput {
                    _ = manager.setDefaultInputDevice(device)
                } else {
                    _ = manager.setDefaultOutputDevice(device)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if switchingDeviceId == device.id {
                        switchingDeviceId = nil
                    }
                }
                onSelected?()
            }
        } label: {
            HStack(spacing: 10) {
                // Device Icon with frosted badge
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor.opacity(0.20) : Color.white.opacity(0.08))
                        .frame(width: 24, height: 24)

                    Image(systemName: device.sfSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? accentColor : .white.opacity(0.85))
                }

                // Device Name
                Text(device.name)
                    .font(.system(size: 12.0, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                // Selection / Status indicator
                if isSwitching {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(accentColor)
                        .frame(width: 16, height: 16)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(accentColor)
                        .frame(width: 16, height: 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredDeviceId = hovering ? device.id : nil
            }
        }
    }
}
