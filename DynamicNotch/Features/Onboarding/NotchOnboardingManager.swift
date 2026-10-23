// NotchOnboardingManager.swift
// DynamicNotch / Features / Onboarding / Managers
//
// Thread-safe coordinator for the first launch onboarding lifecycle,
// step transitions, user defaults persistence, and post-onboarding activity restoration.

import Foundation
import SwiftUI
import Combine

@MainActor
final class NotchOnboardingManager: ObservableObject {

    static let shared = NotchOnboardingManager()

    private let userDefaultsKey = "hasSeenOnboarding"

    @Published private(set) var currentStep: OnboardingStep? = nil
    @Published private(set) var isGreetingActive: Bool = false

    var hasSeenOnboarding: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    var isOnboardingActive: Bool {
        currentStep != nil
    }

    var isGreetingOrOnboardingActive: Bool {
        isOnboardingActive || isGreetingActive
    }

    private init() {}

    // MARK: - Lifecycle

    /// Checks if the user is launching the application for the first time.
    /// If not seen onboarding -> shows full 4-step onboarding.
    /// If already seen onboarding -> shows 1-round welcome greeting!
    func checkFirstLaunch() {
        if !hasSeenOnboarding {
            show(step: .welcome)
        } else {
            showWelcomeGreeting()
        }
    }

    /// Presents only the cursive Welcome handwriting for 1 round on normal app launches.
    func showWelcomeGreeting() {
        self.isGreetingActive = true
        self.currentStep = nil
        NotchViewModel.shared?.presentWelcomeGreeting()
    }

    /// Concludes the 1-round welcome greeting and returns notch to normal behavior.
    func finishWelcomeGreeting() {
        self.isGreetingActive = false
        NotchViewModel.shared?.dismissWelcomeGreeting()
    }

    /// Presents a specific onboarding step directly into the notch.
    func show(step: OnboardingStep) {
        self.isGreetingActive = false
        self.currentStep = step
        NotchViewModel.shared?.presentOnboarding(step: step)
    }

    /// Moves forward to the next step.
    func nextStep() {
        guard let current = currentStep else { return }
        switch current {
        case .welcome:
            show(step: .shortcuts)
        case .shortcuts:
            show(step: .permissions)
        case .permissions:
            show(step: .support)
        case .support:
            show(step: .community)
        case .community:
            finishOnboarding()
        }
    }

    /// Concludes the onboarding flow, writes the flag to UserDefaults,
    /// and smoothly collapses or restores background activities.
    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
        self.currentStep = nil
        self.isGreetingActive = false
        NotchViewModel.shared?.dismissOnboarding()
    }

    /// Allows replaying the onboarding flow at any time (e.g. from Settings or Help menu).
    func restartOnboarding() {
        show(step: .welcome)
    }
}
