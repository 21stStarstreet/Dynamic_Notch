// ShelfItem.swift
// DynamicNotch / Features / Shelf
//
// Immutable model representing a file, folder, or document temporarily held
// on the Notch Shelf (Tray) for drag-and-drop operations across macOS spaces.

import Foundation
import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let fileSizeString: String
    let thumbnail: NSImage?
    let creationDate: Date

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        fileSizeString: String,
        thumbnail: NSImage? = nil,
        creationDate: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.fileSizeString = fileSizeString
        self.thumbnail = thumbnail
        self.creationDate = creationDate
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }

    /// File extension in uppercase (e.g. "PNG", "PDF", "ZIP").
    var fileExtension: String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? "DOSYA" : ext.uppercased()
    }

    /// SF Symbol icon associated with this file's type.
    var systemIconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "tiff", "svg":
            return "photo.fill"
        case "mp4", "mov", "m4v", "avi", "mkv":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac", "aiff":
            return "waveform"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "rar", "7z", "dmg", "pkg":
            return "archivebox.fill"
        case "swift", "js", "ts", "py", "html", "css", "json", "xml", "cpp", "c", "h", "sh":
            return "curlybraces"
        case "txt", "rtf", "md":
            return "doc.text.fill"
        case "doc", "docx", "pages":
            return "doc.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "presentation.fill"
        default:
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return "folder.fill"
            }
            return "doc.fill"
        }
    }
}
