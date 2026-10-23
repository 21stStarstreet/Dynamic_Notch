// ClipboardView.swift
// DynamicNotch / Features / Clipboard
//
// Apple-grade Liquid Glass Clipboard History Viewer for DynamicNotch.
// Symmetrical, perfectly balanced card layout that fills available width evenly,
// with rich metadata, tactile spring interactions, and copy feedback.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ClipboardView: View {

    @ObservedObject var observer: ClipboardObserver
    let onDismiss: () -> Void
    var onItemsChanged: (([ClipboardObserver.ClipboardItem]) -> Void)? = nil

    init(
        observer: ClipboardObserver,
        onDismiss: @escaping () -> Void,
        onItemsChanged: (([ClipboardObserver.ClipboardItem]) -> Void)? = nil
    ) {
        self.observer = observer
        self.onDismiss = onDismiss
        self.onItemsChanged = onItemsChanged
    }

    @State private var isHoveringClear: Bool = false
    @State private var copiedItemID: UUID? = nil

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var items: [ClipboardObserver.ClipboardItem] {
        observer.clipboardItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // MARK: - Header Bar (Symmetrical with Cards)

            HStack(alignment: .center, spacing: 6) {
                // Left: Icon + Title + Count Badge
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0)) // Apple System Blue

                    Text(isTurkish ? "Pano Geçmişi" : "Clipboard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    Text("\(items.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                }

                Spacer()

                // Right: Clear All Button
                if !items.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            observer.clearAll()
                            onDismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5, weight: .medium))
                            Text(isTurkish ? "Temizle" : "Clear All")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(isHoveringClear ? 0.95 : 0.60))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isHoveringClear ? 0.20 : 0.09))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(isHoveringClear ? 0.24 : 0.12), lineWidth: 0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.14)) {
                            isHoveringClear = hovering
                        }
                    }
                }
            }
            .frame(height: 22)
            .frame(maxWidth: .infinity)

            // MARK: - Cards Layout (Adaptive: Grid when <= 3, ScrollView when > 3)

            if items.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.25))
                        Text(isTurkish ? "Pano boş" : "Clipboard empty")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .frame(height: 60)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if items.count <= 3 {
                // Balanced Equal-Width Grid (Fills 100% of available notch width evenly: 100% for 1, 50% for 2, 33% for 3)
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        ClipboardItemCard(
                            item: item,
                            isCopiedFeedback: copiedItemID == item.id,
                            onTap: {
                                handleItemTap(item)
                            },
                            onDelete: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    observer.removeItem(item)
                                    if observer.clipboardItems.isEmpty {
                                        onDismiss()
                                    } else {
                                        onItemsChanged?(observer.clipboardItems)
                                    }
                                }
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                // Horizontal Carousel for 4+ items
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            ClipboardItemCard(
                                item: item,
                                isCopiedFeedback: copiedItemID == item.id,
                                onTap: {
                                    handleItemTap(item)
                                },
                                onDelete: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                        observer.removeItem(item)
                                        if observer.clipboardItems.isEmpty {
                                            onDismiss()
                                        } else {
                                            onItemsChanged?(observer.clipboardItems)
                                        }
                                    }
                                }
                            )
                            .frame(width: 130)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func handleItemTap(_ item: ClipboardObserver.ClipboardItem) {
        observer.copyBackToClipboard(item)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
            copiedItemID = item.id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeInOut(duration: 0.20)) {
                if self.copiedItemID == item.id {
                    self.copiedItemID = nil
                }
            }
        }
    }
}

// MARK: - Apple Liquid Glass Clipboard Card

struct ClipboardItemCard: View {

    let item: ClipboardObserver.ClipboardItem
    let isCopiedFeedback: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering: Bool = false
    @State private var isHoveringDelete: Bool = false

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var typeColor: Color {
        switch item.type {
        case .text:
            return Color(red: 0.35, green: 0.65, blue: 1.0)  // Apple Blue
        case .image:
            return Color(red: 0.68, green: 0.45, blue: 0.95) // Apple Purple
        case .file:
            return Color(red: 0.98, green: 0.58, blue: 0.12) // Apple Orange
        case .url:
            return Color(red: 0.20, green: 0.78, blue: 0.85) // Apple Cyan
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {

            // Main Interactive Card Body (Click to copy, Drag to drop anywhere)
            VStack(alignment: .leading, spacing: 5) {

                // Top Row: Type Icon / Thumbnail + Detail Metadata Tag
                HStack(alignment: .center, spacing: 6) {
                    ZStack {
                        if isCopiedFeedback {
                            Circle()
                                .fill(Color(red: 0.18, green: 0.80, blue: 0.44)) // Apple Green
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        } else if let preview = item.preview, case .image = item.type {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(typeColor.opacity(0.18))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: item.type.systemIcon)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(typeColor)
                                )
                        }
                    }

                    // Detail Tag (e.g. "2 satır • 146 harf" or "PDF" or "PNG")
                    Text(item.detailText)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.50))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }

                // Content Title (2 lines with natural leading and tail truncation)
                Text(isCopiedFeedback ? (isTurkish ? "Kopyalandı!" : "Copied!") : item.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(isCopiedFeedback ? Color(red: 0.25, green: 0.85, blue: 0.50) : .white.opacity(0.92))
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovering ? 0.13 : 0.07),
                                Color.white.opacity(isHovering ? 0.07 : 0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                Color.white.opacity(isHovering ? 0.22 : 0.10),
                                lineWidth: 0.8
                            )
                    )
            )
            .scaleEffect(isHovering ? 1.018 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.30 : 0.0), radius: 6, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                guard !isHoveringDelete else { return }
                onTap()
            }
            .onDrag {
                itemProvider()
            } preview: {
                dragPreview
            }

            // Top-Right Discrete Delete Button (Appears on Card Hover)
            if isHovering && !isCopiedFeedback {
                Button(action: onDelete) {
                    ZStack {
                        // Generous 24x24 hit target ensures zero miss clicks
                        Color.clear
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())

                        Circle()
                            .fill(Color.black.opacity(isHoveringDelete ? 0.85 : 0.65))
                            .frame(width: 15, height: 15)

                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(isHoveringDelete ? 1.0 : 0.65))
                    }
                }
                .buttonStyle(.plain)
                .zIndex(30)
                .padding(3)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .onHover { isHoveringDelete = $0 }
            }
        }
        .frame(maxWidth: .infinity)
        .onHover { isHovering = $0 }
    }

    // MARK: - Universal Drag and Drop Helpers

    private func itemProvider() -> NSItemProvider {
        switch item.type {
        case .file(let url):
            // Native macOS file drag: register `url as NSURL` directly so Finder, Desktop, Mail,
            // Telegram, WhatsApp, Slack and browser uploaders receive the ACTUAL REAL FILE.
            // Never register plain text file path strings, which causes target apps to paste
            // the text path instead of the file itself!
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = url.lastPathComponent

            // If it's an image file, also register the NSImage representation so graphics apps can accept it directly
            let imageExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"]
            if imageExtensions.contains(url.pathExtension.lowercased()),
               let image = NSImage(contentsOf: url) {
                provider.registerObject(image, visibility: .all)
            }
            return provider

        case .image:
            if let image = (item.rawContent as? NSImage) ?? item.preview {
                // When dragged to Finder, Desktop, WhatsApp or Telegram, provide a real temporary PNG file
                // without registering plain text so it attaches as an actual photo/file!
                if let tempFileURL = temporaryImageURL(for: image, id: item.id) {
                    let provider = NSItemProvider(object: tempFileURL as NSURL)
                    provider.suggestedName = "image.png"

                    // Register image object for native AppKit/Cocoa apps
                    provider.registerObject(image, visibility: .all)

                    // Register PNG data representation for web apps, Figma, Slack, Discord
                    if let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                            completion(pngData, nil)
                            return nil
                        }
                    }

                    return provider
                }

                // Fallback in-memory provider
                let provider = NSItemProvider(object: image)
                provider.suggestedName = "image.png"
                if let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                        completion(pngData, nil)
                        return nil
                    }
                }
                return provider
            }
            return NSItemProvider()

        case .url(let url):
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = item.displayName
            if let stringData = url.absoluteString.data(using: .utf8) {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                    completion(stringData, nil)
                    return nil
                }
                provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
                    completion(stringData, nil)
                    return nil
                }
            }
            return provider

        case .text(let text):
            let provider = NSItemProvider(object: text as NSString)
            provider.suggestedName = "text.txt"
            if let textData = text.data(using: .utf8) {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                    completion(textData, nil)
                    return nil
                }
                provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
                    completion(textData, nil)
                    return nil
                }
                provider.registerDataRepresentation(forTypeIdentifier: UTType.text.identifier, visibility: .all) { completion in
                    completion(textData, nil)
                    return nil
                }
            }
            return provider
        }
    }

    private func temporaryImageURL(for image: NSImage, id: UUID) -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("DynamicNotchClipboard", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let fileURL = tempDir.appendingPathComponent("image.png")

            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }

            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }

            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    @ViewBuilder
    private var dragPreview: some View {
        HStack(spacing: 8) {
            ZStack {
                if let preview = item.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(typeColor.opacity(0.30))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: item.type.systemIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(typeColor)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(item.detailText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.60))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.40), radius: 8, x: 0, y: 4)
        )
    }
}
