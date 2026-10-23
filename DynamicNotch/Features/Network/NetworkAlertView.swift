// NetworkAlertView.swift
// DynamicNotch / Features / Network
//
// Phase 2 (Faz 5): Apple-grade Network HUD for Wi-Fi and VPN events.
// Displays dual-layer BadgeIconView, status title & SSID / Tunnel subtitle,
// and a live ticking VPN uptime counter pill (MM:SS).

import SwiftUI

struct NetworkAlertView: View {

    enum AlertType {
        case wifi(ssid: String?, connected: Bool)
        case vpn(tunnelName: String, connectedDate: Date)
    }

    let type: AlertType

    init(ssid: String?, connected: Bool, isVPN: Bool = false) {
        if isVPN {
            self.type = .vpn(tunnelName: "WireGuard Tunnel", connectedDate: Date())
        } else {
            self.type = .wifi(ssid: ssid, connected: connected)
        }
    }

    init(tunnelName: String, connectedDate: Date) {
        self.type = .vpn(tunnelName: tunnelName, connectedDate: connectedDate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: Clean Network / Wi-Fi Icon (no background capsule)
            Image(systemName: iconName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(badgeColor)
                .frame(width: 32, height: 32)

            // Middle: Status Header and Network / Tunnel Name
            VStack(alignment: .leading, spacing: 2) {
                Text(statusHeader)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.60))
                    .lineLimit(1)

                Text(networkName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            // Right: Live VPN Uptime Counter OR Status Indicator Dot
            switch type {
            case .vpn(_, let connectedDate):
                VPNUptimeView(connectedDate: connectedDate)

            case .wifi(_, let connected):
                Circle()
                    .fill(connected ? Color.notchGreen : Color.notchRed)
                    .frame(width: 8, height: 8)
                    .shadow(color: (connected ? Color.notchGreen : Color.notchRed).opacity(0.4), radius: 3)
            }
        }
    }

    private var iconName: String {
        switch type {
        case .vpn:
            return "network.badge.shield.half.filled"
        case .wifi(_, let connected):
            return connected ? "wifi" : "wifi.slash"
        }
    }

    private var badgeColor: Color {
        switch type {
        case .vpn:
            return .notchIndigo
        case .wifi(_, let connected):
            return connected ? .notchGreen : .notchRed
        }
    }

    private var statusHeader: String {
        switch type {
        case .vpn:
            return "VPN Bağlandı"
        case .wifi(_, let connected):
            if connected {
                return Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "WiFi ağına bağlanıldı" : "Connected to Wi-Fi"
            } else {
                return Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Bağlantı Kesildi" : "Disconnected"
            }
        }
    }

    private var networkName: String {
        switch type {
        case .vpn(let tunnelName, _):
            return tunnelName.isEmpty ? "Güvenli Tünel" : tunnelName
        case .wifi(let ssid, let connected):
            if let ssid, !ssid.isEmpty, ssid != "İnternet Bağlandı" {
                return ssid
            }
            return connected ? (Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Wi-Fi Ağı" : "Wi-Fi Network") : (Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Wi-Fi Kapalı" : "Wi-Fi Off")
        }
    }
}

// MARK: - Live VPN Uptime Counter View (MM:SS or HH:MM:SS)

struct VPNUptimeView: View {

    let connectedDate: Date
    var isCompact: Bool = false

    @State private var uptimeString: String = "00:00"
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if isCompact {
                Text(uptimeString)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.notchIndigo)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            } else {
                HStack(spacing: 5.5) {
                    Circle()
                        .fill(Color.notchIndigo)
                        .frame(width: 5, height: 5)

                    Text(uptimeString)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.notchIndigo.opacity(0.20))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.notchIndigo.opacity(0.38), lineWidth: 1.0)
                        )
                )
            }
        }
        .onReceive(timer) { _ in
            uptimeString = formatUptime(from: connectedDate)
        }
        .onAppear {
            uptimeString = formatUptime(from: connectedDate)
        }
    }

    private func formatUptime(from date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        let hours   = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
