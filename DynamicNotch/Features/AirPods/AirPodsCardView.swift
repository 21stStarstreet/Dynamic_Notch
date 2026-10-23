// AirPodsCardView.swift
// DynamicNotch / Features / AirPods
//
// The full iOS-style AirPods pairing card that slides up from the bottom
// of the screen when AirPods connect.
//
// Layout (top → bottom inside the card):
//   ┌──────────────────────────────────────┐
//   │  ▒▒▒▒▒▒▒▒▒▒▒  (drag handle pill)    │
//   │                                      │
//   │        [3D AirPods Assembly]         │
//   │                                      │
//   │   AirPods Pro (2. Nesil)             │ ← model name
//   │   ●●●●●●●●● ○ ●●●●●●●●●             │ ← battery row
//   │    L: %88  Case: %72  R: %91         │
//   │                                      │
//   │  [  Bağlandı  ]   [  Bağla  ]        │ ← actions (if applicable)
//   └──────────────────────────────────────┘
//
// Glassmorphism Treatment
// ───────────────────────
// The card uses a `.ultraThinMaterial` background (identical to iOS Control
// Centre panels) with a 1pt white rim and a subtle inner shadow that gives
// the frosted glass its characteristic floating depth.
//
// The card is NOT hosted inside the notch window — it lives in its own
// `AirPodsCardWindowController` that creates a separate borderless NSPanel
// anchored to the bottom centre of the main screen.

import SwiftUI

// MARK: - Card Root

struct AirPodsCardView: View {

    @ObservedObject var viewModel: AirPodsCardViewModel

    /// Vertical translation driven by phase (0 = fully on screen, positive = offscreen below)
    private var cardOffsetY: CGFloat {
        switch viewModel.phase {
        case .hidden:        return 520
        case .entering,
             .revealingCase,
             .openingLid,
             .emergingBuds,
             .showing:       return 0
        case .dismissing:    return 520
        }
    }

    private var cardOpacity: Double {
        switch viewModel.phase {
        case .hidden:     return 0
        case .entering:   return 1
        default:          return 1
        }
    }

    var body: some View {
        // Pin to the bottom of whatever frame this view inhabits
        VStack {
            Spacer()
            card
                .offset(y: cardOffsetY)
                .opacity(cardOpacity)
        }
        .padding(.bottom, 28)   // Safe area breathing room from the Dock
    }

    // MARK: - Card Shell

    private var card: some View {
        VStack(spacing: 0) {

            dragHandle

            VStack(spacing: 24) {

                // 3D AirPods assembly
                airpodsRenderer

                // Device info + battery
                batterySection

            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .frame(width: 340)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            // 1pt white frosted rim — the hallmark of Apple's glass panels
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        .shadow(color: .black.opacity(0.38), radius: 48, x: 0, y: -8)
        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: -2)
        .onTapGesture {
            // Tapping the card dismisses it (mirrors iOS behaviour)
            viewModel.dismiss(animated: true)
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 36, height: 4)
            .padding(.top, 12)
    }

    // MARK: - 3D Renderer Area

    private var airpodsRenderer: some View {
        ZStack {
            // Ambient shadow blob beneath the case
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(viewModel.phase == .showing ? 0.22 : 0.0),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 30)
                .blur(radius: 8)
                .offset(y: 55)

            AirPods3DView(model: viewModel.model, phase: viewModel.phase)
        }
        .frame(height: 160)
    }

    // MARK: - Battery Section

    private var batterySection: some View {
        VStack(spacing: 14) {

            // Model name
            Text(viewModel.model.displayName)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .opacity(viewModel.phase == .showing ? 1 : 0)
                .offset(y: viewModel.phase == .showing ? 0 : 6)

            // Battery indicators
            if viewModel.battery.hasAnyData {
                batteryRow
                    .opacity(viewModel.phase == .showing ? 1 : 0)
                    .offset(y: viewModel.phase == .showing ? 0 : 8)
            } else {
                // Connecting state
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(Color.secondary)

                    Text("Bağlanıyor…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .opacity(viewModel.phase == .showing ? 1 : 0)
            }
        }
    }

    // MARK: - Battery Row

    private var batteryRow: some View {
        HStack(spacing: 0) {

            if let left = viewModel.battery.left {
                BatteryPillView(
                    label: "Sol",
                    iconName: "airpodpro.left",
                    percentage: left
                )
            }

            Spacer()

            if viewModel.model.hasCase, let caseLevel = viewModel.battery.caseLevel {
                BatteryPillView(
                    label: "Kutu",
                    iconName: "airpodspro.case.fill",
                    percentage: caseLevel
                )
            }

            Spacer()

            if let right = viewModel.battery.right {
                BatteryPillView(
                    label: "Sağ",
                    iconName: "airpodpro.right",
                    percentage: right
                )
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        ZStack {
            // Ultra-thin material (matches iOS Control Centre, AirPods panel)
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(.ultraThinMaterial)

            // Subtle top-lit inner glow
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.35)
                    )
                )
        }
    }
}

// MARK: - Battery Pill

struct BatteryPillView: View {
    let label: String
    let iconName: String
    let percentage: Int

    private var batteryColor: Color {
        if percentage > 50 { return Color(red: 0.22, green: 0.85, blue: 0.50) }
        if percentage > 20 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 6) {

            // AirPod SF Symbol icon
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .symbolRenderingMode(.hierarchical)

            // Percentage label
            Text("%\(percentage)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(batteryColor)
                .contentTransition(.numericText())

            // Tiny battery bar
            BatteryBarView(percentage: percentage, color: batteryColor)

            // Label
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
    }
}

// MARK: - Battery Bar

struct BatteryBarView: View {
    let percentage: Int
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            // Track
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 36, height: 4)

            // Fill
            Capsule()
                .fill(color)
                .frame(width: max(4, 36.0 * CGFloat(percentage) / 100.0), height: 4)
        }
        .frame(width: 36, height: 4)
    }
}
