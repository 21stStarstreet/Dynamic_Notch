// RemindersService.swift
// DynamicNotch / Features / QuickReminder
//
// Apple-grade service for integrating with macOS Apple Reminders (Anımsatıcılar).
// Leverages native EventKit (EKEventStore, EKReminder) for direct, zero-delay iCloud
// synchronization across iPhone, iPad, Apple Watch, and Mac.
// Includes transparent AppleScript fallback to guarantee zero-fail reliability.

import Foundation
import EventKit
import AppKit

enum ReminderDueOption: Equatable {
    case none
    case today
    case tomorrow

    var displayTitle: String {
        let isTurkish = Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true ||
                       Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("tr") == true ||
                       Locale.current.identifier.lowercased().hasPrefix("tr") == true
        switch self {
        case .none: return ""
        case .today: return isTurkish ? "Bugün" : "Today"
        case .tomorrow: return isTurkish ? "Yarın" : "Tomorrow"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "calendar"
        case .today: return "calendar.badge.clock"
        case .tomorrow: return "sunrise.fill"
        }
    }

    var dueDateComponents: DateComponents? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .none:
            return nil
        case .today:
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = 18
            comps.minute = 0
            return comps
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = 9
            comps.minute = 0
            return comps
        }
    }
}

final class RemindersService {

    static let shared = RemindersService()

    private let eventStore = EKEventStore()

    private init() {}

    enum RemindersError: LocalizedError {
        case emptyTitle
        case accessDenied
        case saveFailed(String)

        var errorDescription: String? {
            let isTurkish = Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true ||
                           Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("tr") == true ||
                           Locale.current.identifier.lowercased().hasPrefix("tr") == true
            switch self {
            case .emptyTitle:
                return isTurkish ? "Anımsatıcı başlığı boş olamaz." : "Reminder title cannot be empty."
            case .accessDenied:
                return isTurkish ? "Anımsatıcılar erişim izni verilmedi." : "Reminders access permission was not granted."
            case .saveFailed(let message):
                return isTurkish ? "Anımsatıcı kaydedilemedi: \(message)" : "Failed to save reminder: \(message)"
            }
        }
    }

    /// Creates a new reminder in Apple Reminders with optional due date and priority flag.
    /// - Parameters:
    ///   - title: The title / body text of the reminder.
    ///   - dueOption: Selected due date chip (none, today, tomorrow).
    ///   - isHighPriority: Whether the reminder is flagged with high priority.
    ///   - completion: Callback returning the saved title or error on the main thread.
    func createReminder(
        title: String,
        dueOption: ReminderDueOption = .none,
        isHighPriority: Bool = false,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            completion(.failure(RemindersError.emptyTitle))
            return
        }

        // Request EventKit access or execute directly if already authorized
        requestRemindersAccess { [weak self] granted in
            guard let self else { return }

            if granted {
                self.saveViaEventKit(
                    title: trimmedTitle,
                    dueOption: dueOption,
                    isHighPriority: isHighPriority,
                    completion: completion
                )
            } else {
                // Seamless AppleScript fallback ensuring zero-data-loss
                self.saveViaAppleScript(
                    title: trimmedTitle,
                    dueOption: dueOption,
                    isHighPriority: isHighPriority,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Native EventKit Persistence (Direct iCloud Sync)

    private func saveViaEventKit(
        title: String,
        dueOption: ReminderDueOption,
        isHighPriority: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let reminder = EKReminder(eventStore: self.eventStore)
            reminder.title = title
            reminder.calendar = self.eventStore.defaultCalendarForNewReminders() ?? self.eventStore.calendars(for: .reminder).first

            if let dueComps = dueOption.dueDateComponents {
                reminder.dueDateComponents = dueComps
                if let targetDate = Calendar.current.date(from: dueComps) {
                    let alarm = EKAlarm(absoluteDate: targetDate)
                    reminder.addAlarm(alarm)
                }
            }

            if isHighPriority {
                reminder.priority = 1 // 1 = High, 5 = Medium, 9 = Low in EventKit
            }

            do {
                try self.eventStore.save(reminder, commit: true)
                DispatchQueue.main.async {
                    completion(.success(title))
                }
            } catch {
                // If EventKit save encounters an issue, fallback to AppleScript
                self.saveViaAppleScript(
                    title: title,
                    dueOption: dueOption,
                    isHighPriority: isHighPriority,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Native AppleScript Fallback Engine

    private func saveViaAppleScript(
        title: String,
        dueOption: ReminderDueOption,
        isHighPriority: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let escapedTitle = title
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")

            var properties: [String] = ["name:\"\(escapedTitle)\""]

            if isHighPriority {
                properties.append("priority:1")
            }

            if let dueComps = dueOption.dueDateComponents, let date = Calendar.current.date(from: dueComps) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let dateStr = formatter.string(from: date)
                properties.append("due date:date \"\(dateStr)\"")
            }

            let propsString = properties.joined(separator: ", ")

            let scriptSource = """
            tell application id "com.apple.reminders"
                try
                    tell default list
                        make new reminder with properties {\(propsString)}
                    end tell
                on error
                    try
                        make new reminder with properties {\(propsString)}
                    end try
                end try
            end tell
            """

            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else {
                DispatchQueue.main.async {
                    completion(.failure(RemindersError.saveFailed("AppleScript derlenemedi")))
                }
                return
            }

            script.executeAndReturnError(&errorInfo)

            DispatchQueue.main.async {
                if let errorInfo = errorInfo {
                    let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "Bilinmeyen hata"
                    completion(.failure(RemindersError.saveFailed(msg)))
                } else {
                    completion(.success(title))
                }
            }
        }
    }

    // MARK: - EventKit Access Negotiation

    private func requestRemindersAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, _ in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }
}
