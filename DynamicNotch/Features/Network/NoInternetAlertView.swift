// NoInternetAlertView.swift
// DynamicNotch / Features / Network
//
// Apple-grade Interactive System Dialog for internet connectivity loss.
// Displays pulsing radar icon, clear typography, and liquid glass action buttons
// (OK to dismiss, Settings to launch macOS Network Preferences).

import SwiftUI
import AppKit

struct NoInternetAlertView: View {

    let onDismiss: () -> Void
    let onSettings: () -> Void

    @State private var isPulsing: Bool = false
    @State private var isHoveringOK: Bool = false
    @State private var isHoveringSettings: Bool = false

    private let warningAmber = Color(red: 0.98, green: 0.58, blue: 0.12)
    private let appleBlue    = Color(red: 0.04, green: 0.48, blue: 1.0)

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var titleText: String {
        isTurkish ? "İnternet Bağlantısı Yok" : "No Internet Connection"
    }

    private var subtitleText: String {
        isTurkish
            ? "Wi-Fi veya Ethernet ağına bağlanın."
            : "Connect to Wi-Fi or Ethernet to continue."
    }

    private var okText: String {
        isTurkish ? "Tamam" : "OK"
    }

    private var settingsText: String {
        isTurkish ? "Ayarlar" : "Settings"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // MARK: - Left: Wi-Fi Alert Icon
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(warningAmber)
                .frame(width: 30, height: 30)
                .opacity(isPulsing ? 0.65 : 1.0)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.1)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }

            // MARK: - Center: Title & Subtitle Stack
            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(2)
                    .lineSpacing(1.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // MARK: - Right: Stacked Action Buttons (Settings on Top, Tamam on Bottom)
            VStack(spacing: 5) {
                // Primary: Settings Button
                Button {
                    onSettings()
                } label: {
                    Text(settingsText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 68, height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isHoveringSettings ? appleBlue.opacity(0.85) : appleBlue)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringSettings = $0 }

                // Secondary: Tamam / OK Button
                Button {
                    onDismiss()
                } label: {
                    Text(okText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.90))
                        .frame(width: 68, height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isHoveringOK ? 0.22 : 0.12))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringOK = $0 }
            }
            .frame(width: 68)
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
    }
}
