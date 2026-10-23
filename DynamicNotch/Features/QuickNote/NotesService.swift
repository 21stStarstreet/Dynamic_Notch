// NotesService.swift
// DynamicNotch / Features / QuickNote
//
// Apple-grade service for integrating with macOS Apple Notes (Notlar).
// Dispatches note creation asynchronously via NSAppleScript without blocking
// the main thread or dropping 120 FPS ProMotion animation frames.
//
// Highlights:
// • Automatic Title & Body formatting: first line styled as Title (h1),
//   subsequent lines styled as clean body paragraphs (div / p).
// • Dual-path fallback: attempts the user's primary/default account & folder,
//   with seamless fallback to universal root note creation.
// • Full HTML & AppleScript character escaping.

import Foundation
import AppKit

final class NotesService {

    static let shared = NotesService()

    private init() {}

    enum NotesError: LocalizedError {
        case emptyNote
        case scriptExecutionFailed(String)
        case scriptCompilationFailed

        var errorDescription: String? {
            switch self {
            case .emptyNote:
                return "Not içeriği boş olamaz."
            case .scriptExecutionFailed(let message):
                return "Apple Notlar komutu çalıştırılamadı: \(message)"
            case .scriptCompilationFailed:
                return "AppleScript derlenemedi."
            }
        }
    }

    /// Creates a new note in Apple Notes with the provided raw text.
    /// - Parameters:
    ///   - text: The multi-line text entered by the user.
    ///   - completion: Callback returning the extracted note title or error on the main thread.
    func createNote(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NotesError.emptyNote))
            return
        }

        // Extract title from the first non-empty line
        let lines = trimmed.components(separatedBy: .newlines)
        let firstLine = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Yeni Not"
        let displayTitle = firstLine.trimmingCharacters(in: .whitespaces)

        // Build HTML body for Apple Notes
        let htmlBody = buildHtmlBody(from: lines)
        let escapedHtmlForScript = escapeForAppleScript(htmlBody)

        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = """
            tell application "Notes"
                try
                    tell default account
                        make new note at default folder with properties {body:"\(escapedHtmlForScript)"}
                    end tell
                on error
                    try
                        tell default account
                            make new note with properties {body:"\(escapedHtmlForScript)"}
                        end tell
                    on error
                        make new note with properties {body:"\(escapedHtmlForScript)"}
                    end try
                end try
            end tell
            """

            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else {
                DispatchQueue.main.async {
                    completion(.failure(NotesError.scriptCompilationFailed))
                }
                return
            }

            script.executeAndReturnError(&errorInfo)

            DispatchQueue.main.async {
                if let errorInfo = errorInfo {
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Bilinmeyen hata"
                    completion(.failure(NotesError.scriptExecutionFailed(message)))
                } else {
                    completion(.success(displayTitle))
                }
            }
        }
    }

    // MARK: - HTML Formatting & Escaping Helpers

    private func buildHtmlBody(from lines: [String]) -> String {
        var html = "<div>"
        var isFirstLine = true

        for line in lines {
            let escaped = escapeForHtml(line)
            if isFirstLine {
                html += "<h1>\(escaped.isEmpty ? "&nbsp;" : escaped)</h1>"
                isFirstLine = false
            } else {
                if escaped.isEmpty {
                    html += "<div><br></div>"
                } else {
                    html += "<div>\(escaped)</div>"
                }
            }
        }

        html += "</div>"
        return html
    }

    private func escapeForHtml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}
