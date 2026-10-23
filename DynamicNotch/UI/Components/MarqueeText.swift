// MarqueeText.swift
// DynamicNotch / UI / Components
//
// Auto-scrolling marquee label for long track titles.
//
// Engineering details
// ───────────────────
// Uses `NotchSizeCalculator.measureText` (`NSString.size(withAttributes:)`)
// instead of a nested GeometryReader-in-GeometryReader pattern, preventing
// AppKit/SwiftUI `-layoutSubtreeIfNeeded` recursion during spring animations.

import SwiftUI
import AppKit

struct MarqueeText: View {

    let text: String
    let font: Font
    var nsFont: NSFont = .systemFont(ofSize: 13, weight: .semibold)
    var containerWidth: CGFloat = 150.0
    var speed: Double = 28.0   // points per second

    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .frame(width: containerWidth, height: 17, alignment: .leading)
            .clipped()
            .onAppear {
                recalculateAndAnimate()
            }
            .onChange(of: text) { _, _ in
                recalculateAndAnimate()
            }
    }

    private func recalculateAndAnimate() {
        withAnimation(.linear(duration: 0)) {
            offset = 0
        }

        let textWidth = NotchSizeCalculator.measureText(text, font: nsFont)
        guard textWidth > containerWidth, containerWidth > 0 else { return }

        let travelDistance = textWidth - containerWidth + 14
        let duration = max(Double(travelDistance) / speed, 2.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(
                .linear(duration: duration)
                .repeatForever(autoreverses: true)
            ) {
                offset = -travelDistance
            }
        }
    }
}
