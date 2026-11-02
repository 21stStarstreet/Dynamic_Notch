//
//  QuickActionManager.swift
//  DynamicNotch
//
//  Created for DynamicNotch Quick Action Customization (Option B - iOS Jiggle Mode).
//  Manages radial and center slot assignments, persistence, and execution.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Quick Action Type

enum QuickActionType: String, CaseIterable, Identifiable, Codable {
    case notes = "notes"
    case reminders = "reminders"
    case timer = "timer"
    case sound = "sound"
    case eject = "eject"
    case focus = "focus"
    case mirror = "mirror"
    case screenshotOCR = "screenshotOCR"
    case spaces = "spaces"
    case clipboard = "clipboard"
    case shelf = "shelf"
    case calendar = "calendar"
    case lockScreen = "lockScreen"
    case mute = "mute"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Hızlı Not"
        case .reminders: return "Anımsatıcı"
        case .timer: return "Zamanlayıcı"
        case .sound: return "Ses Çıkışı"
        case .eject: return "Disk Çıkar"
        case .focus: return "Odak Modu"
        case .mirror: return "Ayna"
        case .screenshotOCR: return "Alıntı & OCR"
        case .spaces: return "Masaüstüler"
        case .clipboard: return "Pano Geçmişi"
        case .shelf: return "Dosya Rafı"
        case .calendar: return "Takvim"
        case .lockScreen: return "Ekranı Kilitle"
        case .mute: return "Sessize Al"
        }
    }

    var helpText: String {
        switch self {
        case .notes: return "Hızlı Not Ekle (⌥⇧N)"
        case .reminders: return "Hızlı Anımsatıcı Ekle (⌥⇧R)"
        case .timer: return "Zamanlayıcı Kur (⌥⇧T)"
        case .sound: return "Ses Giriş ve Çıkışları"
        case .eject: return "Bağlı Diskleri Güvenle Çıkar (⌥⇧E)"
        case .focus: return "Rahatsız Etmeyin"
        case .mirror: return "Hızlı Kamera Kontrolü"
        case .screenshotOCR: return "Ekran Alıntısı & Metin Tanıma"
        case .spaces: return "Masaüstüleri Listele ve Değiştir"
        case .clipboard: return "Kopyalanan Öğeler"
        case .shelf: return "Geçici Dosya Rafı"
        case .calendar: return "Etkinlikler & Takvim"
        case .lockScreen: return "macOS Ekranını Kilitle"
        case .mute: return "Sesi Aç / Kapat"
        }
    }

    var category: String {
        switch self {
        case .notes, .reminders, .clipboard, .calendar:
            return "Üretkenlik"
        case .timer, .mirror, .screenshotOCR, .shelf:
            return "Araçlar"
        case .sound, .eject, .focus, .spaces, .lockScreen, .mute:
            return "Sistem Kontrolü"
        }
    }
}

// MARK: - Quick Action Manager

@MainActor
final class QuickActionManager: ObservableObject {

    static let shared = QuickActionManager()

    // Persistence keys
    private let radialSlotsKey = "DynamicNotch_quickActionRadialSlots_v1"
    private let centerSlotKey = "DynamicNotch_quickActionCenterSlot_v1"

    /// Default radial slots (Positions 0...7 clockwise starting from 12:00)
    static let defaultRadialSlots: [QuickActionType] = [
        .notes,         // 0: Top (0° / 12:00)
        .reminders,     // 1: Top-Right (45° / 1:30)
        .timer,         // 2: Right (90° / 3:00)
        .sound,         // 3: Bottom-Right (135° / 4:30)
        .eject,         // 4: Bottom (180° / 6:00)
        .focus,         // 5: Bottom-Left (225° / 7:30)
        .mirror,        // 6: Left (270° / 9:00)
        .screenshotOCR  // 7: Top-Left (315° / 10:30)
    ]

    /// Default center button slot
    static let defaultCenterSlot: QuickActionType = .spaces

    /// 8 Radial dial slots
    @Published var radialSlots: [QuickActionType] = QuickActionManager.defaultRadialSlots

    /// 1 Center slot
    @Published var centerSlot: QuickActionType = QuickActionManager.defaultCenterSlot

    /// Jiggle / Edit Mode active state
    @Published var isEditMode: Bool = false

    /// Slot index currently selected for the Action Picker modal (0...7 for radial, 8 for center, nil = closed)
    @Published var selectedSlotForPicker: Int? = nil

    private init() {
        loadSlots()
    }

    // MARK: - Persistence

    func loadSlots() {
        if let storedRadialRaw = UserDefaults.standard.stringArray(forKey: radialSlotsKey) {
            let loaded = storedRadialRaw.compactMap { QuickActionType(rawValue: $0) }
            if loaded.count == 8 {
                self.radialSlots = loaded
            } else {
                // If corrupted or partial, fill remaining with defaults
                var combined = loaded
                while combined.count < 8 {
                    combined.append(Self.defaultRadialSlots[combined.count])
                }
                self.radialSlots = Array(combined.prefix(8))
            }
        } else {
            self.radialSlots = Self.defaultRadialSlots
        }

        if let storedCenterRaw = UserDefaults.standard.string(forKey: centerSlotKey),
           let loadedCenter = QuickActionType(rawValue: storedCenterRaw) {
            self.centerSlot = loadedCenter
        } else {
            self.centerSlot = Self.defaultCenterSlot
        }
    }

    func saveSlots() {
        let radialRaw = radialSlots.map { $0.rawValue }
        UserDefaults.standard.set(radialRaw, forKey: radialSlotsKey)
        UserDefaults.standard.set(centerSlot.rawValue, forKey: centerSlotKey)
    }

    // MARK: - Slot Modification

    func setSlot(index: Int, action: QuickActionType) {
        if index >= 0 && index < 8 {
            guard index < radialSlots.count else { return }
            radialSlots[index] = action
            saveSlots()
        } else if index == 8 {
            centerSlot = action
            saveSlots()
        }
    }

    func resetToDefaults() {
        radialSlots = Self.defaultRadialSlots
        centerSlot = Self.defaultCenterSlot
        saveSlots()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    // MARK: - Action Execution

    func execute(action: QuickActionType, viewModel: NotchViewModel) {
        viewModel.windowController?.grantTransitionGrace(duration: 2.0)
        switch action {
        case .notes:
            viewModel.toggleQuickNote()

        case .reminders:
            viewModel.toggleQuickReminder()

        case .timer:
            viewModel.toggleTimerManager()

        case .sound:
            viewModel.openAudioRoutePicker()

        case .eject:
            viewModel.toggleExternalDriveManager()

        case .focus:
            viewModel.toggleFocusMode()

        case .mirror:
            viewModel.toggleCameraMirror()

        case .screenshotOCR:
            viewModel.triggerQuickScreenshotOCR()

        case .spaces:
            withAnimation(.spring(response: 0.42, dampingFraction: 0.66)) {
                viewModel.isShowingSpacesSubpanel = true
            }

        case .clipboard:
            viewModel.toggleClipboardManager()

        case .shelf:
            viewModel.toggleShelf()

        case .calendar:
            viewModel.toggleCalendarManager()

        case .lockScreen:
            lockScreenNow()

        case .mute:
            viewModel.toggleMuteFromHUD()
        }
    }

    // MARK: - Native Lock Screen Bridge

    func lockScreenNow() {
        // macOS Private SACLockScreenImmediate dynamic dispatch
        let lib = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        if let lib = lib {
            defer { dlclose(lib) }
            if let sym = dlsym(lib, "SACLockScreenImmediate") {
                typealias LockFunc = @convention(c) () -> Int32
                let fn = unsafeBitCast(sym, to: LockFunc.self)
                _ = fn()
                return
            }
        }

        // Secondary Native Fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}
