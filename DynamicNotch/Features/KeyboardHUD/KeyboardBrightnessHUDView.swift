// KeyboardBrightnessHUDView.swift
// DynamicNotch / Features / KeyboardHUD
//
// Apple-grade Keyboard Backlight HUD:
// • Top row: Localized header ("Klavye Aydınlatması" / "Keyboard Brightness")
// • Bottom row: Dynamic Keyboard icon (keyboard / keyboard.fill)
//   + GPU Canvas interactive scrubber bar + monospaced percentage level (0–100).
//
// Built to the exact visual, typographic, and physical standards of VolumeHUDView and BrightnessHUDView.

import SwiftUI

struct KeyboardBrightnessHUDView: View {

    let brightness: Float
    var onSetBrightness: ((Float) -> Void)? = nil

    @State private var isDraggingBar: Bool = false
    @State private var isHoveringBar: Bool = false

    private var numericLevel: Int {
        Int(round(min(max(brightness, 0.0), 1.0) * 100))
    }

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var headerTitle: String {
        isTurkish ? "Klavye Aydınlatması" : "Keyboard Brightness"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Top Row: Localized Header Title
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.notchTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
            }

            // Bottom Row: Keyboard Icon + Interactive Scrubber Bar + Monospaced Numeric Level (0–100)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: keyboardIcon)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 22, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))

                InteractiveKeyboardSliderBar(
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

    private var keyboardIcon: String {
        brightness <= 0.01 ? "keyboard" : "keyboard.fill"
    }
}

/// Interactive GPU Canvas keyboard brightness slider bar that supports direct clicking and horizontal dragging.
private struct InteractiveKeyboardSliderBar: View {
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
