// QuickNoteSavedAlertView.swift
// DynamicNotch / Features / QuickNote
//
// Transient Apple-grade HUD confirming that a note has been added to Apple Notes.
// Matches the visual language of Dynamic Notch system alerts (52pt body height,
// SF Pro Rounded typography, and Apple Notes amber branding).

import SwiftUI

struct QuickNoteSavedAlertView: View {

    let title: String
    let onDismiss: () -> Void

    private let notesAmberStart = Color(red: 0.98, green: 0.76, blue: 0.28)
    private let notesAmberEnd   = Color(red: 0.86, green: 0.54, blue: 0.10)

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // Apple Notes Squircle with Verified Checkmark Badge
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [notesAmberStart, notesAmberEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: notesAmberStart.opacity(0.35), radius: 4, y: 1.5)

                Image(systemName: "note.text")
                    .font(.system(size: 16.5, weight: .bold))
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

            // Title & Note Preview Stack
            VStack(alignment: .leading, spacing: 2) {
                Text(isTurkish ? "Apple Notlar'a Eklendi" : "Added to Apple Notes")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(title.isEmpty ? (isTurkish ? "Yeni Not" : "New Note") : title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(notesAmberStart.opacity(0.95))
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
