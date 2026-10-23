// BatteryAlertView.swift
// DynamicNotch / Features / Battery
//
// Phase 2 (Faz 1) Redesigned Battery Alert Views:
//   1. Charging:     Compact-first alert; when hovered, expands to single-line layout with
//                    title on left and percentage + dynamic charging battery icon on right.
//   2. Battery Low:  Two-line warning layout on left + iPhone Dynamic Island Low Battery
//                    animated badge on right (matching reference screenshot 1:1).
//   3. Full Battery: Two-line completion summary on left + green bolt-battery badge on right.

import SwiftUI
import AppKit

struct BatteryAlertView: View {

    enum BatteryAlertType: Equatable {
        case charging
        case low
        case full
    }

    let type: BatteryAlertType
    let percentage: Int

    private var displayPercentage: Int {
        switch type {
        case .full:
            return 100
        case .low:
            return percentage <= 20 ? max(1, percentage) : 14
        case .charging:
            return min(max(percentage, 1), 100)
        }
    }

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    var body: some View {
        switch type {
        case .charging:
            chargingView
        case .low:
            lowBatteryView
        case .full:
            fullBatteryView
        }
    }

    // MARK: - 1. Charging Layout (Expanded on Hover: 42pt Height)

    private var chargingView: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(isTurkish ? "Şarj Oluyor" : "Charging")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.notchTitle)
                .lineLimit(1)

            Spacer(minLength: 16)

            HStack(alignment: .center, spacing: 7) {
                Text("%\(displayPercentage)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(batteryColor)

                ZStack {
                    Image(systemName: batteryIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(batteryColor)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: -1.5, y: 0)
                }
            }
        }
    }

    // MARK: - 2. Battery Low Layout (62pt Height: 2-Line Warning + iPhone Animated Low Battery Icon)

    private var lowBatteryView: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isTurkish ? "Düşük Batarya" : "Low Battery")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.notchTitle)
                        .lineLimit(1)

                    Text("%\(displayPercentage)")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.notchRed)
                        .lineLimit(1)
                }

                Text(isTurkish ? "Düşük Güç Modu'nu açmanız veya\nşarja takmanız önerilir." : "Consider turning on Low Power Mode\nor connecting to a charger.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.48))
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            IPhoneLowBatteryAnimatedBadge()
        }
    }

    // MARK: - 3. Full Battery Layout (52pt Height: 2-Line + Right Badge)

    private var fullBatteryView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isTurkish ? "Batarya Dolu" : "Battery Full")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.notchTitle)
                        .lineLimit(1)

                    Text("100%")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.notchGreen)
                        .lineLimit(1)
                }

                Text(isTurkish ? "Mac'iniz tamamen şarj oldu." : "Your Mac is fully charged.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.notchSubtitle)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "battery.100.bolt")
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(.notchGreen)
                .frame(width: 32, height: 32)
        }
    }

    // MARK: - Dynamic SF Symbol Battery Icon & Color (Faz 1.4)

    private var batteryIconName: String {
        switch displayPercentage {
        case 0..<10:  return "battery.0"
        case 10..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default:      return "battery.100"
        }
    }

    private var batteryColor: Color {
        let isCharging = (type == .charging || type == .full)
        switch (displayPercentage, isCharging) {
        case (_, true):  return .notchGreen
        case (..<20, _): return .notchRed
        case (..<40, _): return .notchOrange
        default:         return .notchGreen
        }
    }
}

// MARK: - iPhone Dynamic Island Low Battery Animated Badge

private struct IPhoneLowBatteryAnimatedBadge: View {

    @State private var breathe = false
    @State private var ripple  = false

    private let outerCapsuleColor = Color(red: 0.28, green: 0.05, blue: 0.06)
    private let batteryShellColor = Color(red: 0.56, green: 0.14, blue: 0.15)
    private let activeRedColor    = Color(red: 1.00, green: 0.26, blue: 0.26)

    var body: some View {
        ZStack {
            // 1. Dark crimson outer capsule pill
            Capsule(style: .continuous)
                .fill(outerCapsuleColor)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(activeRedColor.opacity(0.20), lineWidth: 1.0)
                )
                .frame(width: 66, height: 36)

            // 2. Translucent red battery body + right terminal cap
            HStack(alignment: .center, spacing: 2.0) {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(batteryShellColor)
                    .frame(width: 34, height: 18)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(batteryShellColor)
                    .frame(width: 2.5, height: 7)
            }
            .offset(x: 1.5)

            // 3. Low-charge inner red pill bar + iPhone pulsing/rippling focus ring
            //    positioned over the left side of the battery body
            ZStack {
                // Expanding outer sonar ripple ring
                Circle()
                    .strokeBorder(activeRedColor.opacity(ripple ? 0.0 : 0.65), lineWidth: 1.4)
                    .frame(width: 24, height: 24)
                    .scaleEffect(ripple ? 1.38 : 0.86)

                // Primary iPhone focus ring around the low-charge bar
                Circle()
                    .strokeBorder(activeRedColor, lineWidth: 1.9)
                    .frame(width: 24, height: 24)
                    .scaleEffect(breathe ? 1.06 : 0.94)
                    .shadow(color: activeRedColor.opacity(0.55), radius: breathe ? 4.5 : 2.0)

                // Inner glowing low-charge bar
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(activeRedColor)
                    .frame(width: 5.5, height: 11)
                    .scaleEffect(breathe ? 1.04 : 0.96)
            }
            .offset(x: -10.5)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.95)
                .repeatForever(autoreverses: true)
            ) {
                breathe = true
            }
            withAnimation(
                .easeOut(duration: 1.55)
                .repeatForever(autoreverses: false)
            ) {
                ripple = true
            }
        }
    }
}
