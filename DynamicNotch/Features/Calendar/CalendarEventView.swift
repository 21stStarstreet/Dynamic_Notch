// CalendarEventView.swift
// DynamicNotch / Features / Calendar
//
// Apple-grade expanded interactive card for Calendar & Meeting Live Activities.
// Displays live countdown, meeting platform identification, tactile 1-click
// "Toplantıya Katıl" glass button, and today's upcoming event schedule.

import SwiftUI
import AppKit

struct CalendarEventView: View {

    let event: CalendarEventItem
    @ObservedObject private var manager = CalendarManager.shared

    @State private var isJoinHovered = false
    @State private var isCalHovered = false
    @State private var pulseState = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Calendar color dot + Title + Status Pill
            HStack(alignment: .center, spacing: 6) {
                // Calendar Color Indicator
                Circle()
                    .fill(event.calendarColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: event.calendarColor.opacity(0.40), radius: 2)

                Text(event.calendarTitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)

                Spacer()

                // Status Capsule (e.g. "ŞİMDİ", "10 DK KALDI")
                HStack(spacing: 5) {
                    if event.isHappeningNow {
                        Circle()
                            .fill(Color.notchGreen)
                            .frame(width: 7, height: 7)
                            .scaleEffect(pulseState ? 1.25 : 0.85)
                            .opacity(pulseState ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulseState)
                            .onAppear { pulseState = true }
                    }

                    Text(event.statusBadgeText)
                        .font(.system(size: 12.0, weight: .bold, design: .rounded))
                        .foregroundColor(event.isHappeningNow ? .notchGreen : event.calendarColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            (event.isHappeningNow ? Color.notchGreen : event.calendarColor)
                                .opacity(0.18)
                        )
                )
            }
            .padding(.horizontal, 2)

            // Main Info Block: Event Title + Time / Platform Subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Time Range
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.50))
                        Text(event.formattedTimeRange)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.70))
                    }

                    // Conference Platform or Location Badge
                    if let platform = event.conferencePlatform {
                        Text("•")
                            .foregroundColor(.white.opacity(0.30))
                        HStack(spacing: 4) {
                            Image(systemName: platform.iconName)
                                .font(.system(size: 9.5))
                                .foregroundColor(platform.accentColor)
                            Text(platform.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(platform.accentColor)
                        }
                    } else if let loc = event.location, !loc.isEmpty {
                        Text("•")
                            .foregroundColor(.white.opacity(0.30))
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.50))
                            Text(loc)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)

            // Action Dock: "Toplantıya Katıl" (if conference) + "Takvim'de Aç"
            HStack(spacing: 8) {
                if event.hasConference {
                    Button {
                        manager.openMeeting(for: event)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: event.conferencePlatform?.iconName ?? "video.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(event.conferencePlatform != nil ? "\(event.conferencePlatform!.rawValue)'a Katıl" : "Toplantıya Katıl")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                (event.conferencePlatform?.accentColor ?? Color.blue).opacity(isJoinHovered ? 0.90 : 0.75),
                                                (event.conferencePlatform?.accentColor ?? Color.blue).opacity(isJoinHovered ? 0.75 : 0.60)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(isJoinHovered ? 0.40 : 0.20), lineWidth: 0.8)
                            }
                        )
                        .scaleEffect(isJoinHovered ? 1.02 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isJoinHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { isJoinHovered = $0 }
                }

                // Secondary Action: Open in Apple Calendar
                Button {
                    manager.openInCalendar(for: event)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .medium))
                        Text("Takvim'de Aç")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(isCalHovered ? 0.95 : 0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(isCalHovered ? 0.16 : 0.10))
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(isCalHovered ? 0.22 : 0.12), lineWidth: 0.8)
                        }
                    )
                    .scaleEffect(isCalHovered ? 1.02 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isCalHovered)
                }
                .buttonStyle(.plain)
                .onHover { isCalHovered = $0 }

                Spacer()
            }
            .padding(.top, 1)

            // Optional: Next scheduled event of the day
            if let nextUpcoming = manager.todayEvents.first(where: { $0.id != event.id && $0.startDate > event.startDate }) {
                Divider()
                    .background(Color.white.opacity(0.12))
                    .padding(.vertical, 2)

                HStack(spacing: 6) {
                    Text("SONRAKİ:")
                        .font(.system(size: 9.0, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.40))

                    Circle()
                        .fill(nextUpcoming.calendarColor)
                        .frame(width: 5, height: 5)

                    Text(nextUpcoming.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)

                    Spacer()

                    Text(nextUpcoming.formattedTimeRange)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.50))
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
