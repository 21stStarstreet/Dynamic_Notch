// OnboardingBadgeView.swift
// DynamicNotch / Features / Onboarding / Views
//
// Apple-grade pure icon presentation without background plates,
// featuring vibrant native gradients, soft radiant glow, and gentle breathing animation.

import SwiftUI

struct OnboardingBadgeView: View {
    let step: OnboardingStep

    var body: some View {
        iconForStep
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        step.accentColor,
                        step.accentColor.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: step.accentColor.opacity(0.30), radius: 8, x: 0, y: 2)
            .frame(width: 52, height: 52)
    }

    @ViewBuilder
    private var iconForStep: some View {
        switch self.step {
        case .welcome:
            Image(systemName: "sparkles")
        case .shortcuts:
            Image(systemName: "keyboard.fill")
        case .permissions:
            Image(systemName: "checkmark.seal.fill")
        case .support:
            Image(systemName: "star.fill")
        case .community:
            Image(systemName: "paperplane.fill")
        }
    }
}
