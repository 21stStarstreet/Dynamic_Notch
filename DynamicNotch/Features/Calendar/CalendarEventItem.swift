// CalendarEventItem.swift
// DynamicNotch / Features / Calendar
//
// Apple-grade data model representing a system calendar event with
// smart video conference detection, localized time tracking,
// and custom calendar colors.

import Foundation
import SwiftUI
import AppKit

// MARK: - Conference Platform

enum ConferencePlatform: String, Equatable {
    case zoom = "Zoom"
    case googleMeet = "Google Meet"
    case microsoftTeams = "Microsoft Teams"
    case webex = "Webex"
    case facetime = "FaceTime"
    case generic = "Video Toplantısı"

    var iconName: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "video.badge.waveform.fill"
        case .microsoftTeams: return "person.2.wave.2.fill"
        case .webex: return "video.fill"
        case .facetime: return "video.fill"
        case .generic: return "video.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .zoom: return Color(red: 0.18, green: 0.53, blue: 1.0)
        case .googleMeet: return Color(red: 0.0, green: 0.65, blue: 0.42)
        case .microsoftTeams: return Color(red: 0.38, green: 0.42, blue: 0.90)
        case .webex: return Color(red: 0.05, green: 0.70, blue: 0.85)
        case .facetime: return Color(red: 0.20, green: 0.82, blue: 0.38)
        case .generic: return Color(red: 0.20, green: 0.60, blue: 1.0)
        }
    }
}

// MARK: - CalendarEventItem

struct CalendarEventItem: Identifiable, Equatable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var originalURL: URL?
    var calendarTitle: String
    var calendarColor: Color
    var conferencePlatform: ConferencePlatform?
    var conferenceURL: URL?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        originalURL: URL? = nil,
        calendarTitle: String = "Takvim",
        calendarColor: Color = Color(red: 0.22, green: 0.60, blue: 1.0),
        conferencePlatform: ConferencePlatform? = nil,
        conferenceURL: URL? = nil
    ) {
        self.id = id
        self.title = title.isEmpty ? "İsimsiz Etkinlik" : title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.originalURL = originalURL
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor

        if let conferenceURL, let conferencePlatform {
            self.conferenceURL = conferenceURL
            self.conferencePlatform = conferencePlatform
        } else {
            // Auto-detect conference link and platform from url, location, and notes
            let detected = Self.detectConference(url: originalURL, location: location, notes: notes)
            self.conferencePlatform = detected?.platform
            self.conferenceURL = detected?.url
        }
    }

    var hasConference: Bool {
        conferenceURL != nil
    }

    // MARK: - Timing & State Helpers

    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }

    var isPast: Bool {
        endDate <= Date()
    }

    var isUpcoming: Bool {
        startDate > Date()
    }

    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSinceNow
    }

    var remainingDuration: TimeInterval {
        max(0, endDate.timeIntervalSinceNow)
    }

    /// Progress for ongoing meeting (0.0 ... 1.0)
    var progress: Double {
        guard isHappeningNow else { return isPast ? 1.0 : 0.0 }
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 0.0 }
        let elapsed = Date().timeIntervalSince(startDate)
        return max(0.0, min(1.0, elapsed / total))
    }

    // MARK: - Formatted Strings

    var formattedTimeRange: String {
        if isAllDay {
            return Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Tüm Gün" : "All Day"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        return "\(start) – \(end)"
    }

    var statusBadgeText: String {
        let isTurkish = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
        if isHappeningNow {
            let remMinutes = Int(ceil(remainingDuration / 60))
            if remMinutes <= 0 {
                return isTurkish ? "ŞİMDİ" : "NOW"
            }
            if remMinutes < 60 {
                return isTurkish ? "\(remMinutes) DK KALDI" : "\(remMinutes) MIN LEFT"
            }
            let hours = remMinutes / 60
            let mins = remMinutes % 60
            if mins == 0 {
                return isTurkish ? "\(hours) SAAT KALDI" : "\(hours) HR LEFT"
            }
            return isTurkish ? "\(hours) SA \(mins) DK KALDI" : "\(hours) HR \(mins) MIN LEFT"
        }
        if isAllDay {
            return isTurkish ? "TÜM GÜN" : "ALL DAY"
        }
        let diff = timeUntilStart
        if diff <= 60 {
            return isTurkish ? "BAŞLIYOR" : "STARTING"
        }
        let minutes = Int(ceil(diff / 60))
        if minutes < 60 {
            return isTurkish ? "\(minutes) DK KALDI" : "IN \(minutes) MIN"
        }
        let hours = minutes / 60
        return isTurkish ? "\(hours) SAAT SONRA" : "IN \(hours) HR"
    }

    var compactCountdownString: String {
        let isTurkish = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
        if isHappeningNow {
            let remMinutes = Int(ceil(remainingDuration / 60))
            if remMinutes <= 0 {
                return isTurkish ? "Şimdi" : "Now"
            }
            if remMinutes <= 60 {
                return isTurkish ? "\(remMinutes)dk" : "\(remMinutes)m"
            }
            let h = remMinutes / 60
            let m = remMinutes % 60
            return m == 0 ? (isTurkish ? "\(h)sa" : "\(h)h") : (isTurkish ? "\(h)sa\(m)d" : "\(h)h\(m)m")
        }
        if isAllDay {
            return isTurkish ? "Tüm Gün" : "All Day"
        }
        let diff = timeUntilStart
        if diff <= 60 {
            return isTurkish ? "Başlıyor" : "Starts"
        }
        let minutes = Int(ceil(diff / 60))
        if minutes < 60 {
            return isTurkish ? "\(minutes)dk" : "\(minutes)m"
        }
        // Start time e.g. "14:30"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startDate)
    }

    var durationFormatted: String {
        let duration = endDate.timeIntervalSince(startDate)
        let minutes = Int(round(duration / 60))
        let isTurkish = Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
        if minutes < 60 {
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

    // MARK: - Smart Conference Link Detector

    static func detectConference(url: URL?, location: String?, notes: String?) -> (platform: ConferencePlatform, url: URL)? {
        var candidateStrings: [String] = []
        if let urlStr = url?.absoluteString { candidateStrings.append(urlStr) }
        if let loc = location, !loc.isEmpty { candidateStrings.append(loc) }
        if let not = notes, !not.isEmpty { candidateStrings.append(not) }

        let fullText = candidateStrings.joined(separator: " \n ")

        // Detect URLs with data detector
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))

        for match in matches {
            guard let range = Range(match.range, in: fullText) else { continue }
            let linkStr = String(fullText[range])
            guard let foundURL = URL(string: linkStr) else { continue }
            let host = foundURL.host?.lowercased() ?? ""

            if host.contains("zoom.us") {
                return (.zoom, foundURL)
            } else if host.contains("meet.google.com") {
                return (.googleMeet, foundURL)
            } else if host.contains("teams.microsoft.com") || host.contains("teams.live.com") {
                return (.microsoftTeams, foundURL)
            } else if host.contains("webex.com") {
                return (.webex, foundURL)
            } else if host.contains("facetime.apple.com") {
                return (.facetime, foundURL)
            }
        }

        // Fallback: check if the explicit event url is a valid web link
        if let url = url, url.scheme == "https" || url.scheme == "http" {
            return (.generic, url)
        }

        return nil
    }

    static let empty = CalendarEventItem(
        id: "empty",
        title: "",
        startDate: Date(),
        endDate: Date().addingTimeInterval(1800)
    )
}
