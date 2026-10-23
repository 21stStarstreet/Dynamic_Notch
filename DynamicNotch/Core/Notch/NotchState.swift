// NotchState.swift
// DynamicNotch / Core / Notch
//
// The canonical state machine for the notch.
// Every event that can be shown passes through ContentType; every visible state
// of the window is described by NotchState.
//
// Design notes
// ─────────────
// • EventCategory cleanly separates perpetual LiveActivities (music, download)
//   from transient Alerts so the Priority Queue in NotchViewModel can make the
//   right scheduling decisions without inspecting individual case names.
//
// • priority: Int is the single source of truth for Alert ordering inside the
//   queue.  Higher value == shown first when multiple alerts are pending.
//
// • defaultDuration is nil for LiveActivities (they never auto-dismiss) and a
//   concrete TimeInterval for every Alert.
//
// • NowPlayingInfo and DownloadItem are value types (struct) so that equality
//   checks in Equatable conformance are cheap and mutation is copy-on-write.

import Foundation
import AppKit
import SwiftUI

// MARK: - Supporting Models

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsedTime: TimeInterval
    var artwork: NSImage?
    var isPlaying: Bool
    var appName: String
    var accentColor: Color
    var timestamp: Date
    var isFavorited: Bool
    var trackID: String?

    init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        artwork: NSImage?,
        isPlaying: Bool,
        appName: String,
        accentColor: Color? = nil,
        isFavorited: Bool = false,
        trackID: String? = nil,
        timestamp: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.appName = appName
        self.isFavorited = isFavorited
        self.trackID = trackID
        self.timestamp = timestamp

        if let accentColor {
            self.accentColor = accentColor
        } else if let artwork, let dom = artwork.dominantAccentColor() {
            self.accentColor = Color(nsColor: dom)
        } else {
            self.accentColor = Color(red: 0.98, green: 0.42, blue: 0.62)
        }
    }

    /// True live playback position extrapolated from the last update timestamp.
    /// Guarantees that elapsed time never freezes or resets to 00:00 when moving between
    /// the Main Notch and the Satellite Orb.
    var currentLiveElapsed: TimeInterval {
        guard isPlaying else { return elapsedTime }
        let drift = max(0, Date().timeIntervalSince(timestamp))
        let total = elapsedTime + drift
        return duration > 0 ? min(total, duration) : total
    }

    mutating func setArtwork(_ image: NSImage?) {
        self.artwork = image
        if let image, let dom = image.dominantAccentColor() {
            self.accentColor = Color(nsColor: dom)
        }
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.duration == rhs.duration &&
        lhs.elapsedTime == rhs.elapsedTime &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.appName == rhs.appName &&
        lhs.artwork === rhs.artwork &&
        lhs.accentColor == rhs.accentColor &&
        lhs.isFavorited == rhs.isFavorited &&
        lhs.trackID == rhs.trackID
    }

    static let empty = NowPlayingInfo(
        title: "", artist: "", album: "",
        duration: 0, elapsedTime: 0,
        artwork: nil, isPlaying: false, appName: "",
        accentColor: .white,
        timestamp: Date()
    )
}

struct DownloadItem: Equatable {
    var id: String            // stable identifier (file path / UUID)
    var filename: String      // display name without .download extension
    var progress: Double      // 0.0 … 1.0
    var totalBytes: Int64
    var downloadedBytes: Int64
    var speedBytesPerSec: Double = 0.0
    var sourceFolderName: String = "Downloads"

    static let empty = DownloadItem(
        id: "", filename: "", progress: 0,
        totalBytes: 0, downloadedBytes: 0,
        speedBytesPerSec: 0, sourceFolderName: "Downloads"
    )
}

struct TimerItem: Equatable, Identifiable {
    var id: UUID
    var title: String
    var totalDuration: TimeInterval
    var endDate: Date
    var isPaused: Bool
    var remainingWhenPaused: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String = "Timer",
        totalDuration: TimeInterval,
        endDate: Date? = nil,
        isPaused: Bool = false,
        remainingWhenPaused: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.totalDuration = totalDuration
        self.endDate = endDate ?? Date().addingTimeInterval(totalDuration)
        self.isPaused = isPaused
        self.remainingWhenPaused = remainingWhenPaused
    }

    var remaining: TimeInterval {
        if isPaused, let r = remainingWhenPaused {
            return max(0, r)
        }
        return max(0, endDate.timeIntervalSinceNow)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, 1.0 - (remaining / totalDuration)))
    }

    var isExpired: Bool {
        return remaining <= 0.05
    }

    var formattedRemaining: String {
        let rem = remaining
        let hours = Int(rem) / 3600
        let minutes = (Int(rem) % 3600) / 60
        let seconds = Int(rem) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var compactFormattedRemaining: String {
        let rem = remaining
        let hours = Int(rem) / 3600
        let minutes = (Int(rem) % 3600) / 60
        let seconds = Int(rem) % 60
        if hours >= 1 {
            return String(format: "%02d:%02d", hours, minutes)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    static let empty = TimerItem(totalDuration: 0)
}

struct ScreenshotItem: Equatable, Identifiable {
    var id: UUID = UUID()
    var fileURL: URL
    var thumbnail: NSImage
    var createdAt: Date = Date()
    var recognizedText: String? = nil

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.fileURL == rhs.fileURL && lhs.recognizedText == rhs.recognizedText
    }
}

// MARK: - Event Category

enum EventCategory {
    /// Perpetual: lives until explicitly ended (music stops, download finishes).
    case liveActivity
    /// Transient: auto-dismisses after `defaultDuration`; can be queued.
    case alert
}

// MARK: - Notch State

enum NotchState: Equatable {
    case idle
    case expanding(ContentType)
    case expanded(ContentType)
    case collapsing

    // MARK: Content Types

    enum ContentType: Equatable {

        // ── LiveActivities (perpetual) ──────────────────────────────────────
        case nowPlaying(NowPlayingInfo)
        case download(DownloadItem)
        case timer(TimerItem)
        case externalDrive([ExternalDriveItem])
        case calendarEvent(CalendarEventItem)
        case hotspot(HotspotItem)
        case screenRecording(Date)
        case onboarding(OnboardingStep)
        case welcomeGreeting

        // ── Alerts (transient) ─────────────────────────────────────────────
        case batteryLow
        case batteryCharging
        case batteryFull
        case bluetoothConnected(String)       // associated: device name
        case bluetoothDisconnected(String)
        case wifiConnected(String)            // associated: SSID
        case wifiDisconnected
        case vpnConnected(String, Date)       // associated: tunnelName, connectedDate
        case focusChanged(Bool)               // true = Focus/DND On, false = Off
        case muted(Bool)                      // true = Muted, false = Unmuted
        case volumeChange(Float)              // 0.0 … 1.0
        case brightnessChange(Float)          // 0.0 … 1.0
        case keyboardBrightnessChange(Float)  // 0.0 … 1.0 (Apple-grade Keyboard Backlight)
        case noInternet
        case clipboard([ClipboardObserver.ClipboardItem])
        case timerSetup
        case screenshot(ScreenshotItem)
        case shelf
        case externalDriveEjected(name: String, success: Bool)
        case calendarAlert(CalendarEventItem)
        case hotspotLowBattery(HotspotItem)
        case quickNote
        case quickNoteSaved(title: String)
        case quickReminder
        case quickReminderSaved(title: String)
        case accessibilityPermissionRequired
        case spotifyAuthorized
        case emptySquareMenu
        case cameraMirror

        // MARK: Category

        var category: EventCategory {
            switch self {
            case .nowPlaying, .download, .timer, .externalDrive, .calendarEvent, .hotspot, .screenRecording, .onboarding, .welcomeGreeting:
                return .liveActivity
            default:
                return .alert
            }
        }

        var isLiveActivity: Bool { category == .liveActivity }
        var isAlert:        Bool { category == .alert }

        var kindIdentifier: String {
            switch self {
            case .nowPlaying: return "nowPlaying"
            case .timer: return "timer"
            case .download: return "download"
            case .externalDrive: return "externalDrive"
            case .externalDriveEjected: return "externalDriveEjected"
            case .calendarEvent: return "calendarEvent"
            case .calendarAlert: return "calendarAlert"
            case .hotspot: return "hotspot"
            case .hotspotLowBattery: return "hotspotLowBattery"
            case .quickNote: return "quickNote"
            case .quickNoteSaved: return "quickNoteSaved"
            case .quickReminder: return "quickReminder"
            case .quickReminderSaved: return "quickReminderSaved"
            case .accessibilityPermissionRequired: return "accessibilityPermissionRequired"
            case .spotifyAuthorized: return "spotifyAuthorized"
            case .emptySquareMenu: return "emptySquareMenu"
            case .cameraMirror: return "cameraMirror"
            case .timerSetup: return "timerSetup"
            case .clipboard: return "clipboard"
            case .screenRecording: return "screenRecording"
            case .onboarding: return "onboarding"
            case .welcomeGreeting: return "welcomeGreeting"
            case .batteryCharging, .batteryFull, .batteryLow: return "battery"
            case .bluetoothConnected, .bluetoothDisconnected: return "bluetooth"
            case .wifiConnected, .wifiDisconnected: return "wifi"
            case .vpnConnected: return "vpn"
            case .focusChanged: return "focus"
            case .muted, .volumeChange: return "volume"
            case .brightnessChange: return "brightness"
            case .keyboardBrightnessChange: return "keyboardBrightness"
            case .noInternet: return "noInternet"
            case .screenshot: return "screenshot"
            case .shelf: return "shelf"
            }
        }

        /// Alerts that initially present in Compact Wing Mode (left & right wings beside
        /// the physical notch) and expand into their full card only when hovered by the cursor.
        /// All system alerts except `.batteryLow`, `.noInternet`, and `.screenshot` use this compact-first presentation.
        var prefersCompactPresentation: Bool {
            switch self {
            case .batteryLow,
                 .batteryCharging,
                 .batteryFull,
                 .wifiConnected,
                 .noInternet,
                 .clipboard,
                 .timerSetup,
                 .nowPlaying,
                 .download,
                 .timer,
                 .screenshot,
                 .shelf,
                 .externalDrive,
                 .calendarEvent,
                 .calendarAlert,
                 .hotspot,
                 .hotspotLowBattery,
                 .quickNote,
                 .quickNoteSaved,
                 .quickReminder,
                 .quickReminderSaved,
                 .accessibilityPermissionRequired,
                 .spotifyAuthorized,
                 .emptySquareMenu,
                 .cameraMirror,
                 .screenRecording,
                 .onboarding,
                 .welcomeGreeting:
                return false
            case .bluetoothConnected(let name):
                let model = AirPodsModel(deviceName: name)
                return !model.supportsFullAnimation
            case .bluetoothDisconnected,
                 .wifiDisconnected,
                 .vpnConnected,
                 .focusChanged,
                 .muted,
                 .volumeChange,
                 .brightnessChange,
                 .keyboardBrightnessChange,
                 .externalDriveEjected:
                return true
            }
        }

        /// Returns `true` when `incoming` is a continuous value update of the same indicator
        /// (e.g. volume steps, timer countdown, media/download progress) that should update
        /// in-place in compact mode without collapsing the black notch background.
        func updatesCompactInPlace(with incoming: ContentType) -> Bool {
            switch (self, incoming) {
            case (.nowPlaying, .nowPlaying),
                 (.download, .download),
                 (.volumeChange, .volumeChange),
                 (.brightnessChange, .brightnessChange),
                 (.keyboardBrightnessChange, .keyboardBrightnessChange),
                 (.timer, .timer),
                 (.screenRecording, .screenRecording),
                 (.batteryLow, .batteryLow),
                  (.batteryCharging, .batteryCharging),
                  (.vpnConnected, .vpnConnected),
                  (.shelf, .shelf),
                  (.externalDrive, .externalDrive),
                  (.calendarEvent, .calendarEvent),
                  (.hotspot, .hotspot):
                return true
            default:
                return false
            }
        }

        /// Returns `true` when `incoming` belongs to the exact same active feature UI
        /// and should update its values in-place rather than shrinking into the notch first.
        func updatesInPlace(with incoming: ContentType, isExpanded: Bool) -> Bool {
            if updatesCompactInPlace(with: incoming) {
                return true
            }
            if isExpanded {
                switch (self, incoming) {
                case (.muted, .volumeChange),
                     (.volumeChange, .muted),
                     (.muted, .muted),
                     (.wifiConnected, .wifiConnected),
                     (.brightnessChange, .brightnessChange),
                     (.keyboardBrightnessChange, .keyboardBrightnessChange),
                     (.clipboard, .clipboard),
                     (.timerSetup, .timerSetup),
                     (.timerSetup, .timer),
                     (.screenshot, .screenshot),
                     (.shelf, .shelf),
                     (.externalDrive, .externalDrive),
                     (.calendarEvent, .calendarEvent),
                     (.calendarAlert, .calendarAlert),
                     (.calendarAlert, .calendarEvent),
                     (.hotspot, .hotspot),
                     (.hotspotLowBattery, .hotspotLowBattery),
                     (.hotspotLowBattery, .hotspot),
                     (.onboarding, .onboarding),
                     (.quickNote, .quickNote),
                     (.quickNoteSaved, .quickNoteSaved),
                     (.quickReminder, .quickReminder),
                     (.quickReminderSaved, .quickReminderSaved),
                     (.emptySquareMenu, .emptySquareMenu),
                     (.cameraMirror, .cameraMirror):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        // MARK: Priority (higher = shown first in the queue)
        //
        // onboarding > screenRecording > noInternet > batteryLow > hotspotLowBattery > screenshot > shelf > externalDriveEjected > timer > calendarAlert > nowPlaying > timerSetup > calendarEvent > clipboard > hotspot > externalDrive > download >
        // batteryCharging > batteryFull > bluetooth > focusChanged > wifi > vpn > brightnessChange > keyboardBrightnessChange > volumeChange

        var priority: Int {
            switch self {
            case .onboarding, .welcomeGreeting:           return 150
            case .screenRecording:                        return 100
            case .emptySquareMenu:                        return 99
            case .cameraMirror:                           return 82
            case .noInternet:                             return 95
            case .batteryLow:                             return 90
            case .hotspotLowBattery:                      return 89
            case .screenshot:                             return 88
            case .shelf:                                  return 87
            case .externalDriveEjected:                   return 86
            case .accessibilityPermissionRequired:        return 86
            case .spotifyAuthorized:                      return 94
            case .timer:                                  return 85
            case .calendarAlert:                          return 84
            case .nowPlaying:                             return 80
            case .quickNote:                              return 79
            case .quickReminder:                          return 79
            case .timerSetup:                             return 78
            case .quickNoteSaved:                         return 77
            case .quickReminderSaved:                     return 77
            case .calendarEvent:                          return 76
            case .clipboard:                              return 75
            case .hotspot:                                return 74
            case .externalDrive:                          return 72
            case .download:                               return 70
            case .batteryCharging:                        return 60
            case .batteryFull:                            return 50
            case .bluetoothConnected, .bluetoothDisconnected: return 40
            case .focusChanged:                           return 35
            case .wifiConnected, .wifiDisconnected:       return 30
            case .vpnConnected:                           return 20
            case .brightnessChange:                       return 12
            case .keyboardBrightnessChange:               return 11
            case .muted, .volumeChange:                   return 10
            }
        }

        // MARK: Default Alert Duration (nil = LiveActivity, never auto-dismisses while active)

        /// Central 5-minute (300s) retention duration for any LiveActivity that is paused or idle.
        static let liveActivityIdleRetentionDuration: TimeInterval = 5 * 60

        /// True when a LiveActivity is in a paused or non-progressing state and should
        /// remain visible for `liveActivityIdleRetentionDuration` (5 minutes) before hiding.
        var isLiveActivityPausedOrIdle: Bool {
            switch self {
            case .nowPlaying(let info):
                return !info.isPlaying
            case .download(let item):
                return item.progress >= 1.0
            case .timer(let item):
                return item.isPaused
            case .externalDrive(let drives):
                return drives.isEmpty
            case .calendarEvent(let item):
                return item.isPast
            case .hotspot:
                return false
            default:
                return false
            }
        }

        var defaultDuration: TimeInterval? {
            switch self {
            case .noInternet:                             return 12.0
            case .batteryLow:                             return 6.0
            case .hotspotLowBattery:                      return 5.0
            case .screenshot:                             return 8.0
            case .shelf:                                  return 10.0
            case .externalDriveEjected:                   return 2.8
            case .calendarAlert:                          return 6.0
            case .accessibilityPermissionRequired:        return 15.0
            case .spotifyAuthorized:                      return 2.2
            case .quickNote:                              return 180.0
            case .quickNoteSaved:                         return 2.6
            case .quickReminder:                          return 180.0
            case .quickReminderSaved:                     return 2.6
            case .timerSetup:                             return 60.0
            case .clipboard:                              return 6.0
            case .batteryCharging, .batteryFull:          return 4.0
            case .bluetoothConnected(let name):
                let model = AirPodsModel(deviceName: name)
                return model.supportsFullAnimation ? 6.0 : 3.0
            case .bluetoothDisconnected:                  return 3.0
            case .focusChanged:                           return 3.0
            case .wifiConnected, .wifiDisconnected:       return 3.0
            case .vpnConnected:                           return 20
            case .muted:                                  return 2.5
            case .brightnessChange:                       return 2.0
            case .keyboardBrightnessChange:               return 2.2
            case .volumeChange:                           return 2.0
            case .emptySquareMenu, .cameraMirror:         return nil
            case .nowPlaying, .download, .timer, .externalDrive, .calendarEvent, .hotspot, .screenRecording, .onboarding, .welcomeGreeting: return nil
            }
        }
    }
}
