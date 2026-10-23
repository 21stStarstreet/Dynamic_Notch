// BluetoothAlertView.swift
// DynamicNotch / Features / Bluetooth
//
// Displays Bluetooth device connection and disconnection banners.
//
// Engineering detail
// ──────────────────
// Apple's SF Symbols library does NOT include a symbol named "bluetooth"
// (due to Bluetooth SIG trademark rules), so `Image(systemName: "bluetooth")`
// silently renders blank on macOS!
// We solve this by:
//   1. Selecting device-specific SF Symbols for known peripherals (AirPods,
//      headphones, keyboards, mice, controllers).
//   2. Providing a custom vector `BluetoothRuneIcon` Path for generic devices.

import SwiftUI

struct BluetoothAlertView: View {

    let deviceName: String
    let connected: Bool
    var batteryPercentage: Int? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill((connected ? Color.white : Color.gray).opacity(0.14))
                    .frame(width: 34, height: 34)

                deviceIcon
                    .foregroundColor(connected ? .white : .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(connected ? "Bağlandı" : "Bağlantı Kesildi")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.notchSubtitle)
                    .lineLimit(1)

                Text(deviceName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.notchTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 10)

            if connected, let batteryPercentage {
                CircularBatteryView(percentage: batteryPercentage, size: 32, lineWidth: 3.0)
            } else {
                Circle()
                    .fill(connected ? Color.notchGreen : Color.white.opacity(0.28))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var deviceIcon: some View {
        BluetoothDeviceIconView(deviceName: deviceName, fontSize: 18)
    }
}

/// Reusable Bluetooth device icon (AirPods, headphones, keyboard, mouse, trackpad, speaker, controller, or vector Bluetooth rune).
struct BluetoothDeviceIconView: View {
    let deviceName: String
    var fontSize: CGFloat = 18

    var body: some View {
        let lower = deviceName.lowercased()
        if lower.contains("airpods max") {
            Image(systemName: "airpodsmax")
                .font(.system(size: fontSize, weight: .semibold))
        } else if lower.contains("airpods pro") {
            Image(systemName: "airpodspro")
                .font(.system(size: fontSize, weight: .semibold))
        } else if lower.contains("airpods") {
            Image(systemName: "airpods")
                .font(.system(size: fontSize, weight: .semibold))
        } else if lower.contains("headphone") || lower.contains("headset") || lower.contains("kulaklık") || lower.contains("sony") || lower.contains("bose") || lower.contains("beats") {
            Image(systemName: "headphones")
                .font(.system(size: fontSize, weight: .semibold))
        } else if lower.contains("keyboard") || lower.contains("klavye") {
            Image(systemName: "keyboard.fill")
                .font(.system(size: fontSize - 0.5, weight: .semibold))
        } else if lower.contains("trackpad") {
            Image(systemName: "trackpad.fill")
                .font(.system(size: fontSize - 0.5, weight: .semibold))
        } else if lower.contains("mouse") || lower.contains("fare") {
            Image(systemName: "magicmouse.fill")
                .font(.system(size: fontSize - 0.5, weight: .semibold))
        } else if lower.contains("speaker") || lower.contains("hoparlör") || lower.contains("homepod") {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: fontSize - 0.5, weight: .semibold))
        } else if lower.contains("controller") || lower.contains("gamepad") || lower.contains("dualsense") || lower.contains("xbox") {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: fontSize - 0.5, weight: .semibold))
        } else {
            BluetoothRuneShape()
                .stroke(style: StrokeStyle(lineWidth: fontSize >= 15 ? 2.0 : 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: fontSize * 0.68, height: fontSize * 1.08)
        }
    }
}

/// Crisp vector path of the classic Bluetooth rune symbol.
private struct BluetoothRuneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let midX = w * 0.50
        let midY = h * 0.50

        // Spine
        path.move(to: CGPoint(x: midX, y: 0))
        path.addLine(to: CGPoint(x: midX, y: h))

        // Upper & lower triangles
        path.move(to: CGPoint(x: 0, y: h * 0.25))
        path.addLine(to: CGPoint(x: w, y: h * 0.75))
        path.addLine(to: CGPoint(x: midX, y: h))

        path.move(to: CGPoint(x: 0, y: h * 0.75))
        path.addLine(to: CGPoint(x: w, y: h * 0.25))
        path.addLine(to: CGPoint(x: midX, y: 0))

        let _ = midY
        return path
    }
}
