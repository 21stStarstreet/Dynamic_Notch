// DynamicIslandShape.swift
// DynamicNotch / Core / Animation
//
// Authentic Apple Dynamic Island continuous superellipse (squircle) silhouette
// for notchless displays (MacBook Air M1, iMac, Mac mini, Mac Studio, external monitors).
//
// Unlike NotchShape, DynamicIslandShape is completely detached from the display
// bezel, featuring 360-degree continuous rounded curvature with no concave ears.

import SwiftUI

/// Continuous Apple squircle shape for the floating capsule.
struct DynamicIslandShape: Shape {

    var cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 20.0) {
        self.cornerRadius = cornerRadius
    }

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let maxRadius = min(rect.width / 2.0, rect.height / 2.0)
        let r = max(0.0, min(cornerRadius, maxRadius))

        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: r, height: r),
            style: .continuous
        )
        return path
    }
}

/// Draws the continuous 360-degree perimeter rim highlight for the floating capsule,
/// providing Apple-grade liquid glass depth and specular lighting.
struct DynamicIslandRimShape: Shape {

    var cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 20.0) {
        self.cornerRadius = cornerRadius
    }

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let maxRadius = min(rect.width / 2.0, rect.height / 2.0)
        let r = max(0.0, min(cornerRadius, maxRadius))

        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: r, height: r),
            style: .continuous
        )
        return path
    }
}
