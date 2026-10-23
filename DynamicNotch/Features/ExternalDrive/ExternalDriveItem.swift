// ExternalDriveItem.swift
// DynamicNotch / Features / ExternalDrive
//
// Model representing a mounted external drive, SSD, USB volume, SD card, or DMG
// with full capacity metrics, Apple system iconography, and ejection capabilities.

import AppKit
import SwiftUI

enum ExternalDriveType: String, Equatable, CaseIterable {
    case ssd = "Harici SSD"
    case usb = "USB Sürücü"
    case sdCard = "SD Kart"
    case diskImage = "Disk İmajı"
    case network = "Ağ Sürücüsü"
    case other = "Harici Disk"

    var iconName: String {
        switch self {
        case .ssd: return "externaldrive.connected.to.line.below.fill"
        case .usb: return "externaldrive.fill"
        case .sdCard: return "sdcard.fill"
        case .diskImage: return "opticaldiscdrive.fill"
        case .network: return "network"
        case .other: return "externaldrive.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .ssd: return Color(red: 0.20, green: 0.60, blue: 1.0) // System Blue
        case .usb: return Color(red: 0.35, green: 0.78, blue: 0.98) // Cyan
        case .sdCard: return Color(red: 1.0, green: 0.60, blue: 0.0) // Orange
        case .diskImage: return Color(red: 0.65, green: 0.65, blue: 0.70) // Silver/Gray
        case .network: return Color(red: 0.35, green: 0.35, blue: 0.85) // Indigo
        case .other: return Color(red: 0.20, green: 0.60, blue: 1.0)
        }
    }
}

struct ExternalDriveItem: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let mountPath: String
    let totalCapacityBytes: Int64
    let availableCapacityBytes: Int64
    let usedCapacityBytes: Int64
    let usedPercentage: Double
    let driveType: ExternalDriveType
    let isEjectable: Bool
    let isRemovable: Bool

    var totalCapacityFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalCapacityBytes, countStyle: .file)
    }

    var availableCapacityFormatted: String {
        ByteCountFormatter.string(fromByteCount: availableCapacityBytes, countStyle: .file)
    }

    var usedCapacityFormatted: String {
        ByteCountFormatter.string(fromByteCount: usedCapacityBytes, countStyle: .file)
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: mountPath)
    }

    static func == (lhs: ExternalDriveItem, rhs: ExternalDriveItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.mountPath == rhs.mountPath &&
        lhs.totalCapacityBytes == rhs.totalCapacityBytes &&
        lhs.availableCapacityBytes == rhs.availableCapacityBytes &&
        lhs.usedCapacityBytes == rhs.usedCapacityBytes &&
        lhs.driveType == rhs.driveType &&
        lhs.isEjectable == rhs.isEjectable
    }
}
