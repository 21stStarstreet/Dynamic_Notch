// SatelliteOrbWindowController.swift
// DynamicNotch / Features / SatelliteOrb
//
// Manages the independent NSPanel for the Satellite Orb.
// Positions the orb tightly to the right of the hardware notch.
// Passes all mouse events through seamlessly as a quiet companion indicator.

import AppKit
import SwiftUI
import Combine

@MainActor
final class SatelliteOrbWindowController: NSObject {

    // MARK: - Properties

    private var panel: NotchPanel!
    private let viewModel: SatelliteOrbViewModel
    private weak var notchViewModel: NotchViewModel?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init / Deinit

    init(viewModel: SatelliteOrbViewModel, notchViewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.notchViewModel = notchViewModel
        super.init()

        setupPanel()
        observeStateChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let notchWidth = notchViewModel?.pillSize.width ?? NotchPositionCalculator.notchBaseWidth(for: screen)
        let canvasFrame = NotchPositionCalculator.orbCanvasFrame(for: screen, notchWidth: notchWidth)

        panel = NotchPanel(
            contentRect: canvasFrame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        panel.isFloatingPanel             = true
        panel.becomesKeyOnlyIfNeeded      = true
        panel.isMovable                   = false
        panel.isMovableByWindowBackground = false
        panel.level                       = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)

        panel.backgroundColor         = .clear
        panel.isOpaque                = false
        panel.hasShadow               = false
        panel.ignoresMouseEvents      = true   // Fully transparent to cursor; purely a visual status indicator
        panel.acceptsMouseMovedEvents = false
        panel.isReleasedWhenClosed    = false
        panel.canHide                 = false
        panel.hidesOnDeactivate       = false
        panel.collectionBehavior      = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let rootView = SatelliteOrbContainerView(viewModel: viewModel)
        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        SkyLightSpaceBridge.shared.attachToLockScreenSpace(windowNumber: panel.windowNumber)
        panel.orderFrontRegardless()
    }

    // MARK: - Position Updating

    private func updatePanelPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let notchWidth = notchViewModel?.pillSize.width else { return }

        let targetFrame = NotchPositionCalculator.orbCanvasFrame(for: screen, notchWidth: notchWidth)
        if panel.frame.origin != targetFrame.origin {
            panel.setFrameOrigin(targetFrame.origin)
        }
    }

    // MARK: - State Observers

    private func observeStateChanges() {
        guard let notchVM = notchViewModel else { return }

        // 1. Follow the main notch width dynamically as it morphs
        notchVM.$pillSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelPosition()
            }
            .store(in: &cancellables)

        // 2. Observe orb visibility changes
        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.updatePanelPosition()
                    self.panel.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)

        // 3. Screen resolution / arrangement changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelPosition()
            }
            .store(in: &cancellables)
    }
}
