// ExternalDriveView.swift
// DynamicNotch / Features / ExternalDrive
//
// Apple-grade expanded interactive card for viewing mounted external drives,
// inspection of used/free storage capacity bar, Finder quick-reveal,
// and tactile one-click safe ejection.

import SwiftUI

struct ExternalDriveView: View {

    let drives: [ExternalDriveItem]
    @ObservedObject private var manager = ExternalDriveManager.shared

    @State private var hoveredFinderId: String? = nil
    @State private var hoveredEjectId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))

                Text(drives.count > 1 ? "HARİCİ SÜRÜCÜLER" : "HARİCİ SÜRÜCÜ")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(0.6)

                Spacer()

                if drives.count > 1 {
                    Button {
                        manager.ejectAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eject.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Tümünü Çıkar")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            // Drives List
            VStack(spacing: 6) {
                ForEach(drives) { drive in
                    driveRow(drive: drive)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func driveRow(drive: ExternalDriveItem) -> some View {
        let isEjecting = manager.ejectingDriveURLs.contains(drive.url)
        let isHoveredFinder = (hoveredFinderId == drive.id)
        let isHoveredEject = (hoveredEjectId == drive.id)

        return HStack(alignment: .center, spacing: 10) {
            // Left: High-resolution Finder Disk Icon
            Image(nsImage: drive.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1)

            // Center Column: Name, Badge, Storage Bar, and Free Space
            VStack(alignment: .leading, spacing: 4) {
                // Top: Name & Type Badge
                HStack(alignment: .center, spacing: 6) {
                    Text(drive.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.notchTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(drive.driveType.rawValue)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(drive.driveType.accentColor.opacity(0.95))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(drive.driveType.accentColor.opacity(0.16))
                        )
                }

                // Middle: Apple Storage Segment Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        drive.driveType.accentColor,
                                        drive.driveType.accentColor.opacity(0.82)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4.0, geo.size.width * CGFloat(drive.usedPercentage)))
                    }
                }
                .frame(height: 4.5)

                // Bottom: Capacity Details (e.g. 412.5 GB boş / 1 TB)
                HStack(spacing: 4) {
                    Text("\(drive.availableCapacityFormatted) boş")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.notchSubtitle)

                    Text("•")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.white.opacity(0.30))

                    Text(drive.totalCapacityFormatted)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.40))
                }
            }

            Spacer(minLength: 4)

            // Right Actions: Finder + Eject Buttons
            HStack(spacing: 6) {
                // Finder Button
                Button {
                    manager.openInFinder(drive: drive)
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isHoveredFinder ? .white : .white.opacity(0.70))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(Color.white.opacity(isHoveredFinder ? 0.20 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Finder'da Aç")
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.15)) { hoveredFinderId = h ? drive.id : nil }
                }

                // Eject Button
                Button {
                    manager.eject(drive: drive)
                } label: {
                    if isEjecting {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(isHoveredEject ? .notchRed : .white.opacity(0.70))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(
                                    isHoveredEject
                                        ? Color.notchRed.opacity(0.20)
                                        : Color.white.opacity(0.08)
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isEjecting)
                .help("Güvenle Çıkar")
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.15)) { hoveredEjectId = h ? drive.id : nil }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.white.opacity(0.05))
        )
    }
}
