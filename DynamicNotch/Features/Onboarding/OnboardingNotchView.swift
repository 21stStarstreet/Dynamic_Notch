// OnboardingNotchView.swift
// DynamicNotch / Features / Onboarding / Views
//
// Apple-grade multi-step onboarding presentation hosted directly inside
// the DynamicNotch window. Features fluid typography, liquid glass buttons,
// page indicators, and non-blocking spring transitions.

import SwiftUI

struct OnboardingNotchView: View {
    let step: OnboardingStep
    let onStepChange: (OnboardingStep) -> Void
    let onFinish: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var hoveredButton: String? = nil
    @State private var isShortcutsAllCompleted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Content Area
            Group {
                switch step {
                case .welcome:
                    welcomeContent
                case .shortcuts:
                    InteractiveShortcutTrainerView(
                        onProceed: {
                            handlePrimaryAction()
                        },
                        onAllCompletedChanged: { completed in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isShortcutsAllCompleted = completed
                            }
                        }
                    )
                case .permissions, .support, .community:
                    detailContent(for: step)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .scale(scale: 1.04))
            ))
            .id(step)

            Spacer(minLength: 8)

            // Bottom Navigation & Actions Row
            if !(step == .shortcuts && isShortcutsAllCompleted) {
                bottomActionBar
            } else {
                HStack {
                    Spacer()
                    paginationDots
                    Spacer()
                }
                .frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 1: Welcome Banner

    private var welcomeContent: some View {
        VStack(spacing: 8) {
            WelcomeAnimatedTextView(isSingleRound: false)

            Text(step.subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .lineSpacing(2.0)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
    }

    // MARK: - Steps 2, 3, 4: Rich Feature Presentation

    private func detailContent(for currentStep: OnboardingStep) -> some View {
        HStack(alignment: .center, spacing: 16) {
            OnboardingBadgeView(step: currentStep)

            VStack(alignment: .leading, spacing: 4) {
                Text(currentStep.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(currentStep.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2.0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Bottom Action Bar & Navigation

    private var bottomActionBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Secondary Action (Geç / Ayarları Aç / GitHub'da Aç / Telegram'a Katıl)
            if let secTitle = step.secondaryButtonTitle {
                Button(action: handleSecondaryAction) {
                    Text(secTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            }
                        )
                }
                .buttonStyle(.plain)
                .scaleEffect(hoveredButton == "secondary" ? 1.02 : 1.0)
                .onHover { isHovered in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        hoveredButton = isHovered ? "secondary" : nil
                    }
                }
            }

            Spacer()

            // Apple Pagination Dots
            paginationDots

            Spacer()

            // Primary Action (Sürdür / Başla)
            Button(action: handlePrimaryAction) {
                HStack(spacing: 5) {
                    Text(step.primaryButtonTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))

                    if step != .community {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        step.accentColor,
                                        step.accentColor.opacity(0.82)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    }
                )
                .shadow(color: step.accentColor.opacity(0.35), radius: 6, y: 1)
            }
            .buttonStyle(.plain)
            .scaleEffect(hoveredButton == "primary" ? 1.02 : 1.0)
            .onHover { isHovered in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    hoveredButton = isHovered ? "primary" : nil
                }
            }
        }
    }

    private var paginationDots: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? Color.white : Color.white.opacity(0.24))
                    .frame(width: s == step ? 16 : 5, height: 5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: step)
            }
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            switch step {
            case .welcome:
                onStepChange(.shortcuts)
            case .shortcuts:
                onStepChange(.permissions)
            case .permissions:
                onStepChange(.support)
            case .support:
                onStepChange(.community)
            case .community:
                onFinish()
            }
        }
    }

    private func handleSecondaryAction() {
        if step == .welcome {
            onFinish()
        } else if step == .shortcuts {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                onStepChange(.permissions)
            }
        } else if let url = step.secondaryActionURL {
            openURL(url)
        }
    }
}
