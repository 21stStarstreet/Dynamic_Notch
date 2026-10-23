// ProgressBarView.swift
// DynamicNotch / UI / Components
//
// GPU-accelerated progress bar rendered via SwiftUI Canvas.
//
// Why Canvas instead of GeometryReader?
// ─────────────────────────────────────
// Using `GeometryReader` inside a container that is animating its size causes
// SwiftUI to re-evaluate child layout constraints on every frame, which can
// trigger `-layoutSubtreeIfNeeded` or `Update Constraints in Window` exceptions
// in AppKit's NSHostingView. `Canvas` renders directly during the draw pass
// with zero layout invalidation.

import SwiftUI

struct ProgressBarView: View {

    let progress: Double
    var tint: Color = .white
    var backgroundColor: Color = .white.opacity(0.18)
    var isIndeterminate: Bool = false

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0.0), 1.0))
    }

    var body: some View {
        if isIndeterminate {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { context, size in
                    let radius = size.height / 2.0
                    let bgRect = CGRect(origin: .zero, size: size)
                    let bgPath = Path(roundedRect: bgRect, cornerRadius: radius)
                    context.fill(bgPath, with: .color(backgroundColor))

                    let time = timeline.date.timeIntervalSinceReferenceDate
                    // Smooth 1.2-second cycle sweep
                    let cycle = (time * 0.85).truncatingRemainder(dividingBy: 1.4)
                    let beamWidth = max(18.0, size.width * 0.32)
                    let startX = -beamWidth
                    let endX = size.width + beamWidth
                    let currentX = startX + (endX - startX) * CGFloat(cycle / 1.4)

                    let beamRect = CGRect(x: currentX, y: 0, width: beamWidth, height: size.height)

                    context.clip(to: bgPath)
                    context.fill(
                        Path(roundedRect: beamRect, cornerRadius: radius),
                        with: .color(tint.opacity(0.85))
                    )
                }
            }
        } else {
            Canvas { context, size in
                let radius = size.height / 2.0
                let bgRect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(roundedRect: bgRect, cornerRadius: radius),
                    with: .color(backgroundColor)
                )

                let fillWidth = max(0, size.width * clampedProgress)
                if fillWidth > 0 {
                    let fillRect = CGRect(x: 0, y: 0, width: fillWidth, height: size.height)
                    context.fill(
                        Path(roundedRect: fillRect, cornerRadius: radius),
                        with: .color(tint)
                    )
                }
            }
        }
    }
}
