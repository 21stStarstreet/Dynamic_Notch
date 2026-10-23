// Color+Extensions.swift
// DynamicNotch / Utilities / Extensions

import SwiftUI
import AppKit

extension Color {
    /// Pure pitch black matching the physical MacBook notch bezel.
    static let notchBlack = Color(red: 0, green: 0, blue: 0)

    /// Subtle dark surface used for inner cards and placeholders.
    static let notchSurface = Color(white: 0.14)

    // MARK: - Phase 2 Semantic Status Colors

    static let notchGreen  = Color(red: 0.18, green: 0.85, blue: 0.40)  // Charging, connected, full
    static let notchRed    = Color(red: 0.95, green: 0.27, blue: 0.27)  // Low battery, mute, recording
    static let notchOrange = Color(red: 1.00, green: 0.62, blue: 0.10)  // Timer, VPN uptime
    static let notchBlue   = Color(red: 0.20, green: 0.55, blue: 1.00)  // Download, primary action
    static let notchIndigo = Color(red: 0.40, green: 0.40, blue: 0.95)  // VPN badge, Focus / DND

    // MARK: - Phase 2 Typography Colors

    static let notchTitle    = Color.white
    static let notchSubtitle = Color.white.opacity(0.55)
    static let notchMuted    = Color.white.opacity(0.30)

    /// Creates a SwiftUI Color from a hex integer (e.g. 0x34C759).
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex         & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
