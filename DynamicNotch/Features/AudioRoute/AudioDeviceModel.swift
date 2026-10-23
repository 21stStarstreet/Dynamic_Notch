// AudioDeviceModel.swift
// DynamicNotch / Features / AudioRoute
//
// Immutable value types for CoreAudio output devices and transport types.

import Foundation
import CoreAudio
import SwiftUI

// MARK: - Transport Type

enum AudioDeviceTransportType: Equatable {
    case builtIn
    case bluetooth
    case airPlay
    case usb
    case hdmi
    case unknown

    var iconName: String {
        switch self {
        case .builtIn:   return "laptopcomputer"
        case .bluetooth: return "headphones"
        case .airPlay:   return "airplayaudio"
        case .usb:       return "cable.connector.horizontal"
        case .hdmi:      return "display"
        case .unknown:   return "speaker.wave.2"
        }
    }
}

// MARK: - Audio Device Direction

enum AudioDeviceDirection: String, CaseIterable, Identifiable {
    case output = "Çıkış"
    case input  = "Giriş"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .output: return "speaker.wave.2.fill"
        case .input:  return "mic.fill"
        }
    }
}

// MARK: - Audio Device Item

struct AudioDeviceItem: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportType: AudioDeviceTransportType
    let isCurrentDefault: Bool
    var isInput: Bool = false

    var sfSymbol: String {
        let lower = name.lowercased()
        if isInput {
            if lower.contains("airpods") {
                return "airpodspro"
            } else if lower.contains("macbook") || lower.contains("built-in") || lower.contains("dahili") {
                return "mic.fill"
            }
            return "mic.fill"
        } else {
            if lower.contains("airpods max") {
                return "airpodsmax"
            } else if lower.contains("airpods pro") {
                return "airpodspro"
            } else if lower.contains("airpods") {
                return "airpods"
            } else if lower.contains("beats") {
                return "beats.headphones"
            } else if lower.contains("macbook") || lower.contains("hoparlör") || lower.contains("speaker") || lower.contains("internal") {
                return "laptopcomputer"
            } else if lower.contains("display") || lower.contains("tv") || lower.contains("hdmi") || lower.contains("monitör") {
                return "display"
            }
            return transportType.iconName
        }
    }

    static func == (lhs: AudioDeviceItem, rhs: AudioDeviceItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.uid == rhs.uid &&
        lhs.name == rhs.name &&
        lhs.transportType == rhs.transportType &&
        lhs.isCurrentDefault == rhs.isCurrentDefault &&
        lhs.isInput == rhs.isInput
    }
}

typealias AudioOutputDevice = AudioDeviceItem
