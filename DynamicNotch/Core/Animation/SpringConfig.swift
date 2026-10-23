// SpringConfig.swift
// DynamicNotch / Core / Animation
//
// A single source-of-truth for all animation curves used in the app.
// Centralising them here means visual "feel" tuning only happens in one file,
// and every animation across the codebase is automatically consistent.

import SwiftUI

enum SpringConfig {

    /// Expand: fluid spring with subtle organic bounce — mimics Apple's Dynamic Island.
    static let expand = Animation.spring(response: 0.42, dampingFraction: 0.76, blendDuration: 0.15)

    /// Compact wing appear: smooth horizontal spring when side wings emerge from the notch.
    static let compactAppear = Animation.spring(response: 0.38, dampingFraction: 0.80, blendDuration: 0.15)

    /// Collapse: silky, critically-damped spring that smoothly retracts into the hardware notch.
    static let collapse = Animation.spring(response: 0.40, dampingFraction: 0.86, blendDuration: 0.15)

    /// Content crossfade / swap (e.g. now-playing → battery alert).
    static let contentTransition = Animation.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.12)

    /// Jelly: used for interactive squeeze effects.
    static let jelly = Animation.spring(response: 0.35, dampingFraction: 0.50)

    // MARK: - Satellite Orb Springs (iOS Dynamic Island Style)

    /// Orb entrance: organic bounce from top edge.
    static let orbAppear = Animation.spring(response: 0.44, dampingFraction: 0.72)

    /// Orb expand: swift, fluid expansion into card.
    static let orbExpand = Animation.spring(response: 0.38, dampingFraction: 0.80)

    /// Orb collapse: critically damped retraction into compact orb.
    static let orbCollapse = Animation.spring(response: 0.32, dampingFraction: 0.88)

    /// Orb dismiss: clean fade out.
    static let orbDismiss = Animation.easeInOut(duration: 0.28)
}
