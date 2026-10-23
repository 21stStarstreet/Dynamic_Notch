// AirPodsCardViewModel.swift
// DynamicNotch / Features / AirPods
//
// State machine and data model for the AirPods pairing card.
//
// Design Notes
// ────────────
// This ViewModel drives two separate concerns:
//   1. Device Identity  — which AirPods model is connected (determines 3D shape).
//   2. Animation Phase  — sequenced multi-step reveal that mirrors iOS exactly:
//        .hidden → .entering → .revealingCase → .openingLid → .emergingBuds → .showing → .dismissing → .hidden
//   3. Battery Data     — left, right, and case percentages sourced from IOBluetooth.
//
// The `animationPhase` drives all SwiftUI animations via a single discriminated
// enum so every motion is deterministic and unit-testable.

import SwiftUI
import Combine

// MARK: - AirPods Model Detection

enum AirPodsModel: Equatable {
    case airPodsPro2          // AirPods Pro (2nd generation) — oval bud shape
    case airPodsPro           // AirPods Pro (1st generation)
    case airPods4             // AirPods 4 — short stem
    case airPods3             // AirPods 3 — medium stem
    case airPods              // AirPods (1st/2nd gen) — long stem
    case airPodsMax           // AirPods Max — over-ear
    case unknown              // Generic Bluetooth — show compact non-animated card

    init(deviceName: String) {
        let lower = deviceName.lowercased()
        if lower.contains("airpods max") {
            self = .airPodsMax
        } else if lower.contains("airpods pro") {
            // Detect generation hint in name
            if lower.contains("2") || lower.contains("2nd") || lower.contains("2.") {
                self = .airPodsPro2
            } else {
                self = .airPodsPro
            }
        } else if lower.contains("airpods 4") || lower.contains("airpods4") {
            self = .airPods4
        } else if lower.contains("airpods 3") || lower.contains("airpods3") {
            self = .airPods3
        } else if lower.contains("airpods") {
            self = .airPods
        } else {
            self = .unknown
        }
    }

    var supportsFullAnimation: Bool {
        switch self {
        case .unknown: return false
        default: return true
        }
    }

    /// Human-readable display name for the card subtitle
    var displayName: String {
        switch self {
        case .airPodsPro2: return "AirPods Pro (2. Nesil)"
        case .airPodsPro:  return "AirPods Pro"
        case .airPods4:    return "AirPods 4"
        case .airPods3:    return "AirPods 3"
        case .airPods:     return "AirPods"
        case .airPodsMax:  return "AirPods Max"
        case .unknown:     return "Bluetooth Cihazı"
        }
    }

    /// True when buds live in a charging case (Max has no case)
    var hasCase: Bool {
        switch self {
        case .airPodsMax: return false
        default: return true
        }
    }

    /// Bud shape for the 3D renderer
    var budStyle: AirPodsBudStyle {
        switch self {
        case .airPodsPro2, .airPodsPro: return .oval    // stubby in-ear tip
        case .airPods4, .airPods3:       return .shortStem
        case .airPods:                   return .longStem
        case .airPodsMax:                return .overEar
        case .unknown:                   return .oval
        }
    }
}

enum AirPodsBudStyle {
    case oval
    case shortStem
    case longStem
    case overEar
}

// MARK: - Animation Phase

enum AirPodsAnimationPhase: Equatable {
    case hidden
    case entering            // Card slides up from bottom
    case revealingCase       // Case materialises from centre with spring
    case openingLid          // Lid rotates open on X axis (3D perspective)
    case emergingBuds        // Buds fly up out of the open case
    case showing             // Full idle state — battery readout visible
    case dismissing          // Card slides back down
}

// MARK: - Battery State

struct AirPodsBattery: Equatable {
    var left:  Int?          // nil = unknown
    var right: Int?
    var caseLevel: Int?      // nil = no case or unknown

    var hasAnyData: Bool { left != nil || right != nil || caseLevel != nil }

    static let unknown = AirPodsBattery(left: nil, right: nil, caseLevel: nil)
}

// MARK: - ViewModel

@MainActor
final class AirPodsCardViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var phase: AirPodsAnimationPhase = .hidden
    @Published private(set) var model: AirPodsModel = .unknown
    @Published private(set) var deviceName: String = ""
    @Published private(set) var battery: AirPodsBattery = .unknown
    @Published private(set) var isVisible: Bool = false

    // MARK: Private timing constants (milliseconds → seconds)
    //
    // Carefully tuned to match the rhythm Apple uses in iOS 17+ AirPods pairing:
    //   • Card enter:    280 ms spring
    //   • Case reveal:   220 ms spring (100 ms after enter)
    //   • Lid open:      400 ms spring (120 ms after case)
    //   • Buds emerge:   340 ms spring (200 ms after lid mid-point)
    //   • Show:          idle, battery animates in
    //   • Auto-dismiss:  after 6 s total (user can tap to dismiss early)

    private let enterDelay:      TimeInterval = 0.00
    private let caseRevealDelay: TimeInterval = 0.18
    private let lidOpenDelay:    TimeInterval = 0.42
    private let budsEmergeDelay: TimeInterval = 0.72
    private let showDelay:       TimeInterval = 1.05
    private let autoDismissAfter: TimeInterval = 7.0

    private var dismissTask: Task<Void, Never>?
    private var phaseTask:   Task<Void, Never>?

    // MARK: - Public API

    func present(deviceName: String, battery: AirPodsBattery) {
        guard phase == .hidden || phase == .dismissing else {
            // Update battery in-place if already showing same device
            if self.deviceName == deviceName {
                self.battery = battery
            }
            return
        }

        // Cancel any in-flight dismiss
        dismissTask?.cancel()
        phaseTask?.cancel()

        self.deviceName = deviceName
        self.model      = AirPodsModel(deviceName: deviceName)
        self.battery    = battery
        self.isVisible  = true

        phaseTask = Task { [weak self] in
            guard let self else { return }
            await self.runAnimationSequence()
        }
    }

    func dismiss(animated: Bool = true) {
        guard phase != .hidden && phase != .dismissing else { return }
        phaseTask?.cancel()
        dismissTask?.cancel()

        if animated {
            withAnimation(AirPodsSpring.dismiss) {
                phase = .dismissing
            }
            dismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.phase     = .hidden
                    self?.isVisible = false
                }
            }
        } else {
            phase     = .hidden
            isVisible = false
        }
    }

    func updateBattery(_ battery: AirPodsBattery) {
        self.battery = battery
    }

    // MARK: - Private Sequencer

    private func runAnimationSequence() async {
        // Phase 1: Card enters from bottom
        withAnimation(AirPodsSpring.cardEnter) {
            phase = .entering
        }

        try? await sleep(caseRevealDelay)
        guard !Task.isCancelled else { return }

        // Phase 2: Case materialises
        withAnimation(AirPodsSpring.caseReveal) {
            phase = .revealingCase
        }

        try? await sleep(lidOpenDelay - caseRevealDelay)
        guard !Task.isCancelled else { return }

        // Phase 3: Lid rotates open
        withAnimation(AirPodsSpring.lidOpen) {
            phase = .openingLid
        }

        try? await sleep(budsEmergeDelay - lidOpenDelay)
        guard !Task.isCancelled else { return }

        // Phase 4: Buds emerge
        withAnimation(AirPodsSpring.budsEmerge) {
            phase = .emergingBuds
        }

        try? await sleep(showDelay - budsEmergeDelay)
        guard !Task.isCancelled else { return }

        // Phase 5: Idle / showing
        withAnimation(AirPodsSpring.settle) {
            phase = .showing
        }

        // Phase 6: Auto-dismiss after timeout
        try? await sleep(autoDismissAfter)
        guard !Task.isCancelled else { return }

        dismiss(animated: true)
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Animation Curves (Apple-calibrated springs)

enum AirPodsSpring {
    /// Card enters from below — snappy but not bouncy
    static let cardEnter  = Animation.spring(response: 0.52, dampingFraction: 0.80)
    /// Case materialises — quick pop
    static let caseReveal = Animation.spring(response: 0.40, dampingFraction: 0.72)
    /// Lid opens — smooth mechanical rotation
    static let lidOpen    = Animation.spring(response: 0.58, dampingFraction: 0.68)
    /// Buds emerge — organic float upward
    static let budsEmerge = Animation.spring(response: 0.48, dampingFraction: 0.65)
    /// Settle — gentle final rest
    static let settle     = Animation.spring(response: 0.36, dampingFraction: 0.82)
    /// Dismiss — critically damped, no bounce
    static let dismiss    = Animation.spring(response: 0.44, dampingFraction: 0.90)
}
