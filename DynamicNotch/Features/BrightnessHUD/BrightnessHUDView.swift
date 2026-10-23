// BrightnessHUDView.swift
// DynamicNotch / Features / BrightnessHUD
//
// Apple-grade Display Brightness HUD:
// • Top row: Screen localized name (e.g. "Dahili Liquid Retina XDR Ekran" or "Ekran Parlaklığı")
// • Bottom row: Adaptive Sun icon (sun.min / sun.min.fill / sun.max.fill)
//   + GPU Canvas interactive scrubber bar + monospaced percentage level (0–100).

import SwiftUI

struct BrightnessHUDView: View {

    let brightness: Float
    var screenName: String = NSScreen.main?.localizedName ?? "Ekran Parlaklığı"
    var onSetBrightness: ((Float) -> Void)? = nil

    @State private var isDraggingBar: Bool = false
    @State private var isHoveringBar: Bool = false

    private var numericLevel: Int {
        Int(round(min(max(brightness, 0.0), 1.0) * 100))
    }

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var displayScreenName: String {
        let trimmed = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().contains("built-in") {
            return isTurkish ? "Ekran Parlaklığı" : "Display Brightness"
        }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Top Row: Active Display Name
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayScreenName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.notchTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
            }

            // Bottom Row: Sun Icon + Interactive Scrubber Bar + Monospaced Numeric Level (0–100)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: sunIcon)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 22, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))

                InteractiveBrightnessSliderBar(
                    progress: Double(brightness),
                    tint: .white,
                    backgroundColor: Color.white.opacity(0.18),
                    isHighlighted: isDraggingBar || isHoveringBar,
                    onScrub: { newLevel in
                        isDraggingBar = true
                        onSetBrightness?(newLevel)
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
                    .foregroundColor(.gray)
                    .frame(width: 28, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        }
    }

    private var sunIcon: String {
        if brightness <= 0.01 {
            return "sun.min"
        } else if brightness < 0.50 {
            return "sun.min.fill"
        } else {
            return "sun.max.fill"
        }
    }
}

/// Interactive GPU Canvas brightness slider bar that supports direct clicking and horizontal dragging.
private struct InteractiveBrightnessSliderBar: View {
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
