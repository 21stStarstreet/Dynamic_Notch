// CalendarManager.swift
// DynamicNotch / Features / Calendar
//
// Apple-grade calendar event coordinator backed by EventKit.
// Automatically tracks upcoming meetings, detects video conference URLs,
// manages granular notification lead times, and integrates seamlessly
// into DynamicNotch Live Activities and transient Alert HUDs.

import Foundation
import EventKit
import SwiftUI
import Combine
import AppKit

@MainActor
final class CalendarManager: ObservableObject {

    static let shared = CalendarManager()

    // MARK: - Published State

    @Published private(set) var hasAccess: Bool = false
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var todayEvents: [CalendarEventItem] = []
    @Published private(set) var activeOrNextEvent: CalendarEventItem? = nil
    @Published private(set) var isMeetingActiveOrImminent: Bool = false

    /// Callback invoked when an upcoming event enters the alert lead-time window
    var onEventAlertTriggered: ((CalendarEventItem) -> Void)?

    // MARK: - Private Properties

    private let eventStore = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private var periodicRefreshTimer: AnyCancellable?
    private var alertedEventKeys: Set<String> = []

    // MARK: - Preferences

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "showCalendarEvents") as? Bool ?? true
    }

    /// Alert lead time in minutes (default: 10 minutes)
    var alertLeadTimeMinutes: Int {
        let val = UserDefaults.standard.integer(forKey: "calendarAlertLeadTimeMinutes")
        return val > 0 ? val : 10
    }

    /// Whether to show Live Activity on notch wings when meeting is imminent (<= 15m) or active
    var showLiveActivityForImminentMeetings: Bool {
        UserDefaults.standard.object(forKey: "calendarShowLiveActivity") as? Bool ?? true
    }

    // MARK: - Initialization

    private init() {
        checkAuthorizationStatus()
        setupNotificationObservers()
        startPeriodicTimer()
    }

    // MARK: - Permissions & Setup

    func checkAuthorizationStatus() {
        if #available(macOS 14.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            hasAccess = (authorizationStatus == .fullAccess)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            hasAccess = (authorizationStatus == .authorized)
        }

        if hasAccess {
            fetchEvents()
        }
    }

    func requestAccess(completion: ((Bool) -> Void)? = nil) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.checkAuthorizationStatus()
                    if granted {
                        self.fetchEvents()
                    }
                    completion?(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.checkAuthorizationStatus()
                    if granted {
                        self.fetchEvents()
                    }
                    completion?(granted)
                }
            }
        }
    }

    private func setupNotificationObservers() {
        // Observe system calendar changes (new events added, deleted, moved)
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchEvents()
            }
            .store(in: &cancellables)

        // Observe system time changes (significant time change, wake from sleep)
        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemClockDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchEvents()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchEvents()
            }
            .store(in: &cancellables)
    }

    private func startPeriodicTimer() {
        periodicRefreshTimer?.cancel()
        // Check every 15 seconds to keep countdown accurate and trigger alerts promptly
        periodicRefreshTimer = Timer.publish(every: 15.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateActiveAndUpcomingState()
            }
    }

    // MARK: - Event Fetching & Parsing

    func fetchEvents() {
        guard hasAccess else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        // Look back 30 minutes to catch meetings that just started
        let searchStart = now.addingTimeInterval(-1800)
        let predicate = eventStore.predicateForEvents(withStart: searchStart, end: endOfDay, calendars: nil)
        let rawEvents = eventStore.events(matching: predicate)

        let parsedItems: [CalendarEventItem] = rawEvents
            .filter { !$0.isAllDay || $0.startDate >= startOfDay }
            .filter { $0.endDate > now.addingTimeInterval(-60) } // Has not ended more than 1 min ago
            .map { ekEvent in
                let color: Color
                if let cgColor = ekEvent.calendar.cgColor {
                    color = Color(cgColor: cgColor)
                } else {
                    color = Color(red: 0.22, green: 0.60, blue: 1.0)
                }

                return CalendarEventItem(
                    id: ekEvent.eventIdentifier ?? UUID().uuidString,
                    title: ekEvent.title ?? "İsimsiz Etkinlik",
                    startDate: ekEvent.startDate,
                    endDate: ekEvent.endDate,
                    isAllDay: ekEvent.isAllDay,
                    location: ekEvent.location,
                    notes: ekEvent.notes,
                    originalURL: ekEvent.url,
                    calendarTitle: ekEvent.calendar.title,
                    calendarColor: color
                )
            }
            .sorted { $0.startDate < $1.startDate }

        self.todayEvents = parsedItems
        updateActiveAndUpcomingState()
    }

    // MARK: - Active & Upcoming State Computation

    private func updateActiveAndUpcomingState() {
        guard isEnabled else {
            self.activeOrNextEvent = nil
            self.isMeetingActiveOrImminent = false
            return
        }

        let now = Date()

        // 1. Check for currently happening meeting
        if let current = todayEvents.first(where: { $0.isHappeningNow }) {
            self.activeOrNextEvent = current
            self.isMeetingActiveOrImminent = true
            return
        }

        // 2. Otherwise find the closest upcoming event
        let upcoming = todayEvents.filter { $0.startDate > now }
        if let next = upcoming.first {
            self.activeOrNextEvent = next

            // Imminent if within 15 minutes
            let timeUntil = next.timeUntilStart
            self.isMeetingActiveOrImminent = (timeUntil <= 15 * 60)

            // Check if alert should be triggered
            checkAlertTrigger(for: next)
        } else {
            self.activeOrNextEvent = nil
            self.isMeetingActiveOrImminent = false
        }
    }

    private func checkAlertTrigger(for event: CalendarEventItem) {
        let leadSeconds = Double(alertLeadTimeMinutes * 60)
        let timeUntil = event.timeUntilStart
        let eventKey = "\(event.id)_\(alertLeadTimeMinutes)"

        // If event starts within the lead time (and hasn't started yet, and not already alerted)
        if timeUntil > 0 && timeUntil <= leadSeconds && !alertedEventKeys.contains(eventKey) {
            alertedEventKeys.insert(eventKey)
            onEventAlertTriggered?(event)
        }
    }

    // MARK: - User Actions

    func openMeeting(for item: CalendarEventItem) {
        if let meetingURL = item.conferenceURL {
            NSWorkspace.shared.open(meetingURL)
        } else if let originalURL = item.originalURL {
            NSWorkspace.shared.open(originalURL)
        } else {
            openInCalendar(for: item)
        }
    }

    func openInCalendar(for item: CalendarEventItem) {
        // Direct Activation of macOS Calendar (Takvim)
        if let calendarAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: calendarAppURL, configuration: config, completionHandler: nil)
        } else {
            let fallbackURL = URL(fileURLWithPath: "/System/Applications/Calendar.app")
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    // MARK: - Simulation Bench

    func simulateUpcomingMeeting(minutesUntilStart: Int = 10) -> CalendarEventItem {
        let start = Date().addingTimeInterval(Double(minutesUntilStart * 60))
        let end = start.addingTimeInterval(45 * 60)
        let item = CalendarEventItem(
            id: "sim-meeting-\(UUID().uuidString)",
            title: "Q4 Tasarım & Mühendislik Senkronu",
            startDate: start,
            endDate: end,
            isAllDay: false,
            location: "Google Meet",
            notes: "https://meet.google.com/xyz-qwer-tyu Toplantı gündemi: DynamicNotch Calendar & Live Activities",
            calendarTitle: "İş & Projeler",
            calendarColor: Color(red: 0.18, green: 0.50, blue: 1.0),
            conferencePlatform: .googleMeet,
            conferenceURL: URL(string: "https://meet.google.com/xyz-qwer-tyu")
        )
        self.activeOrNextEvent = item
        self.isMeetingActiveOrImminent = true
        return item
    }

    func simulateActiveMeeting() -> CalendarEventItem {
        let start = Date().addingTimeInterval(-15 * 60)
        let end = Date().addingTimeInterval(30 * 60)
        let item = CalendarEventItem(
            id: "sim-meeting-active-\(UUID().uuidString)",
            title: "Tasarım Sistemi Değerlendirmesi",
            startDate: start,
            endDate: end,
            isAllDay: false,
            location: "Zoom Video Meeting",
            notes: "https://zoom.us/j/987654321 Toplantı şifresi: 123456",
            calendarTitle: "Tasarım",
            calendarColor: Color(red: 0.60, green: 0.25, blue: 0.95),
            conferencePlatform: .zoom,
            conferenceURL: URL(string: "https://zoom.us/j/987654321")
        )
        self.activeOrNextEvent = item
        self.isMeetingActiveOrImminent = true
        return item
    }
}
