// SpringConfig.swift
// DynamicNotch / Core / Animation
//
// A single source-of-truth for all animation curves used in the app.
// Centralising them here means visual "feel" tuning only happens in one file,
// and every animation across the codebase is automatically consistent.

import SwiftUI

enum SpringConfig {

    /// Expand: fluid spring with authentic Apple Dynamic Island elastic bounce and wave overshoot.
    static let expand = Animation.spring(response: 0.44, dampingFraction: 0.64, blendDuration: 0.0)

    /// Compact wing appear: organic horizontal spring when side wings emerge with tactile pop.
    static let compactAppear = Animation.spring(response: 0.36, dampingFraction: 0.66, blendDuration: 0.0)

    /// Collapse: silky retraction with subtle fluid suction into the hardware notch.
    static let collapse = Animation.spring(response: 0.38, dampingFraction: 0.70, blendDuration: 0.0)

    /// Content crossfade / morph (e.g. now-playing → battery alert, or radial menu ↔ spaces).
    static let contentTransition = Animation.spring(response: 0.40, dampingFraction: 0.64, blendDuration: 0.0)

    /// Jelly: used for interactive squeeze effects.
    static let jelly = Animation.spring(response: 0.35, dampingFraction: 0.50)

    // MARK: - Satellite Orb Springs (iOS Dynamic Island Style)

    /// Orb entrance: organic bounce from top edge.
    static let orbAppear = Animation.spring(response: 0.42, dampingFraction: 0.66)

    /// Orb expand: swift, fluid expansion into card.
    static let orbExpand = Animation.spring(response: 0.38, dampingFraction: 0.68)

    /// Orb collapse: critically damped retraction into compact orb.
    static let orbCollapse = Animation.spring(response: 0.34, dampingFraction: 0.72)

    /// Orb dismiss: clean fade out.
    static let orbDismiss = Animation.easeInOut(duration: 0.28)
}
