// ShelfManager.swift
// DynamicNotch / Features / Shelf
//
// Central manager for items stored temporarily on the Notch Shelf (Tray).
// Generates QuickLook retina thumbnails, coordinates drag-and-drop ingestion,
// and provides Apple-grade haptic feedback.

import Foundation
import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class ShelfManager: ObservableObject {

    static let shared = ShelfManager()

    // MARK: - Published State

    @Published private(set) var items: [ShelfItem] = []
    @Published var isDragApproaching: Bool = false
    @Published var isDropZoneTargeted: Bool = false

    private init() {}

    // MARK: - Ingestion & Item Management

    /// Ingests a list of file URLs dropped into the shelf, generating QuickLook thumbnails asynchronously.
    func add(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // Trigger Apple tactile feedback on successful drop reception
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )

        for url in urls {
            // Avoid duplicate additions of the identical file path
            if items.contains(where: { $0.url.path == url.path }) {
                continue
            }

            let name = url.lastPathComponent
            let sizeString = formattedFileSize(for: url)

            let placeholderItem = ShelfItem(
                url: url,
                name: name,
                fileSizeString: sizeString,
                thumbnail: nil
            )

            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                items.insert(placeholderItem, at: 0)
            }

            // Generate high-resolution retina thumbnail in background
            generateThumbnail(for: url, itemId: placeholderItem.id)
        }
    }

    /// Removes an item from the shelf by UUID with animation.
    func remove(id: UUID) {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            items.removeAll(where: { $0.id == id })
        }
    }

    /// Clears all items currently in the shelf.
    func clearAll() {
        guard !items.isEmpty else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
            items.removeAll()
        }
    }

    /// Reveals the selected file in macOS Finder.
    func revealInFinder(item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Opens the file with its default macOS viewer application.
    func openFile(item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    // MARK: - QuickLook Thumbnail Generation

    private func generateThumbnail(for url: URL, itemId: UUID) {
        let size = CGSize(width: 96, height: 96)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, error in
            guard let self = self, let cgImage = representation?.cgImage else { return }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 48, height: 48))

            DispatchQueue.main.async {
                if let index = self.items.firstIndex(where: { $0.id == itemId }) {
                    let old = self.items[index]
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.items[index] = ShelfItem(
                            id: old.id,
                            url: old.url,
                            name: old.name,
                            fileSizeString: old.fileSizeString,
                            thumbnail: nsImage,
                            creationDate: old.creationDate
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedFileSize(for url: URL) -> String {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if resourceValues.isDirectory == true {
                return "KLASÖR"
            }
            if let size = resourceValues.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
        } catch {}
        return ""
    }
}
