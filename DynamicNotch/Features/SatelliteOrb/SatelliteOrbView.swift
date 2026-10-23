// SatelliteOrbView.swift
// DynamicNotch / Features / SatelliteOrb
//
// Pixel-perfect circular Satellite Orb matching Apple Dynamic Island aesthetic.
// Renders inside a sleek black circle, housing the exact same iconic presentation
// found on the dynamic notch wings, scaled with balanced breathing room.

import SwiftUI

struct SatelliteOrbView: View {

    let content: NotchState.ContentType
    var isDragging: Bool = false

    static let diameter: CGFloat = 28.0

    var body: some View {
        ZStack {
            // Pure black circular backing with subtle glass rim highlight
            Circle()
                .fill(Color.black)
                .overlay(
                    Circle()
                        .stroke(
                            Color.white.opacity(isDragging ? 0.32 : 0.14),
                            lineWidth: 0.85
                        )
                )

            // Content inside the compact circle (matching dynamic notch left-wing design with delicate sizing)
            compactContent(for: content)
                .id(content.kindIdentifier)
                .transition(
                    .scale(scale: 0.60)
                    .combined(with: .opacity)
                )
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: content.kindIdentifier)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .shadow(
            color: Color.black.opacity(isDragging ? 0.55 : 0.38),
            radius: isDragging ? 8 : 6,
            x: 0,
            y: isDragging ? 3 : 2
        )
        .contentShape(Circle())
    }

    // MARK: - Compact Content Switcher (Matches Dynamic Notch Wing Design)

    @ViewBuilder
    private func compactContent(for content: NotchState.ContentType) -> some View {
        switch content {
        case .nowPlaying(let info):
            AlbumArtView(
                image: info.artwork,
                isPlaying: info.isPlaying,
                size: 16.5,
                cornerRadius: 4.5
            )

        case .timer(let item):
            TimelineView(.animation(minimumInterval: 0.25, paused: item.isPaused)) { context in
                let rem: TimeInterval = item.isPaused
                    ? (item.remainingWhenPaused ?? item.remaining)
                    : max(0, item.endDate.timeIntervalSince(context.date))
                let isUrgent = rem <= 60.0
                let isExpired = rem <= 0
                let tintColor: Color = isExpired ? .notchRed : (isUrgent ? .notchRed : .notchOrange)
                let progress = item.totalDuration > 0 ? max(0, min(1, rem / item.totalDuration)) : 1.0

                ZStack {
                    Circle()
                        .stroke(tintColor.opacity(0.22), lineWidth: 1.8)
                        .frame(width: 18.5, height: 18.5)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(tintColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .frame(width: 18.5, height: 18.5)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: item.isPaused ? "pause.fill" : "timer")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(tintColor)
                }
            }

        case .download(let item):
            ZStack {
                Circle()
                    .stroke(Color.notchBlue.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, item.progress))))
                    .stroke(Color.notchBlue, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 18.5, height: 18.5)
                    .rotationEffect(.degrees(-90))

                Image(systemName: DownloadProgressView.fileIcon(for: item.filename))
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(.notchBlue)
            }

        case .keyboardBrightnessChange(let brightness):
            let progress = max(0, min(1, CGFloat(brightness)))
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 18.5, height: 18.5)
                    .rotationEffect(.degrees(-90))

                Image(systemName: progress <= 0.01 ? "keyboard" : "keyboard.fill")
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(.white)
            }

        case .brightnessChange(let brightness):
            let progress = max(0, min(1, CGFloat(brightness)))
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 18.5, height: 18.5)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(.white)
            }

        case .volumeChange(let vol):
            let progress = max(0, min(1, CGFloat(vol)))
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 18.5, height: 18.5)
                    .rotationEffect(.degrees(-90))

                Image(systemName: vol <= 0.005 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(.white)
            }

        case .muted:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(.notchRed)
            }

        case .externalDrive(let drives):
            if let drive = drives.first {
                ZStack {
                    Circle()
                        .fill(drive.driveType.accentColor.opacity(0.20))
                        .frame(width: 18.5, height: 18.5)

                    Image(systemName: drive.driveType.iconName)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(drive.driveType.accentColor)
                }
            }

        case .externalDriveEjected:
            ZStack {
                Circle()
                    .fill(Color.notchGreen.opacity(0.20))
                    .frame(width: 18.5, height: 18.5)

                Image(systemName: "eject.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(.notchGreen)
            }

        case .calendarEvent(let event), .calendarAlert(let event):
            let accent = event.conferencePlatform?.accentColor ?? event.calendarColor
            let progress = event.progress
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                if event.isHappeningNow {
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(Color.notchGreen, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .frame(width: 18.5, height: 18.5)
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: event.conferencePlatform?.iconName ?? "calendar")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(event.isHappeningNow ? .notchGreen : accent)
            }

        case .hotspot(let hotspot), .hotspotLowBattery(let hotspot):
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 1.8)
                    .frame(width: 18.5, height: 18.5)

                Circle()
                    .trim(from: 0, to: CGFloat(hotspot.batteryFraction))
                    .stroke(hotspot.batteryColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 18.5, height: 18.5)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "personalhotspot")
                    .font(.system(size: 8.0, weight: .semibold))
                    .foregroundColor(hotspot.batteryColor)
            }

        case .screenRecording:
            ScreenRecordingWingDot(size: 7.5)

        case .batteryCharging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 11.0, weight: .bold))
                .foregroundColor(.notchGreen)

        case .batteryFull:
            Image(systemName: "battery.100.bolt")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.notchGreen)

        case .batteryLow:
            Image(systemName: "battery.25")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(.notchRed)

        case .wifiConnected:
            Image(systemName: "wifi")
                .font(.system(size: 11.0, weight: .semibold))
                .foregroundColor(.notchGreen)

        case .wifiDisconnected:
            Image(systemName: "wifi.slash")
                .font(.system(size: 11.0, weight: .semibold))
                .foregroundColor(.notchRed)

        case .noInternet:
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 11.0, weight: .semibold))
                .foregroundColor(Color(red: 0.98, green: 0.58, blue: 0.12))

        case .bluetoothConnected(let name):
            BluetoothDeviceIconView(deviceName: name, fontSize: 10.0)
                .foregroundColor(.notchBlue)

        case .bluetoothDisconnected(let name):
            BluetoothDeviceIconView(deviceName: name, fontSize: 10.0)
                .foregroundColor(.white.opacity(0.6))

        case .vpnConnected:
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.notchIndigo)

        case .focusChanged(let isActive):
            Image(systemName: isActive ? "moon.fill" : "moon")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(isActive ? .notchIndigo : .white.opacity(0.6))

        case .screenshot:
            Image(systemName: "camera.fill")
                .font(.system(size: 10.0, weight: .semibold))
                .foregroundColor(.white)

        case .clipboard:
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.notchBlue)

        case .shelf:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 10.0, weight: .semibold))
                .foregroundColor(Color(red: 0.22, green: 0.62, blue: 1.0))

        default:
            Circle()
                .fill(Color.notchGreen)
                .frame(width: 7, height: 7)
        }
    }
}
