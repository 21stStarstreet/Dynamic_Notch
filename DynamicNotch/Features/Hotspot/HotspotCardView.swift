// HotspotCardView.swift
// DynamicNotch / Features / Hotspot
//
// Apple-grade expanded interactive card for Personal Hotspot Live Activities.
// Displays tethered iPhone/iPad name, cellular network type (5G/LTE),
// signal bars, dynamic battery fill gauge, and connection duration.

import SwiftUI
import AppKit

struct HotspotCardView: View {

    let hotspot: HotspotItem
    @State private var isActionHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // Header Row: Hotspot icon + Category Title + 5G/LTE Signal Badge
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "personalhotspot")
                    .font(.system(size: 13.0, weight: .semibold))
                    .foregroundColor(.notchGreen)

                Text("KİŞİSEL ERİŞİM NOKTASI")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(0.6)

                Spacer()

                // Cellular Technology & Signal Bars Badge or Connection State
                if let cell = hotspot.cellularType, let bars = hotspot.signalBars {
                    HStack(spacing: 5) {
                        Text(cell)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))

                        if #available(macOS 13.0, *) {
                            Image(systemName: "cellularbars", variableValue: Double(bars) / 4.0)
                                .font(.system(size: 9.0, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                        } else {
                            Image(systemName: "cellularbars")
                                .font(.system(size: 9.0, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                } else if hotspot.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.notchGreen)
                            .frame(width: 5, height: 5)

                        Text("Bağlı")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.90))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.notchGreen.opacity(0.15))
                    )
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.white.opacity(0.40))
                            .frame(width: 5, height: 5)

                        Text("Bağlı Değil")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
            }

            // Main Info Block: Device Name & Battery Telemetry
            HStack(alignment: .center, spacing: 14) {
                // Large Tactile Apple Battery Capsule
                ZStack(alignment: .leading) {
                    // Outer Battery Shell
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.6)
                        .frame(width: 44, height: 22)

                    // Battery Terminal Nub
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 4, height: 8)
                        .offset(x: 45)

                    // Liquid Fill Gauge
                    if let _ = hotspot.batteryLevel {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(hotspot.batteryColor)
                            .frame(width: max(4, 38.0 * CGFloat(hotspot.batteryFraction)), height: 16)
                            .padding(.leading, 3)
                            .shadow(color: hotspot.batteryColor.opacity(0.40), radius: 3)
                    } else {
                        // Clean outline with subtle dimmed fill when level is unbroadcast
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 38, height: 16)
                            .padding(.leading, 3)
                    }

                    if hotspot.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 22)
                    }
                }

                // Battery Details Stack
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(hotspot.percentageFormatted)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(hotspot.batteryLevel != nil ? "Şarj" : "Pil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.50))
                    }

                    Text(hotspot.deviceName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Status Capsule (Normal / Düşük Pil)
                if hotspot.isLowBattery {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(hotspot.batteryColor)

                        Text(hotspot.isCriticalBattery ? "Kritik Pil" : "Düşük Pil")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(hotspot.batteryColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(hotspot.batteryColor.opacity(0.16))
                    )
                }
            }
            .padding(.horizontal, 2)

            // Divider & Bottom Telemetry
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.vertical, 1)

            HStack(spacing: 8) {
                if let uptime = hotspot.uptimeFormatted {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))
                        Text("Bağlantı:")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.50))
                        Text(uptime)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: hotspot.isConnected ? "personalhotspot" : "wifi")
                            .font(.system(size: 10.0))
                            .foregroundColor(.white.opacity(0.45))
                        Text(hotspot.isConnected ? "Wi-Fi Kişisel Erişim Noktası" : (hotspot.statusDescription ?? "Bağlantı Yok"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Direct link to Network Settings
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Ağ Ayarları")
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundColor(isActionHovered ? .notchGreen : .white.opacity(0.60))
                }
                .buttonStyle(.plain)
                .onHover { isActionHovered = $0 }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signalIconName(bars: Int) -> String {
        switch bars {
        case 4: return "cellularbars"
        case 3: return "cellularbars"
        case 2: return "cellularbars"
        default: return "cellularbars"
        }
    }
}
