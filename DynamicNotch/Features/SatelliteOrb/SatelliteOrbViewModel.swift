// SatelliteOrbViewModel.swift
// DynamicNotch / Features / SatelliteOrb
//
// State machine coordinating the independent Satellite Orb (Detached Island Bubble)
// when two Live Activities occur simultaneously (e.g., Music playing while Timer is running).

import SwiftUI
import Combine

@MainActor
final class SatelliteOrbViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var orbContent: NotchState.ContentType?
    @Published private(set) var isVisible: Bool = false
    @Published private(set) var isExpanded: Bool = false
    @Published private(set) var isHovered: Bool = false
    @Published private(set) var activeSize: CGSize = CGSize(width: 28.0, height: 28.0)

    /// Compact circular diameter matching iOS Dynamic Island secondary indicator
    static let compactDiameter: CGFloat = 28.0

    // MARK: - Dependencies

    weak var notchViewModel: NotchViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var dismissDebounceItem: DispatchWorkItem?

    // MARK: - Init

    init(notchViewModel: NotchViewModel) {
        self.notchViewModel = notchViewModel
        bindObservers()
    }

    // MARK: - Binding

    private func bindObservers() {
        guard let vm = notchViewModel else { return }

        Publishers.CombineLatest4(
            vm.$activeNowPlaying,
            vm.$activeDownload,
            vm.$activeTimerActivity,
            vm.$isScreenLocked
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.recalculate()
        }
        .store(in: &cancellables)
    }

    // MARK: - State Recalculation

    func recalculate() {
        guard let vm = notchViewModel else { return }

        // Hide completely on lock screen
        if vm.isScreenLocked {
            withAnimation(SpringConfig.orbDismiss) {
                self.isVisible = false
                self.isExpanded = false
            }
            return
        }

        // Collect all active live activities sorted by priority (highest to lowest)
        let candidates = [vm.activeTimerActivity, vm.activeDownload, vm.activeNowPlaying]
            .compactMap { $0 }
            .sorted(by: { $0.priority > $1.priority })

        // When 2 or more Live Activities are running concurrently, the second one belongs to the Satellite Orb!
        if candidates.count >= 2 {
            let secondary = candidates[1]
            let compact = compactSize(for: secondary)

            if !isVisible || orbContent != secondary {
                withAnimation(SpringConfig.orbAppear) {
                    self.orbContent = secondary
                    self.isVisible = true
                    if !self.isExpanded {
                        self.activeSize = compact
                    } else {
                        self.activeSize = self.expandedSize(for: secondary)
                    }
                }
            } else {
                // In-place data update
                self.orbContent = secondary
            }
        } else {
            // Less than 2 activities active -> smoothly retract & hide the Satellite Orb
            if isVisible {
                dismissDebounceItem?.cancel()
                dismissDebounceItem = nil
                withAnimation(SpringConfig.orbDismiss) {
                    self.isVisible = false
                    self.isExpanded = false
                    self.isHovered = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, !self.isVisible else { return }
                    self.orbContent = nil
                }
            }
        }
    }

    // MARK: - Hover Controls (Passive Satellite Indicator — No Expansion)

    func setHovered(_ hovering: Bool) {
        // The Satellite Orb is purely a passive indicator ("o orada sadece var olacak");
        // hover expansion is intentionally disabled.
        isHovered = hovering
    }

    func expand() {
        // Expansion disabled per user request
    }

    func collapse() {
        // Expansion disabled per user request
    }

    func toggleExpansion() {
        // Expansion disabled per user request
    }

    // MARK: - Sizing Metrics

    func compactSize(for content: NotchState.ContentType) -> CGSize {
        CGSize(width: Self.compactDiameter, height: Self.compactDiameter)
    }

    func expandedSize(for content: NotchState.ContentType) -> CGSize {
        switch content {
        case .timer:
            return CGSize(width: 320.0, height: 114.0)
        case .nowPlaying:
            return CGSize(width: 330.0, height: 120.0)
        case .download:
            return CGSize(width: 310.0, height: 88.0)
        default:
            return CGSize(width: 310.0, height: 100.0)
        }
    }
}
