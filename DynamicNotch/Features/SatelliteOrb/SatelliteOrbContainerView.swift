// SatelliteOrbContainerView.swift
// DynamicNotch / Features / SatelliteOrb
//
// Root SwiftUI container for the Satellite Orb.
// Hosts the passive circular satellite indicator alongside the dynamic notch.

import SwiftUI

struct SatelliteOrbContainerView: View {

    @ObservedObject var viewModel: SatelliteOrbViewModel

    private var topOffset: CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let notchH = NotchPositionCalculator.effectiveNotchHeight(for: screen)
        return max(2.0, (notchH - viewModel.activeSize.height) / 2.0)
    }

    var body: some View {
        Group {
            if let content = viewModel.orbContent {
                SatelliteOrbView(content: content)
                    .offset(y: topOffset)
                    .scaleEffect(viewModel.isVisible ? 1.0 : 0.35, anchor: .top)
                    .opacity(viewModel.isVisible ? 1.0 : 0.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
