// HotspotItem.swift
// DynamicNotch / Features / Hotspot
//
// Apple-grade data model representing an active Personal Hotspot connection
// (iPhone or iPad tethering) with live battery level, charging status,
// cellular network standard (5G/LTE), and signal telemetry.

import Foundation
import SwiftUI

struct HotspotItem: Identifiable, Equatable {
    var id: String
    var deviceName: String
    var batteryLevel: Int? // 0 … 100, or nil if unknown
    var isCharging: Bool
    var cellularType: String? // "5G", "LTE", or nil if unknown
    var signalBars: Int? // 1 … 4, or nil if unknown
    var connectedDate: Date? // nil if connection start time is unknown
    var isConnected: Bool
    var statusDescription: String?

    init(
        id: String = UUID().uuidString,
        deviceName: String,
        batteryLevel: Int? = nil,
        isCharging: Bool = false,
        cellularType: String? = nil,
        signalBars: Int? = nil,
        connectedDate: Date? = nil,
        isConnected: Bool = true,
        statusDescription: String? = nil
    ) {
        self.id = id
        self.deviceName = deviceName.isEmpty ? "iPhone" : deviceName
        if let batteryLevel {
            self.batteryLevel = max(0, min(100, batteryLevel))
        } else {
            self.batteryLevel = nil
        }
        self.isCharging = isCharging
        self.cellularType = cellularType
        if let signalBars {
            self.signalBars = max(1, min(4, signalBars))
        } else {
            self.signalBars = nil
        }
        self.connectedDate = connectedDate
        self.isConnected = isConnected
        self.statusDescription = statusDescription
    }

    // MARK: - Battery Helpers & Visual State

    var isLowBattery: Bool {
        guard let batteryLevel else { return false }
        return batteryLevel <= 20
    }

    var isCriticalBattery: Bool {
        guard let batteryLevel else { return false }
        return batteryLevel <= 10
    }

    var batteryFraction: Double {
        guard let batteryLevel else { return 0.0 }
        return Double(batteryLevel) / 100.0
    }

    var batteryColor: Color {
        if !isConnected {
            return Color.white.opacity(0.4)
        }
        if isCriticalBattery {
            return Color(red: 1.0, green: 0.23, blue: 0.19) // Apple Red
        } else if isLowBattery {
            return Color(red: 1.0, green: 0.60, blue: 0.0) // Apple Orange
        } else {
            return Color.notchGreen // Apple Green
        }
    }

    var batteryIconName: String {
        guard let batteryLevel else {
            return isCharging ? "battery.100percent.bolt" : "battery.100percent"
        }
        if isCharging {
            if batteryLevel >= 90 { return "battery.100percent.bolt" }
            if batteryLevel >= 65 { return "battery.75percent.bolt" }
            if batteryLevel >= 40 { return "battery.50percent.bolt" }
            if batteryLevel >= 15 { return "battery.25percent.bolt" }
            return "battery.0percent.bolt"
        } else {
            if batteryLevel >= 90 { return "battery.100percent" }
            if batteryLevel >= 65 { return "battery.75percent" }
            if batteryLevel >= 40 { return "battery.50percent" }
            if batteryLevel >= 15 { return "battery.25percent" }
            return "battery.0percent"
        }
    }

    var percentageFormatted: String {
        guard let batteryLevel else {
            return "%--"
        }
        let isTurkish = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
        return isTurkish ? "%\(batteryLevel)" : "\(batteryLevel)%"
    }

    var uptimeFormatted: String? {
        guard let connectedDate else { return nil }
        let elapsed = max(0, Date().timeIntervalSince(connectedDate))
        let minutes = Int(elapsed / 60)
        let isTurkish = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
        if minutes < 1 {
            return isTurkish ? "Az önce" : "Just now"
        } else if minutes < 60 {
            return isTurkish ? "\(minutes) dk" : "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remMin = minutes % 60
            if remMin == 0 {
                return isTurkish ? "\(hours) sa" : "\(hours) hr"
            } else {
                return isTurkish ? "\(hours) sa \(remMin) dk" : "\(hours) hr \(remMin) min"
            }
        }
    }

    static let empty = HotspotItem(
        deviceName: "iPhone",
        batteryLevel: nil,
        isConnected: false
    )

    static func disconnected(currentWifiSSID: String?) -> HotspotItem {
        HotspotItem(
            deviceName: "Kişisel Erişim Noktası",
            batteryLevel: nil,
            isCharging: false,
            cellularType: nil,
            signalBars: nil,
            connectedDate: nil,
            isConnected: false,
            statusDescription: currentWifiSSID != nil ? "\"\(currentWifiSSID!)\" Wi-Fi ağına bağlı" : "Bağlı Değil"
        )
    }
}
