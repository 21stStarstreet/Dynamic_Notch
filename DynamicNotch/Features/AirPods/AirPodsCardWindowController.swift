// AirPodsCardWindowController.swift
// DynamicNotch / Features / AirPods
//
// Owns the dedicated borderless NSPanel for the AirPods pairing card.
//
// Window Architecture Decision
// ─────────────────────────────
// The AirPods card is intentionally hosted in its OWN NSPanel, separate from
// the notch NSPanel. Reasons:
//
//   1. The card sits at the BOTTOM CENTRE of the screen, not the top.
//      Sharing one window would require the window to cover the entire screen,
//      which breaks cursor hit-testing for everything in between.
//
//   2. The card needs to receive clicks to dismiss itself — something the notch
//      window intentionally passes through when idle.
//
//   3. A separate window gives us independent z-ordering without disrupting the
//      notch window's `canJoinAllSpaces` / `stationary` behavior.
//
// The panel:
//   • Uses `.ultraThinMaterial` so it composites against the live wallpaper.
//   • Lives at `NSWindow.Level.floating + 10` (above normal windows, below screensaver).
//   • Is centred horizontally and positioned so its bottom edge lands 28pt above the Dock.
//   • Has `ignoresMouseEvents = false` ONLY while visible, so taps/clicks work.

import AppKit
import SwiftUI
import Combine

@MainActor
final class AirPodsCardWindowController: NSObject {

    // MARK: - Properties

    private var panel: NSPanel?
    private let viewModel: AirPodsCardViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(viewModel: AirPodsCardViewModel) {
        self.viewModel = viewModel
        super.init()
        observeVisibility()
    }

    // MARK: - Visibility Observer

    private func observeVisibility() {
        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                if visible {
                    self?.ensurePanelExists()
                    self?.panel?.ignoresMouseEvents = false
                } else {
                    // After dismissal animation completes, allow events to pass through
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                        self?.panel?.ignoresMouseEvents = true
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel Creation

    private func ensurePanelExists() {
        if panel != nil { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Card intrinsic size (matches AirPodsCardView width + generous height)
        let cardWidth:  CGFloat = 340
        let cardHeight: CGFloat = 420

        // Position: centred horizontally, bottom edge 28pt above the Dock area
        let dockOffset:  CGFloat = 100   // rough Dock height; card clears it
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - cardWidth / 2 + screenFrame.origin.x
        let y = screenFrame.origin.y + dockOffset

        let panelFrame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)

        let p = NSPanel(
            contentRect: panelFrame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        p.isFloatingPanel             = true
        p.becomesKeyOnlyIfNeeded      = true
        p.isMovable                   = false
        p.isMovableByWindowBackground = false
        p.level                       = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 10
        )
        p.backgroundColor             = .clear
        p.isOpaque                    = false
        p.hasShadow                   = false
        p.ignoresMouseEvents          = false
        p.acceptsMouseMovedEvents     = true
        p.isReleasedWhenClosed        = false
        p.canHide                     = false
        p.hidesOnDeactivate           = false
        p.collectionBehavior          = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        // Host the SwiftUI card
        let rootView = AirPodsCardView(viewModel: viewModel)
            .frame(width: cardWidth, height: cardHeight)
            .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        p.contentView = hostingView

        self.panel = p
        p.orderFrontRegardless()
    }
}
