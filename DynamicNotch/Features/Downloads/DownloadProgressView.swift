// DownloadProgressView.swift
// DynamicNotch / Features / Downloads
//
// Phase 2 (Faz 4): Apple-grade LiveActivity download progress view.
// Displays smart file-type SF Symbol badge, middle-truncated filename,
// destination folder, real-time MB/s or KB/s speed gauge, percentage,
// and full-width GPU-accelerated progress bar.

import SwiftUI

struct DownloadProgressView: View {

    let item: DownloadItem

    private var clampedProgress: Double {
        min(max(item.progress, 0.0), 1.0)
    }

    private var percentageInt: Int {
        Int(round(clampedProgress * 100))
    }

    private var speedText: String {
        DownloadObserver.formatSpeed(item.speedBytesPerSec)
    }

    private var iconName: String {
        Self.fileIcon(for: item.filename)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 11) {
                // Left: 34×34 File Type Badge
                ZStack {
                    Circle()
                        .fill(Color.notchBlue.opacity(0.18))
                        .frame(width: 34, height: 34)

                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.notchBlue)
                }

                // Middle: Filename and Folder / Byte Stack
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.filename)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 6)

                        if item.totalBytes > 0 {
                            Text("%\(percentageInt)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.notchBlue)
                                .contentTransition(.numericText())
                                .layoutPriority(1)
                                .fixedSize()
                        } else {
                            Text(formatBytes(item.downloadedBytes))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.notchBlue)
                                .contentTransition(.numericText())
                                .layoutPriority(1)
                                .fixedSize()
                        }
                    }

                    HStack(spacing: 6) {
                        Text(subtitleText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Text(speedText)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .layoutPriority(1)
                            .fixedSize()
                    }
                }
            }

            // Bottom: Full-Width GPU-Accelerated Progress Bar
            ProgressBarView(
                progress: clampedProgress,
                tint: .notchBlue,
                isIndeterminate: item.totalBytes <= 0
            )
            .frame(height: 3.5)
        }
    }

    private var subtitleText: String {
        if item.totalBytes > 0 && item.downloadedBytes > 0 {
            return "\(item.sourceFolderName) • \(formatBytes(item.downloadedBytes)) / \(formatBytes(item.totalBytes))"
        } else if item.downloadedBytes > 0 {
            return "\(item.sourceFolderName) • \(formatBytes(item.downloadedBytes))"
        } else {
            return item.sourceFolderName
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Smart File Type SF Symbol Mapper

    static func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.fill"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return "archivebox.fill"
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return "film.fill"
        case "mp3", "aac", "flac", "wav", "m4a", "ogg":
            return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "tiff":
            return "photo.fill"
        case "dmg", "pkg", "iso":
            return "externaldrive.fill"
        case "swift", "py", "js", "ts", "html", "css", "json", "c", "cpp", "rs", "go", "rb", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "app":
            return "app.dashed"
        default:
            return "doc.fill"
        }
    }
}
