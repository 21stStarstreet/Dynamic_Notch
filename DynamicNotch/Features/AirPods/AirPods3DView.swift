// AirPods3DView.swift
// DynamicNotch / Features / AirPods
//
// Ultra-premium 3D AirPods case + bud renderer using pure SwiftUI with
// perspective transforms, layered gradients, specular highlights, and
// ambient occlusion shadows — no external dependencies required.
//
// Rendering Philosophy
// ────────────────────
// Apple's iOS AirPods pairing animation achieves its depth through:
//   1. A perspective-projected 3D case that rotates on the Y axis slightly.
//   2. A lid that rotates open on the X axis (hinge at the top of the case body).
//   3. Buds that emerge from within the open case upward.
//   4. All surfaces have specular highlights on the upper-left to simulate
//      a fixed studio light source (consistent with Apple HIG guidelines).
//   5. Ambient gradients give each surface thickness.
//
// This view synthesises all of the above in SwiftUI using:
//   • `rotation3DEffect`  for case tilt and lid open
//   • Layered `RadialGradient` / `LinearGradient` for surface shading
//   • `shadow` + `blur` for depth cues
//   • `scaleEffect` + `offset` for bud emergence

import SwiftUI

// MARK: - Main 3D View Compositor

struct AirPods3DView: View {

    let model: AirPodsModel
    let phase: AirPodsAnimationPhase

    // The overall 3D rotation of the entire assembly (subtle Y-axis tilt)
    private var assemblyYRotation: Angle {
        switch phase {
        case .hidden:       return .degrees(0)
        case .entering:     return .degrees(-8)
        default:            return .degrees(-12)
        }
    }

    // Lid open angle (X rotation)
    private var lidAngle: Angle {
        switch phase {
        case .openingLid, .emergingBuds, .showing:
            return .degrees(-108)   // 108° matches Apple's natural lid open position
        default:
            return .degrees(0)
        }
    }

    // How far the buds have emerged above the case opening (0 = inside, 1 = full)
    private var budEmergence: CGFloat {
        switch phase {
        case .emergingBuds: return 0.7
        case .showing:      return 1.0
        default:            return 0.0
        }
    }

    // Case body scale (pops in from nothing)
    private var caseScale: CGFloat {
        switch phase {
        case .hidden, .entering: return 0.01
        default: return 1.0
        }
    }

    private var caseOpacity: Double {
        switch phase {
        case .hidden: return 0.0
        default: return 1.0
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // The full case + lid assembly with subtle Y-tilt
            ZStack(alignment: .bottom) {
                // Buds rendered first (behind case lid when closed, in front when open)
                if model.budStyle != .overEar && model.hasCase {
                    AirPodsBudsView(style: model.budStyle, emergence: budEmergence)
                        .opacity(phase == .hidden || phase == .entering || phase == .revealingCase ? 0 : 1)
                }

                // Case body (back + floor)
                AirPodsCaseBodyView(model: model)

                // Lid on top, rotates on X about the top edge of the case body
                if model.hasCase {
                    AirPodsLidView(model: model, angle: lidAngle)
                        .opacity(phase == .hidden || phase == .entering ? 0 : 1)
                }
            }
            .scaleEffect(caseScale)
            .opacity(caseOpacity)
            // Subtle Y-axis tilt gives a 3D dimensional feel
            .rotation3DEffect(
                assemblyYRotation,
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.4
            )
        }
        .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 16)
    }
}

// MARK: - Case Body (Back Shell + Base)

struct AirPodsCaseBodyView: View {
    let model: AirPodsModel

    private var caseSize: CGSize {
        switch model.budStyle {
        case .oval:      return CGSize(width: 114, height: 64)   // AirPods Pro: landscape pebble
        case .shortStem: return CGSize(width: 98, height: 62)    // AirPods 3/4
        case .longStem:  return CGSize(width: 82, height: 72)    // AirPods 1/2: portrait
        case .overEar:   return CGSize(width: 0, height: 0)
        }
    }

    private var caseRadius: CGFloat {
        switch model.budStyle {
        case .oval:      return 26
        case .shortStem: return 24
        case .longStem:  return 20
        case .overEar:   return 0
        }
    }

    var body: some View {
        ZStack {
            // Main body — white premium plastic with subtle warmth
            RoundedRectangle(cornerRadius: caseRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.98),
                            Color(white: 0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: caseSize.width, height: caseSize.height)
                .overlay(
                    // Specular highlight — simulates studio light from upper-left
                    RoundedRectangle(cornerRadius: caseRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    Color.white.opacity(0.0)
                                ],
                                center: UnitPoint(x: 0.25, y: 0.18),
                                startRadius: 0,
                                endRadius: caseSize.width * 0.65
                            )
                        )
                )
                .overlay(
                    // Edge shading — gives plastic thickness / rim
                    RoundedRectangle(cornerRadius: caseRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    Color(white: 0.72).opacity(0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )

            // Status LED (tiny dot in front center)
            Circle()
                .fill(Color(red: 0.25, green: 0.90, blue: 0.52))
                .frame(width: 4.5, height: 4.5)
                .shadow(color: Color(red: 0.25, green: 0.90, blue: 0.52).opacity(0.8), radius: 4)
                .offset(y: 4)

            // Hinge line at top (subtle seam between body and lid)
            Rectangle()
                .fill(Color(white: 0.78).opacity(0.6))
                .frame(width: caseSize.width * 0.88, height: 0.5)
                .offset(y: -(caseSize.height / 2) + 2)
        }
    }
}

// MARK: - Lid (Rotates Open)

struct AirPodsLidView: View {
    let model: AirPodsModel
    let angle: Angle

    private var lidWidth: CGFloat {
        switch model.budStyle {
        case .oval:      return 114
        case .shortStem: return 98
        case .longStem:  return 82
        case .overEar:   return 0
        }
    }

    private var lidHeight: CGFloat {
        switch model.budStyle {
        case .oval:      return 32
        case .shortStem: return 32
        case .longStem:  return 32
        case .overEar:   return 0
        }
    }

    private var lidTopRadius: CGFloat {
        switch model.budStyle {
        case .oval:      return 26
        case .shortStem: return 24
        case .longStem:  return 20
        case .overEar:   return 0
        }
    }

    // Height of the case body so we can place the lid at the top edge
    private var caseBodyHeight: CGFloat {
        switch model.budStyle {
        case .oval:      return 64
        case .shortStem: return 62
        case .longStem:  return 72
        case .overEar:   return 0
        }
    }

    var body: some View {
        ZStack {
            // Lid panel — slightly lighter on top (facing the studio light more)
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: lidTopRadius,
                    bottomLeading: 4,
                    bottomTrailing: 4,
                    topTrailing: lidTopRadius
                ),
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.985),
                        Color(white: 0.93)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: lidWidth, height: lidHeight)
            .overlay(
                // Specular gloss on lid top-left
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: lidTopRadius,
                        bottomLeading: 4,
                        bottomTrailing: 4,
                        topTrailing: lidTopRadius
                    ),
                    style: .continuous
                )
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.0)
                        ],
                        center: UnitPoint(x: 0.2, y: 0.12),
                        startRadius: 0,
                        endRadius: lidWidth * 0.55
                    )
                )
            )
            .overlay(
                // Lid edge border
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: lidTopRadius,
                        bottomLeading: 4,
                        bottomTrailing: 4,
                        topTrailing: lidTopRadius
                    ),
                    style: .continuous
                )
                .stroke(Color(white: 0.80).opacity(0.6), lineWidth: 0.8)
            )
            // Inside surface of the lid (visible when open)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.86), Color(white: 0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: lidWidth - 6, height: lidHeight - 8)
                    .offset(y: 4)
                    .opacity(angle.degrees < -30 ? min(1, (-angle.degrees - 30) / 60.0) : 0)
            )
        }
        // Position lid so its bottom edge aligns with the top edge of the case body.
        // This is the natural hinge axis.
        .offset(y: -(caseBodyHeight / 2) - (lidHeight / 2) + 2)
        // Rotate on X axis about the BOTTOM of the lid (the hinge point)
        .rotation3DEffect(
            angle,
            axis: (x: 1, y: 0, z: 0),
            anchor: UnitPoint(x: 0.5, y: 1.0),   // bottom edge = hinge
            anchorZ: 0,
            perspective: 0.55
        )
        .shadow(
            color: .black.opacity(angle.degrees < -30 ? 0.22 : 0.0),
            radius: 8, x: 0, y: 4
        )
    }
}

// MARK: - Buds (Emerge From Case)

struct AirPodsBudsView: View {
    let style: AirPodsBudStyle
    let emergence: CGFloat   // 0 = inside case, 1 = fully emerged

    // How far above the case opening the buds float when fully emerged
    private var maxEmergenceOffset: CGFloat {
        switch style {
        case .oval:      return -58
        case .shortStem: return -68
        case .longStem:  return -80
        case .overEar:   return 0
        }
    }

    // Horizontal spread of the two buds
    private var budSpread: CGFloat {
        switch style {
        case .oval:      return 26
        case .shortStem: return 22
        case .longStem:  return 18
        case .overEar:   return 0
        }
    }

    private var verticalOffset: CGFloat {
        let caseHeight: CGFloat
        switch style {
        case .oval:      caseHeight = 64
        case .shortStem: caseHeight = 62
        case .longStem:  caseHeight = 72
        case .overEar:   caseHeight = 0
        }
        // Start from just inside the case opening (top of case body)
        let insideCase: CGFloat = -(caseHeight / 2) - 4
        return insideCase + (maxEmergenceOffset - insideCase) * emergence
    }

    var body: some View {
        HStack(spacing: budSpread * 2) {
            SingleBudView(style: style, isLeft: true)
                .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0))

            SingleBudView(style: style, isLeft: false)
                .rotation3DEffect(.degrees(6), axis: (x: 0, y: 1, z: 0))
        }
        .offset(y: verticalOffset)
        .opacity(emergence > 0.05 ? 1 : 0)
        .scaleEffect(0.82 + emergence * 0.18)
    }
}

// MARK: - Single Bud Shape

struct SingleBudView: View {
    let style: AirPodsBudStyle
    let isLeft: Bool

    var body: some View {
        ZStack {
            switch style {
            case .oval:
                OvalBudShape(isLeft: isLeft)
            case .shortStem, .longStem:
                StemBudShape(style: style, isLeft: isLeft)
            case .overEar:
                EmptyView()
            }
        }
    }
}

// MARK: - AirPods Pro Oval Bud

struct OvalBudShape: View {
    let isLeft: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Main Head Body
            ZStack {
                // Bulbous in-ear housing
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color(white: 0.90)],
                            center: UnitPoint(x: isLeft ? 0.35 : 0.65, y: 0.25),
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 24, height: 26)
                    .overlay(
                        Ellipse()
                            .stroke(Color(white: 0.82).opacity(0.6), lineWidth: 0.6)
                    )

                // Black acoustic vent (outer side)
                Capsule()
                    .fill(Color(white: 0.14))
                    .frame(width: 8, height: 3.5)
                    .offset(x: isLeft ? 6 : -6, y: -4)

                // Angled silicone ear tip (inward pointing)
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.94), Color(white: 0.84)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 14, height: 11)

                    // Dark inner sound tunnel
                    Circle()
                        .fill(Color(white: 0.20))
                        .frame(width: 5, height: 5)
                }
                .offset(x: isLeft ? -9 : 9, y: 2)
            }

            // Short Stem pointing down
            VStack(spacing: 0) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.98), Color(white: 0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 6.5, height: 20)

                // Silver chrome charging contact at bottom
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(bottomLeading: 3.25, bottomTrailing: 3.25),
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.78), Color(white: 0.60)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 6.5, height: 3.5)
            }
            .offset(x: isLeft ? 2 : -2, y: 16)
        }
        .frame(width: 32, height: 46)
    }
}

// MARK: - AirPods Stemmed Bud

struct StemBudShape: View {
    let style: AirPodsBudStyle
    let isLeft: Bool

    private var stemHeight: CGFloat { style == .longStem ? 36 : 24 }
    private var stemWidth:  CGFloat { 6.5 }

    var body: some View {
        ZStack(alignment: .top) {
            // Head (speaker bulb)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color(white: 0.89)],
                            center: UnitPoint(x: isLeft ? 0.35 : 0.65, y: 0.28),
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color(white: 0.82).opacity(0.6), lineWidth: 0.6))

                // Acoustic side mesh
                Capsule()
                    .fill(Color(white: 0.16))
                    .frame(width: 7, height: 3)
                    .offset(x: isLeft ? -4 : 4, y: 2)
            }

            // Stem
            VStack(spacing: 0) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.98), Color(white: 0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: stemWidth, height: stemHeight)

                // Chrome bottom cap
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(bottomLeading: 3.25, bottomTrailing: 3.25),
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.78), Color(white: 0.60)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: stemWidth, height: 3.5)
            }
            .offset(y: 16)
        }
        .frame(width: 28, height: 20 + stemHeight)
    }
}
