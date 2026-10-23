// HotspotAlertView.swift
// DynamicNotch / Features / Hotspot
//
// Apple-grade transient notification HUD displayed when a connected
// Personal Hotspot device's battery level drops to low or critical levels.

import SwiftUI

struct HotspotAlertView: View {

    let hotspot: HotspotItem
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: Glowing circular battery warning housing
            ZStack {
                Circle()
                    .fill(hotspot.batteryColor.opacity(0.18))
                    .frame(width: 36, height: 36)

                Image(systemName: hotspot.batteryIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(hotspot.batteryColor)
            }

            // Middle: Device Name & Low Battery Description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(hotspot.isCriticalBattery ? "Kritik Pil Uyarısı" : "Hotspot Pili Azalıyor")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(hotspot.batteryColor)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))

                    Text(hotspot.percentageFormatted)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.90))
                }

                Text("\(hotspot.deviceName) şarja takılmalı")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Right: Hotspot symbol badge
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 28, height: 28)

                Image(systemName: "personalhotspot")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.notchGreen)
            }
        }
    }
}
