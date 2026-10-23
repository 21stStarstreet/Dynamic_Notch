// CircularBatteryView.swift
// DynamicNotch / UI / Components
//
// Phase 2 (Faz 3): Apple-style circular battery gauge for AirPods & Bluetooth
// peripherals. Renders a subtle track ring, a proportional colored trim arc
// (green / orange / red), and the numeric battery percentage in the center.

import SwiftUI

struct CircularBatteryView: View {

    let percentage: Int   // 0 … 100
    var size: CGFloat = 32.0
    var lineWidth: CGFloat = 3.0

    private var clampedPercentage: Int {
        min(max(percentage, 0), 100)
    }

    private var ringColor: Color {
        switch clampedPercentage {
        case ..<20: return .notchRed
        case ..<40: return .notchOrange
        default:    return .notchGreen
        }
    }

    private var fontSize: CGFloat {
        size < 24 ? max(6.5, round(size * 0.36)) : max(8.5, round(size * 0.29))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(clampedPercentage) / 100.0)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.45), value: clampedPercentage)

            Text("\(clampedPercentage)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, lineWidth + 1)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}
