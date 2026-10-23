// QuickReminderComposerView.swift
// DynamicNotch / Features / QuickReminder
//
// Apple-grade Quick Reminder composer engineered with Apple Human Interface Guidelines.
// Features:
// • Iconic Apple Reminders circular checkbox bullet with micro-interaction.
// • Direct, instantaneous first-responder keyboard focus on open.
// • Custom AppKit NSTextView backing for zero-latency typing, auto-wrap, and Reminders blue caret.
// • Smart quick-action chips (Bugün, Yarın, Önemli) for instant date/priority tagging.
// • Global keyboard orchestration:
//   - Return or Cmd + Return (↵ / ⌘↵) -> Saves reminder to Apple Reminders (iCloud).
//   - Escape (esc) -> Dismisses composer smoothly.
// • Liquid Glass Action Buttons with Specular Crest, Reminders blue gradient,
//   and tactile micro-press spring dynamics.

import SwiftUI
import AppKit

struct QuickReminderComposerView: View {

    let onSave: (String, ReminderDueOption, Bool) -> Void
    let onDismiss: () -> Void
    var onSetKeyFocus: ((Bool) -> Void)? = nil

    @State private var text: String = ""
    @State private var selectedDueOption: ReminderDueOption = .none
    @State private var isHighPriority: Bool = false
    @State private var isCheckedVisual: Bool = false
    @State private var isHoveringCancel: Bool = false
    @State private var isHoveringSave: Bool = false
    @State private var isSaving: Bool = false

    // Exact Apple Reminders Brand Palette
    private let remindersBlueStart = Color(red: 0.10, green: 0.52, blue: 1.00) // #1A85FF
    private let remindersBlueEnd   = Color(red: 0.02, green: 0.38, blue: 0.94) // #0561F0
    private let remindersFlagRed   = Color(red: 1.00, green: 0.23, blue: 0.19) // Apple System Red

    private var isTurkish: Bool {
        if let preferred = Locale.preferredLanguages.first, preferred.lowercased().hasPrefix("tr") {
            return true
        }
        if let code = Locale.current.language.languageCode?.identifier, code.lowercased().hasPrefix("tr") {
            return true
        }
        return Locale.current.identifier.lowercased().hasPrefix("tr")
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 8) {

            // MARK: - Row 1: Header (Icon, Title & ⌘↵ Shortcut Badge)
            HStack(alignment: .center, spacing: 8) {
                // Apple Reminders Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [remindersBlueStart, remindersBlueEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: remindersBlueStart.opacity(0.35), radius: 3, y: 1)

                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

                // Header Title
                Text(isTurkish ? "Hızlı Anımsatıcı" : "Quick Reminder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))

                Spacer(minLength: 4)

                // Shortcut Hint: ⌘↵ save
                HStack(spacing: 3) {
                    HStack(spacing: 1.5) {
                        Text("⌘")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        Text("↵")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                    Text(isTurkish ? "kaydet" : "save")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                }
                .foregroundColor(.white.opacity(0.40))
            }
            .padding(.horizontal, 2)

            // MARK: - Row 2: Editor Canvas (Iconic Circle Checkbox + Text Input)
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
                                lineWidth: 0.75
                            )
                    )

                HStack(alignment: .top, spacing: 8) {
                    // Apple Reminders Iconic Circular Bullet Button
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.70)) {
                            isCheckedVisual.toggle()
                        }
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    isCheckedVisual ? remindersBlueStart : Color.white.opacity(0.35),
                                    lineWidth: 1.6
                                )
                                .frame(width: 16, height: 16)

                            if isCheckedVisual {
                                Circle()
                                    .fill(remindersBlueStart)
                                    .frame(width: 10, height: 10)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)

                    // Text Editor
                    QuickReminderTextViewRepresentable(
                        text: $text,
                        placeholder: isTurkish ? "Anımsatıcı ekle..." : "Add a reminder...",
                        onCommit: {
                            commitSave()
                        },
                        onCancel: {
                            dismissComposer()
                        }
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 50)

            // MARK: - Row 3: Unified Controls Bar (Chips on Left + Actions on Right)
            HStack(alignment: .center, spacing: 6) {
                // Chip 1: Bugün
                quickChip(
                    title: isTurkish ? "Bugün" : "Today",
                    symbol: "calendar.badge.clock",
                    isSelected: selectedDueOption == .today,
                    accentColor: remindersBlueStart
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        selectedDueOption = (selectedDueOption == .today) ? .none : .today
                    }
                }

                // Chip 2: Yarın
                quickChip(
                    title: isTurkish ? "Yarın" : "Tomorrow",
                    symbol: "sunrise.fill",
                    isSelected: selectedDueOption == .tomorrow,
                    accentColor: remindersBlueStart
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        selectedDueOption = (selectedDueOption == .tomorrow) ? .none : .tomorrow
                    }
                }

                // Chip 3: Önemli (Flag)
                quickChip(
                    title: isTurkish ? "Önemli" : "Flag",
                    symbol: "flag.fill",
                    isSelected: isHighPriority,
                    accentColor: remindersFlagRed
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        isHighPriority.toggle()
                    }
                }

                Spacer(minLength: 6)

                // Cancel Button: [esc vazgeç]
                Button(action: dismissComposer) {
                    HStack(spacing: 3) {
                        Text("esc")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.white.opacity(isHoveringCancel ? 0.14 : 0.07))
                            )

                        Text(isTurkish ? "vazgeç" : "cancel")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(isHoveringCancel ? 0.90 : 0.50))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isHoveringCancel ? 0.10 : 0.04))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringCancel = $0 }

                // Liquid Glass Save Button
                Button(action: commitSave) {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))

                            Text(isTurkish ? "Kaydet" : "Save")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundColor(canSave ? .white : .white.opacity(0.30))
                    .padding(.horizontal, 11)
                    .frame(height: 25)
                    .background(
                        ZStack {
                            if canSave {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [remindersBlueStart, remindersBlueEnd],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 0.75
                                            )
                                    )
                                    .shadow(color: remindersBlueStart.opacity(isHoveringSave ? 0.45 : 0.25), radius: 4, y: 1)
                            } else {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            }
                        }
                    )
                    .scaleEffect(isHoveringSave && canSave ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .onHover { isHoveringSave = $0 }
            }
            .frame(height: 26)
            .padding(.horizontal, 2)
        }
        .frame(height: 112)
        .onAppear {
            onSetKeyFocus?(true)
        }
        .onDisappear {
            onSetKeyFocus?(false)
        }
    }

    // MARK: - Quick Chip Component

    private func quickChip(
        title: String,
        symbol: String,
        isSelected: Bool,
        accentColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .semibold))

                Text(title)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.65))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                ZStack {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.35))
                        Capsule(style: .continuous)
                            .stroke(accentColor.opacity(0.70), lineWidth: 0.8)
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func commitSave() {
        guard canSave else { return }
        isSaving = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        onSave(text, selectedDueOption, isHighPriority)
    }

    private func dismissComposer() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        onDismiss()
    }
}

// MARK: - QuickReminderTextViewRepresentable

struct QuickReminderTextViewRepresentable: NSViewRepresentable {

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

        let textView = KeyInterceptingReminderTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.insertionPointColor = NSColor(red: 0.10, green: 0.52, blue: 1.00, alpha: 1.0) // Apple Reminders blue caret
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? KeyInterceptingReminderTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickReminderTextViewRepresentable
        weak var textView: KeyInterceptingReminderTextView?

        init(_ parent: QuickReminderTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - KeyInterceptingReminderTextView

final class KeyInterceptingReminderTextView: NSTextView {

    var placeholderString: String = ""
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Return or Cmd + Return -> Commit
        if event.keyCode == 36 || event.keyCode == 76 {
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
