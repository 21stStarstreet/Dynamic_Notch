// TransitionManager.swift
// DynamicNotch / Core / Animation
//
// Centralises SwiftUI AnyTransition presets for content appearing and disappearing
// inside the notch container so all feature views share cohesive motion physics.

import SwiftUI

enum TransitionManager {

    /// Asymmetric scale + opacity + blur-like feel used for Rich LiveActivities (Now Playing).
    static let liveActivity: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .top)),
        removal:   .opacity.combined(with: .scale(scale: 0.90, anchor: .top))
    )

    /// Crisp vertical slide + fade for system alerts (Battery, Bluetooth, Wi-Fi).
    static let alertBanner: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.94, anchor: .top)),
        removal:   .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
    )

    /// Fast subtle fade for HUD overlays (Volume, Timer).
    static let hud: AnyTransition = .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
}
