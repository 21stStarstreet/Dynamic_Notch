// NotchShape.swift
// DynamicNotch / Core / Animation
//
// Authentic Apple Dynamic-Notch silhouette with outward-flaring concave top
// ears that merge flush into the top display bezel and smooth convex bottom
// corners.
//
// Geometry
// ────────
//   (0,0) ──────┐                                       ┌────── (w,0)
//                ╲  topEarRadius         topEarRadius  ╱
//                 │                                   │
//                 │           NOTCH BODY              │
//                 ╰───────────────────────────────────╯
//                 bottomCornerRadius   bottomCornerRadius
//
// The main body vertical walls sit at `x = topEarRadius` and `x = width - topEarRadius`.

import SwiftUI

struct NotchShape: Shape {

    var topEarRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(cornerRadius: CGFloat, topEarRadius: CGFloat = 10.0) {
        self.bottomCornerRadius = cornerRadius
        self.topEarRadius = topEarRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topEarRadius, bottomCornerRadius) }
        set {
            topEarRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let topR = min(max(topEarRadius, 0), w * 0.25, h * 0.45)
        let botR = min(max(bottomCornerRadius, 0), (w - 2 * topR) * 0.48, h - topR)

        let leftWallX  = rect.minX + topR
        let rightWallX = rect.maxX - topR

        var path = Path()

        // 1. Start at top-left tip flush with the screen top edge
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 2. Top-left outward concave ear curving down into the left vertical wall
        // Wide liquid flare using smooth Apple continuous cubic curve
        path.addCurve(
            to: CGPoint(x: leftWallX, y: rect.minY + topR),
            control1: CGPoint(x: rect.minX + topR * 0.55, y: rect.minY),
            control2: CGPoint(x: leftWallX, y: rect.minY + topR * 0.45)
        )

        // 3. Left vertical wall down to the bottom-left corner start
        path.addLine(to: CGPoint(x: leftWallX, y: rect.maxY - botR))

        // 4. Bottom-left smooth convex corner (Apple continuous cubic squircle)
        path.addCurve(
            to: CGPoint(x: leftWallX + botR, y: rect.maxY),
            control1: CGPoint(x: leftWallX, y: rect.maxY - botR * 0.448),
            control2: CGPoint(x: leftWallX + botR * 0.448, y: rect.maxY)
        )

        // 5. Bottom horizontal edge
        path.addLine(to: CGPoint(x: rightWallX - botR, y: rect.maxY))

        // 6. Bottom-right smooth convex corner (Apple continuous cubic squircle)
        path.addCurve(
            to: CGPoint(x: rightWallX, y: rect.maxY - botR),
            control1: CGPoint(x: rightWallX - botR * 0.448, y: rect.maxY),
            control2: CGPoint(x: rightWallX, y: rect.maxY - botR * 0.448)
        )

        // 7. Right vertical wall up to the top-right ear start
        path.addLine(to: CGPoint(x: rightWallX, y: rect.minY + topR))

        // 8. Top-right outward concave ear flaring out to the screen top edge
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rightWallX, y: rect.minY + topR * 0.45),
            control2: CGPoint(x: rect.maxX - topR * 0.55, y: rect.minY)
        )

        // 9. Close along the top screen edge (y = 0)
        path.closeSubpath()

        return path
    }
}

/// Draws only the left, bottom, and right contour of the NotchShape (omitting
/// the top edge against the display bezel) so the subtle glass rim highlight
/// never draws a white line across the top of the screen.
struct NotchRimShape: Shape {

    var topEarRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topEarRadius, bottomCornerRadius) }
        set {
            topEarRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let topR = min(max(topEarRadius, 0), w * 0.25, h * 0.45)
        let botR = min(max(bottomCornerRadius, 0), (w - 2 * topR) * 0.48, h - topR)

        let leftWallX  = rect.minX + topR
        let rightWallX = rect.maxX - topR

        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: leftWallX, y: rect.minY + topR),
            control1: CGPoint(x: rect.minX + topR * 0.55, y: rect.minY),
            control2: CGPoint(x: leftWallX, y: rect.minY + topR * 0.45)
        )
        path.addLine(to: CGPoint(x: leftWallX, y: rect.maxY - botR))
        path.addCurve(
            to: CGPoint(x: leftWallX + botR, y: rect.maxY),
            control1: CGPoint(x: leftWallX, y: rect.maxY - botR * 0.448),
            control2: CGPoint(x: leftWallX + botR * 0.448, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rightWallX - botR, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rightWallX, y: rect.maxY - botR),
            control1: CGPoint(x: rightWallX - botR * 0.448, y: rect.maxY),
            control2: CGPoint(x: rightWallX, y: rect.maxY - botR * 0.448)
        )
        path.addLine(to: CGPoint(x: rightWallX, y: rect.minY + topR))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rightWallX, y: rect.minY + topR * 0.45),
            control2: CGPoint(x: rect.maxX - topR * 0.55, y: rect.minY)
        )

        return path
    }
}
