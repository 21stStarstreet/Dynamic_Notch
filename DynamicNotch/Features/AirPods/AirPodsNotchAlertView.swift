// AirPodsNotchAlertView.swift
// DynamicNotch / Features / AirPods
//
// Displays the Apple-grade vertical 3-tier AirPods connection experience directly
// inside the Dynamic Notch:
//   1. Top: Minimalist AirPods Model Title (clean, no badges)
//   2. Center: Really Big AirPods 3D video loop / procedural assembly (180pt hero width)
//   3. Bottom: R / C / L Apple Circular Gauges (open arc, % removed, strictly inside 180pt bounds)

import SwiftUI

struct AirPodsNotchAlertView: View {

    let deviceName: String
    let model: AirPodsModel
    let battery: AirPodsBattery
    var singleBattery: Int? = nil

    @State private var phase: AirPodsAnimationPhase = .revealingCase
    @State private var appearTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 9) {
            // 1. TOP: Minimalist Model Title (clean Apple typography, no badges)
            Text(deviceName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 4)

            // 2. CENTER: Really Big AirPods Hero Stage (2:1 aspect matching 896x448)
            visualAssembly
                .frame(width: 210, height: 105)

            // 3. BOTTOM: R / C / L Apple Circular Gauges (strictly inside 180pt width)
            batteryGaugesSection
                .frame(width: 180)
                .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            startAnimationSequence()
        }
        .onDisappear {
            appearTask?.cancel()
        }
    }

    // MARK: - Visual Assembly (Official Apple Movie or 3D Fallback)

    private var visualAssembly: some View {
        Group {
            if let videoURL = officialVideoURL {
                AirPodsVideoPlayerView(url: videoURL)
                    .frame(width: 210, height: 105)
            } else {
                notch3DAssembly
            }
        }
    }

    private var officialVideoURL: URL? {
        let name: String
        switch model {
        case .airPodsPro2, .airPods4, .airPods3, .airPods:
            name = "AirPods_Pro_2_Official"
        case .airPodsPro:
            name = "AirPods_Pro_1_Official"
        case .airPodsMax, .unknown:
            return nil
        }

        // 1. Check App Bundle
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: "mov") {
            return bundleURL
        }

        // 2. Check local project Media directory
        let localURL = URL(fileURLWithPath: "DynamicNotch/Resources/Media/\(name).mov")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        // 3. Check macOS system BluetoothUIService resource directory
        let sysPath = (model == .airPodsPro)
            ? "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/Banner-PID-8203-Case-mov/Banner-PID-8203-Case-Loop.mov"
            : "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/Banner-PID-8209-Case-mov/Banner-PID-8209-Case-Loop.mov"
        let sysURL = URL(fileURLWithPath: sysPath)
        if FileManager.default.fileExists(atPath: sysURL.path) {
            return sysURL
        }

        return nil
    }

    // MARK: - Miniature 3D Assembly Fallback

    private var notch3DAssembly: some View {
        ZStack {
            // Subtle ambient contact glow beneath the 3D case
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.6), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 36
                    )
                )
                .frame(width: 80, height: 20)
                .blur(radius: 6)
                .offset(y: 42)

            AirPods3DView(model: model, phase: phase)
                .scaleEffect(0.95)
                .offset(y: 6)
        }
    }

    // MARK: - Battery Section (R / C / L)

    private var batteryGaugesSection: some View {
        HStack(spacing: 24) {
            // R (Right earbud)
            AirPodsCircularGaugeView(
                label: "R",
                percentage: battery.right ?? singleBattery
            )

            // C (Case) - only if model has a charging case
            if model.hasCase {
                AirPodsCircularGaugeView(
                    label: "C",
                    percentage: battery.caseLevel
                )
            }

            // L (Left earbud)
            AirPodsCircularGaugeView(
                label: "L",
                percentage: battery.left ?? singleBattery
            )
        }
    }

    // MARK: - Sequencer

    private func startAnimationSequence() {
        appearTask?.cancel()
        phase = .revealingCase

        appearTask = Task { @MainActor in
            // Step 1: Open Lid (0.16s after appearance)
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(AirPodsSpring.lidOpen) {
                phase = .openingLid
            }

            // Step 2: Buds float up (0.28s after lid starts)
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(AirPodsSpring.budsEmerge) {
                phase = .emergingBuds
            }

            // Step 3: Settle in full state
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(AirPodsSpring.settle) {
                phase = .showing
            }
        }
    }
}

// MARK: - Apple Circular Gauge (Open Arc with Inner Label & Percentage, No '%')

struct AirPodsCircularGaugeView: View {
    let label: String
    let percentage: Int?

    private var progress: CGFloat {
        guard let percentage else { return 0.0 }
        return min(max(CGFloat(percentage) / 100.0, 0.0), 1.0)
    }

    private var progressColor: Color {
        guard let percentage else { return Color.white.opacity(0.3) }
        if percentage > 20 {
            return Color(red: 0.25, green: 0.90, blue: 0.52)
        } else if percentage > 10 {
            return Color(red: 0.98, green: 0.65, blue: 0.18)
        } else {
            return Color(red: 0.98, green: 0.32, blue: 0.32)
        }
    }

    var body: some View {
        ZStack {
            // Background Track (270° open arc, split at bottom)
            Circle()
                .trim(from: 0.0, to: 0.75)
                .stroke(
                    Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            // Active Progress Track
            Circle()
                .trim(from: 0.0, to: progress * 0.75)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)

            // Centered content (Letter & Pure Number, NO '%')
            VStack(spacing: 1.0) {
                Text(label)
                    .font(.system(size: 9.0, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))

                if let percentage {
                    Text("\(percentage)")
                        .font(.system(size: percentage >= 100 ? 11.5 : 13.0, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                } else {
                    Text("--")
                        .font(.system(size: 13.0, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .offset(y: -1)
        }
        .frame(width: 44, height: 44)
    }
}
