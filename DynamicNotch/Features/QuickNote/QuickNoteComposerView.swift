// QuickNoteComposerView.swift
// DynamicNotch / Features / QuickNote
//
// Apple-grade Quick Note composer engineered with Apple Human Interface Guidelines.
// Features:
// • Direct, instantaneous first-responder keyboard focus on open.
// • Custom AppKit NSTextView backing for zero-latency typing, auto-wrap, and caret styling.
// • Global keyboard orchestration:
//   - Cmd + Return (⌘↵) -> Saves note to Apple Notes.
//   - Escape (esc) -> Dismisses composer smoothly.
// • Liquid Glass Action Buttons with Specular Crest, Apple Notes gold gradient,
//   and tactile micro-press spring dynamics.

import SwiftUI
import AppKit

struct QuickNoteComposerView: View {

    let onSave: (String) -> Void
    let onDismiss: () -> Void
    var onSetKeyFocus: ((Bool) -> Void)? = nil

    @State private var text: String = ""
    @State private var isHoveringCancel: Bool = false
    @State private var isHoveringSave: Bool = false
    @State private var isSaving: Bool = false

    // Exact Apple Notes Brand Gold / Amber Palettes
    private let notesAmberStart = Color(red: 0.98, green: 0.76, blue: 0.28) // #FAB247
    private let notesAmberEnd   = Color(red: 0.86, green: 0.54, blue: 0.10) // #DB8A1A
    private let darkAmberLabel  = Color(red: 0.12, green: 0.08, blue: 0.01) // #1F1403

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 9) {

            // MARK: - Header (Icon, Title, Shortcut Hint & Close)
            HStack(alignment: .center, spacing: 8) {
                // Apple Notes Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [notesAmberStart, notesAmberEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: notesAmberStart.opacity(0.30), radius: 3, y: 1)

                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

                // Header Title
                Text(isTurkish ? "Hızlı Not" : "Quick Note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))

                Spacer(minLength: 4)

                // Shortcut Hint: ⌘↵ save (identically styled to "esc cancel" in footer)
                HStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        Text("↵")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )

                    Text(isTurkish ? "kaydet" : "save")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                }
                .foregroundColor(.white.opacity(0.40))
            }
            .padding(.horizontal, 4)

            // MARK: - Editor Canvas
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )

                QuickNoteTextViewRepresentable(
                    text: $text,
                    placeholder: isTurkish ? "Bir not yazın..." : "Write a note...",
                    onCommit: {
                        commitSave()
                    },
                    onCancel: {
                        dismissComposer()
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 62)

            // MARK: - Footer Actions Row
            HStack(alignment: .center, spacing: 8) {
                // Secondary Shortcut Hint (Esc)
                HStack(spacing: 4) {
                    Text("esc")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )

                    Text(isTurkish ? "vazgeç" : "cancel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                }
                .foregroundColor(.white.opacity(0.40))

                Spacer(minLength: 8)

                // 1. Cancel Button
                Button {
                    dismissComposer()
                } label: {
                    Text(isTurkish ? "Vazgeç" : "Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(isHoveringCancel ? 0.90 : 0.65))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isHoveringCancel ? 0.12 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringCancel = $0 }

                // 2. Liquid Glass Save Button (Apple Notes Amber)
                Button {
                    commitSave()
                } label: {
                    HStack(spacing: 4.5) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: darkAmberLabel))
                                .scaleEffect(0.65)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9.5, weight: .bold))
                        }

                        Text(isTurkish ? "Kaydet" : "Save")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(canSave ? darkAmberLabel : .white.opacity(0.25))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(
                        ZStack {
                            if canSave {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [notesAmberStart, notesAmberEnd],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.60), Color.clear],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(
                                        color: notesAmberStart.opacity(isHoveringSave ? 0.45 : 0.25),
                                        radius: 6,
                                        y: 2
                                    )
                            } else {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .onHover { isHoveringSave = $0 }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 130)
        .onAppear {
            onSetKeyFocus?(true)
        }
        .onDisappear {
            onSetKeyFocus?(false)
        }
    }

    private func commitSave() {
        guard canSave else { return }
        isSaving = true
        onSave(text)
    }

    private func dismissComposer() {
        onSetKeyFocus?(false)
        onDismiss()
    }
}

// MARK: - AppKit Native NSTextView Representable
// Provides immediate keyboard focus, caret tinting, and key-event interception (⌘↵ and Esc).

struct QuickNoteTextViewRepresentable: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = KeyInterceptingTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.insertionPointColor = NSColor(red: 0.98, green: 0.76, blue: 0.28, alpha: 1.0) // Apple Notes gold caret
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 2)

        textView.placeholderString = placeholder
        textView.onCommit = onCommit
        textView.onCancel = onCancel

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Schedule first responder after window is key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? KeyInterceptingTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickNoteTextViewRepresentable
        weak var textView: KeyInterceptingTextView?

        init(_ parent: QuickNoteTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - KeyInterceptingTextView

final class KeyInterceptingTextView: NSTextView {

    var placeholderString: String = ""
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd + Return or Cmd + Keypad Enter -> Commit
        if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command) {
            onCommit?()
            return true
        }

        // Standard editing shortcuts support (Cmd + A, C, V, X, Z, Shift+Z)
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                selectAll(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "z":
                undoManager?.undo()
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                undoManager?.redo()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Escape -> Dismiss
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty && !placeholderString.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.35)
            ]
            let origin = NSPoint(x: 0, y: textContainerInset.height)
            (placeholderString as NSString).draw(at: origin, withAttributes: attributes)
        }
    }
}
