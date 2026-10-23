// QuickReminderSavedAlertView.swift
// DynamicNotch / Features / QuickReminder
//
// Transient Apple-grade HUD confirming that a reminder has been added to Apple Reminders.
// Matches the visual language of Dynamic Notch system alerts (52pt body height,
// SF Pro Rounded typography, and Apple Reminders electric blue branding).

import SwiftUI

struct QuickReminderSavedAlertView: View {

    let title: String
    let onDismiss: () -> Void

    private let remindersBlueStart = Color(red: 0.10, green: 0.52, blue: 1.00) // #1A85FF
    private let remindersBlueEnd   = Color(red: 0.02, green: 0.38, blue: 0.94) // #0561F0

    private var isTurkish: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true ||
        Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("tr") == true ||
        Locale.current.identifier.lowercased().hasPrefix("tr") == true
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // Apple Reminders Squircle with Verified Checkmark Badge
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [remindersBlueStart, remindersBlueEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: remindersBlueStart.opacity(0.40), radius: 4, y: 1.5)

                Image(systemName: "list.bullet")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)

                // Sub-badge: Green checkmark circle
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 14, height: 14)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.20, green: 0.82, blue: 0.40)) // Apple System Green
                }
                .offset(x: 3, y: 3)
            }

            // Title & Reminder Preview Stack
            VStack(alignment: .leading, spacing: 2) {
                Text(isTurkish ? "Anımsatıcılar'a Eklendi" : "Added to Reminders")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(title.isEmpty ? (isTurkish ? "Yeni Anımsatıcı" : "New Reminder") : title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(remindersBlueStart.opacity(0.95))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Tactile Close Button
            Button(action: onDismiss) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 24, height: 24)

                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.60))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(height: 52)
    }
}
