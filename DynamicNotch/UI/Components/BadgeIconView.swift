// BadgeIconView.swift
// DynamicNotch / UI / Components
//
// Phase 2 (Faz 5): Apple-grade system alert badge icon.
// Renders a dual-layer circular badge with a semi-transparent tinted background,
// a subtle luminous contour ring, and a centered SF Symbol icon.

import SwiftUI

struct BadgeIconView: View {

    let iconName: String
    let color: Color
    var size: CGFloat = 34.0
    var iconScale: CGFloat = 0.48
    var strokeWidth: CGFloat = 1.25

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))

            Circle()
                .strokeBorder(color.opacity(0.35), lineWidth: strokeWidth)

            Image(systemName: iconName)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}
