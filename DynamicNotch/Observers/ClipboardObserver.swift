// ClipboardObserver.swift
// DynamicNotch / Observers
//
// Apple-grade background clipboard monitor for DynamicNotch.
// Tracks NSPasteboard changeCount with minimal CPU footprint, parses rich content
// (Text, Images, Files, URLs), and provides seamless copy-back capabilities.

import AppKit
import Combine
import UniformTypeIdentifiers

final class ClipboardObserver: ObservableObject {

    // MARK: - Models

    struct ClipboardItem: Identifiable, Equatable {
        let id: UUID
        let type: ItemType
        let displayName: String
        let detailText: String
        let preview: NSImage?
        let copiedDate: Date
        let rawContent: Any

        init(
            id: UUID = UUID(),
            type: ItemType,
            displayName: String,
            detailText: String,
            preview: NSImage? = nil,
            copiedDate: Date = Date(),
            rawContent: Any
        ) {
            self.id = id
            self.type = type
            self.displayName = displayName
            self.detailText = detailText
            self.preview = preview
            self.copiedDate = copiedDate
            self.rawContent = rawContent
        }

        static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
            lhs.id == rhs.id
        }

        enum ItemType: Equatable {
            case text(String)
            case image
            case file(URL)
            case url(URL)

            var systemIcon: String {
                switch self {
                case .text:
                    return "doc.text.fill"
                case .image:
                    return "photo.fill"
                case .file(let url):
                    let ext = url.pathExtension.lowercased()
                    switch ext {
                    case "png", "jpg", "jpeg", "heic", "webp", "gif", "svg":
                        return "photo.fill"
                    case "pdf":
                        return "doc.richtext.fill"
                    case "mp4", "mov", "mkv", "avi":
                        return "film.fill"
                    case "mp3", "m4a", "wav", "flac":
                        return "music.note"
                    case "zip", "tar", "gz", "rar", "7z":
                        return "archivebox.fill"
                    case "swift", "js", "ts", "py", "html", "css", "json", "sh":
                        return "chevron.left.forwardslash.chevron.right"
                    default:
                        return "doc.fill"
                    }
                case .url:
                    return "link"
                }
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var clipboardItems: [ClipboardItem] = []
    @Published private(set) var lastCopiedItem: ClipboardItem? = nil

    // MARK: - Private Properties

    private var pollingTimer: AnyCancellable?
    private var lastChangeCount: Int = 0
    private var isInternalCopy: Bool = false
    private let maxItems: Int = 8

    // MARK: - Initialization

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Engine

    func startMonitoring() {
        pollingTimer?.cancel()
        pollingTimer = Timer.publish(every: 0.45, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.inspectPasteboard()
            }
    }

    func stopMonitoring() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func inspectPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // If this change was initiated internally from DynamicNotch, skip adding a duplicate
        if isInternalCopy {
            isInternalCopy = false
            return
        }

        parsePasteboard(pasteboard)
    }

    private func parsePasteboard(_ pasteboard: NSPasteboard) {
        var createdItem: ClipboardItem? = nil

        // 1. Files / Folders (Finder copies)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first,
           firstURL.isFileURL {
            let filename = firstURL.lastPathComponent
            let isDir = (try? firstURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let icon = NSWorkspace.shared.icon(forFile: firstURL.path)

            var detail = isDir ? "Klasör" : firstURL.pathExtension.uppercased()
            if detail.isEmpty { detail = "Dosya" }

            var thumbnail: NSImage? = nil
            let imageExtensions = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"]
            if imageExtensions.contains(firstURL.pathExtension.lowercased()) {
                if let fileImage = NSImage(contentsOf: firstURL) {
                    thumbnail = fileImage
                }
            }

            createdItem = ClipboardItem(
                type: .file(firstURL),
                displayName: filename,
                detailText: detail,
                preview: thumbnail ?? icon,
                rawContent: firstURL
            )
        }
        // 2. Images (Screenshots, copied bitmaps, photos)
        else if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let size = image.size
            let detail = "\(Int(size.width)) × \(Int(size.height))"

            createdItem = ClipboardItem(
                type: .image,
                displayName: "Görüntü",
                detailText: detail,
                preview: image,
                rawContent: image
            )
        }
        // 3. Web URLs (either as NSURL object or plain text string)
        else if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                let firstURL = urls.first,
                !firstURL.isFileURL,
                let scheme = firstURL.scheme?.lowercased(),
                (scheme == "http" || scheme == "https") {
            let host = firstURL.host ?? "Web Bağlantısı"
            createdItem = ClipboardItem(
                type: .url(firstURL),
                displayName: host,
                detailText: firstURL.absoluteString,
                preview: nil,
                rawContent: firstURL
            )
        }
        else if let urlString = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                let validURL = URL(string: urlString),
                let scheme = validURL.scheme?.lowercased(),
                (scheme == "http" || scheme == "https") {
            let host = validURL.host ?? "Web Bağlantısı"
            createdItem = ClipboardItem(
                type: .url(validURL),
                displayName: host,
                detailText: urlString,
                preview: nil,
                rawContent: validURL
            )
        }
        // 4. Plain / Formatted Text
        else if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let charCount = clean.count
            let lineCount = clean.components(separatedBy: .newlines).count
            let detail = lineCount > 1 ? "\(lineCount) satır • \(charCount) harf" : "\(charCount) karakter"

            let lines = clean.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let firstLine = lines.first ?? clean
            let previewText = firstLine.count > 55 ? String(firstLine.prefix(55)) + "…" : firstLine

            createdItem = ClipboardItem(
                type: .text(clean),
                displayName: previewText,
                detailText: detail,
                preview: nil,
                rawContent: clean
            )
        }

        guard let newItem = createdItem else { return }

        // Remove duplicate if identical content already exists
        clipboardItems.removeAll { existing in
            existing.displayName == newItem.displayName && existing.detailText == newItem.detailText
        }

        clipboardItems.insert(newItem, at: 0)
        if clipboardItems.count > maxItems {
            clipboardItems = Array(clipboardItems.prefix(maxItems))
        }

        lastCopiedItem = newItem
    }

    // MARK: - User Actions

    /// Restores the selected item back to macOS NSPasteboard with appropriate data flavor.
    func copyBackToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        isInternalCopy = true
        pasteboard.clearContents()

        switch item.type {
        case .text(let str):
            pasteboard.setString(str, forType: .string)
        case .image:
            if let image = item.rawContent as? NSImage {
                pasteboard.writeObjects([image])
                if let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let pngData = rep.representation(using: .png, properties: [:]) {
                    pasteboard.setData(pngData, forType: .png)
                }
            }
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        case .url(let url):
            pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.absoluteString, forType: .string)
        }

        lastChangeCount = pasteboard.changeCount
    }

    func removeItem(_ item: ClipboardItem) {
        clipboardItems.removeAll { $0.id == item.id }
        if lastCopiedItem?.id == item.id {
            lastCopiedItem = clipboardItems.first
        }
    }

    func clearAll() {
        clipboardItems.removeAll()
        lastCopiedItem = nil
    }
}
