// CalendarEventAlertView.swift
// DynamicNotch / Features / Calendar
//
// Apple-grade transient notification alert HUD displayed when an upcoming
// calendar event or video conference is about to begin.

import SwiftUI

struct CalendarEventAlertView: View {

    let event: CalendarEventItem
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var manager = CalendarManager.shared
    @State private var isActionHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: Glowing icon inside circular glass housing
            ZStack {
                Circle()
                    .fill(
                        (event.conferencePlatform?.accentColor ?? event.calendarColor)
                            .opacity(0.20)
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: event.conferencePlatform?.iconName ?? "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(event.conferencePlatform?.accentColor ?? event.calendarColor)
            }

            // Middle: Event details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.conferencePlatform != nil ? "\(event.conferencePlatform!.rawValue) Toplantısı" : "Takvim Etkinliği")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor((event.conferencePlatform?.accentColor ?? event.calendarColor))
                        .textCase(.uppercase)
                        .tracking(0.4)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))

                    Text(event.statusBadgeText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.70))
                }

                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Right Action: Quick "Katıl" or "Göster" Button
            Button {
                if event.hasConference {
                    manager.openMeeting(for: event)
                } else {
                    manager.openInCalendar(for: event)
                }
                onDismiss?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: event.hasConference ? "arrow.up.right.video.fill" : "calendar")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(event.hasConference ? "Katıl" : "Aç")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            (event.conferencePlatform?.accentColor ?? Color.blue)
                                .opacity(isActionHovered ? 0.90 : 0.75)
                        )
                )
                .scaleEffect(isActionHovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isActionHovered)
            }
            .buttonStyle(.plain)
            .onHover { isActionHovered = $0 }
        }
    }
}
