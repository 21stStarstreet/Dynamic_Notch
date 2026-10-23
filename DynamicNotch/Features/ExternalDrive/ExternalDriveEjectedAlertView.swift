// ExternalDriveEjectedAlertView.swift
// DynamicNotch / Features / ExternalDrive
//
// Apple-grade transient confirmation HUD indicating that a drive has been
// safely unmounted and can now be physically disconnected from the Mac.

import SwiftUI

struct ExternalDriveEjectedAlertView: View {

    let driveName: String
    let success: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon Badge
            ZStack {
                Circle()
                    .fill((success ? Color.notchGreen : Color.notchRed).opacity(0.18))
                    .frame(width: 32, height: 32)

                Image(systemName: success ? "checkmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(success ? .notchGreen : .notchRed)
            }

            // Text Stack
            VStack(alignment: .leading, spacing: 2) {
                Text(success ? "Güvenle Çıkarıldı" : "Çıkarılamadı")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.notchTitle)
                    .lineLimit(1)

                Text(success ? "\(driveName) artık çıkarılabilir" : "\(driveName) kullanımda")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.notchSubtitle)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Eject Symbol
            Image(systemName: "eject.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.40))
        }
        .padding(.horizontal, 4)
    }
}
