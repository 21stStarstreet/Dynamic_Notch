// TimerSetupView.swift
// DynamicNotch / Features / Timer
//
// Apple-grade Timer Setup interface for Dynamic Notch.
// Matches the exact visual DNA, proportions, 36x36pt circular controls,
// and SF Pro Rounded typography of Apple's Dynamic Notch Timer Live Activity.
// Zero capsules, perfectly proportioned, balanced horizontal spacing.
// Supports:
// 1. Direct keyboard numeric entry (0-9, Tab, Arrows, Enter, Space, Esc, Backspace, :)
// 2. Continuous trackpad two-finger scrolling and mouse scroll wheel on each dial
// 3. Vertical click & drag gesture on dials
// 4. Arrow buttons (chevrons) and tap gestures

import SwiftUI
import AppKit

enum DialUnit: Int, CaseIterable {
    case hours = 0
    case minutes = 1
    case seconds = 2
}

struct TimerSetupView: View {

    @ObservedObject var observer: TimerObserver
    let onDismiss: () -> Void
    var onSetKeyFocus: ((Bool) -> Void)? = nil

    @State private var hours: Int = 0
    @State private var minutes: Int = 5
    @State private var seconds: Int = 0

    @State private var focusedUnit: DialUnit = .minutes
    @State private var lastDigitTimestamp: TimeInterval = 0
    @State private var eventMonitor: Any? = nil

    @State private var isHoveringStart: Bool = false
    @State private var isHoveringCancel: Bool = false

    // Exact Apple colors sampled from reference screenshot:
    private let timerOrange = Color(red: 0.975, green: 0.565, blue: 0.187) // #F8902F
    private let pauseBg     = Color(red: 0.30, green: 0.17, blue: 0.07)   // #4C2A11
    private let cancelBg    = Color(red: 0.18, green: 0.18, blue: 0.19)   // #2E2E2F

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var totalSeconds: TimeInterval {
        TimeInterval((hours * 3600) + (minutes * 60) + seconds)
    }

    private var hasValidDuration: Bool {
        totalSeconds > 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {

            // MARK: - Left Controls (Start ▶ & Cancel ✕) - Enlarged 42x42pt Apple Circles

            HStack(spacing: 9) {
                // 1. Start Button (42x42 pt)
                Button {
                    startTimer()
                } label: {
                    ZStack {
                        Circle()
                            .fill(hasValidDuration ? pauseBg : Color.white.opacity(0.06))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .fill(isHoveringStart ? Color.white.opacity(0.12) : Color.clear)
                            )

                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(hasValidDuration ? timerOrange : Color.white.opacity(0.25))
                            .offset(x: 1.5)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .disabled(!hasValidDuration)
                .onHover { isHoveringStart = $0 }

                // 2. Cancel Button (42x42 pt)
                Button {
                    dismissView()
                } label: {
                    ZStack {
                        Circle()
                            .fill(cancelBg)
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .fill(isHoveringCancel ? Color.white.opacity(0.12) : Color.clear)
                            )

                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(white: 0.85))
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .onHover { isHoveringCancel = $0 }
            }
            .offset(y: 4.5)

            Spacer(minLength: 16)

            // MARK: - Right Controls (Saat : Dakika : Saniye Dials)

            HStack(alignment: .center, spacing: 4) {

                // Apple Timer Icon
                Image(systemName: "timer")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(timerOrange)
                    .padding(.trailing, 4)
                    .padding(.bottom, 9)

                // 1. Saat (Hours)
                TimeDialColumn(
                    value: $hours,
                    range: 0...23,
                    label: isTurkish ? "saat" : "hr",
                    color: timerOrange,
                    isFocused: focusedUnit == .hours,
                    onFocus: { focusedUnit = .hours }
                )

                // Colon Separator
                Text(":")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(timerOrange.opacity(0.70))
                    .padding(.bottom, 9)

                // 2. Dakika (Minutes)
                TimeDialColumn(
                    value: $minutes,
                    range: 0...59,
                    label: isTurkish ? "dk" : "min",
                    color: timerOrange,
                    isFocused: focusedUnit == .minutes,
                    onFocus: { focusedUnit = .minutes }
                )

                // Colon Separator
                Text(":")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(timerOrange.opacity(0.70))
                    .padding(.bottom, 9)

                // 3. Saniye (Seconds)
                TimeDialColumn(
                    value: $seconds,
                    range: 0...59,
                    label: isTurkish ? "sn" : "sec",
                    color: timerOrange,
                    isFocused: focusedUnit == .seconds,
                    onFocus: { focusedUnit = .seconds }
                )
            }
        }
        .frame(height: 56)
        .contentShape(Rectangle())
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            teardownKeyboardMonitor()
        }
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardMonitor() {
        onSetKeyFocus?(true)
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if self.handleKeyDown(event) {
                    return nil
                }
                return event
            }
        }
    }

    private func teardownKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        onSetKeyFocus?(false)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Escape -> Dismiss
        if event.keyCode == 53 {
            dismissView()
            return true
        }

        // Return (36) or Keypad Enter (76) -> Start Timer
        if event.keyCode == 36 || event.keyCode == 76 {
            startTimer()
            return true
        }

        // Space (49) -> Start Timer if duration valid
        if event.keyCode == 49 {
            if hasValidDuration {
                startTimer()
                return true
            }
        }

        // Tab (48) -> Navigate focus
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                moveFocusLeft()
            } else {
                moveFocusRight()
            }
            return true
        }

        // Left Arrow (123)
        if event.keyCode == 123 {
            moveFocusLeft()
            return true
        }

        // Right Arrow (124)
        if event.keyCode == 124 {
            moveFocusRight()
            return true
        }

        // Up Arrow (126)
        if event.keyCode == 126 {
            let stepSize = event.modifierFlags.contains(.shift) ? 5 : 1
            stepFocused(by: stepSize)
            return true
        }

        // Down Arrow (125)
        if event.keyCode == 125 {
            let stepSize = event.modifierFlags.contains(.shift) ? 5 : 1
            stepFocused(by: -stepSize)
            return true
        }

        // Backspace / Delete (51)
        if event.keyCode == 51 {
            handleBackspace()
            return true
        }

        // Colon (:) -> Move focus right
        if event.characters == ":" {
            moveFocusRight()
            return true
        }

        // Number keys 0 - 9
        if let chars = event.charactersIgnoringModifiers,
           let firstChar = chars.first,
           let digit = firstChar.wholeNumberValue {
            handleDigitInput(digit)
            return true
        }

        return false
    }

    private func moveFocusLeft() {
        switch focusedUnit {
        case .seconds: focusedUnit = .minutes
        case .minutes: focusedUnit = .hours
        case .hours:   focusedUnit = .seconds
        }
        lastDigitTimestamp = 0
    }

    private func moveFocusRight() {
        switch focusedUnit {
        case .hours:   focusedUnit = .minutes
        case .minutes: focusedUnit = .seconds
        case .seconds: focusedUnit = .hours
        }
        lastDigitTimestamp = 0
    }

    private func stepFocused(by delta: Int) {
        switch focusedUnit {
        case .hours:
            hours = wrap(value: hours + delta, in: 0...23)
        case .minutes:
            minutes = wrap(value: minutes + delta, in: 0...59)
        case .seconds:
            seconds = wrap(value: seconds + delta, in: 0...59)
        }
        lastDigitTimestamp = 0
    }

    private func handleDigitInput(_ digit: Int) {
        let now = Date().timeIntervalSinceReferenceDate
        let isRecent = (now - lastDigitTimestamp) < 1.2

        switch focusedUnit {
        case .hours:
            if isRecent && hours < 3 {
                let combined = (hours * 10) + digit
                hours = min(23, combined)
                lastDigitTimestamp = 0
            } else {
                hours = min(23, digit)
                lastDigitTimestamp = now
            }

        case .minutes:
            if isRecent && minutes < 6 {
                let combined = (minutes * 10) + digit
                minutes = min(59, combined)
                lastDigitTimestamp = 0
            } else {
                minutes = min(59, digit)
                lastDigitTimestamp = now
            }

        case .seconds:
            if isRecent && seconds < 6 {
                let combined = (seconds * 10) + digit
                seconds = min(59, combined)
                lastDigitTimestamp = 0
            } else {
                seconds = min(59, digit)
                lastDigitTimestamp = now
            }
        }
    }

    private func handleBackspace() {
        switch focusedUnit {
        case .hours:   hours = hours / 10
        case .minutes: minutes = minutes / 10
        case .seconds: seconds = seconds / 10
        }
        lastDigitTimestamp = 0
    }

    private func wrap(value: Int, in range: ClosedRange<Int>) -> Int {
        if value > range.upperBound { return range.lowerBound }
        if value < range.lowerBound { return range.upperBound }
        return value
    }

    private func startTimer() {
        guard hasValidDuration else { return }
        teardownKeyboardMonitor()
        observer.startTimer(duration: totalSeconds, title: isTurkish ? "Zamanlayıcı" : "Timer")
        onDismiss()
    }

    private func dismissView() {
        teardownKeyboardMonitor()
        onDismiss()
    }
}

// MARK: - Minimal Apple Time Dial Column (Scroll, Drag, Typography & Indicator)

private struct TimeDialColumn: View {

    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String
    let color: Color
    let isFocused: Bool
    let onFocus: () -> Void

    @State private var isHoveringUp: Bool = false
    @State private var isHoveringDown: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            // Minimal Chevron Up (▲)
            Button {
                step(by: 1)
                onFocus()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isFocused ? (isHoveringUp ? .white : color.opacity(0.85)) : .white.opacity(isHoveringUp ? 0.9 : 0.25))
                    .frame(width: 28, height: 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringUp = $0 }

            // Big SF Pro Rounded Digits (24pt)
            Text(String(format: "%02d", value))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(isFocused ? color : color.opacity(0.70))
                .monospacedDigit()
                .frame(width: 34, height: 26)
                .contentShape(Rectangle())
                .onTapGesture {
                    onFocus()
                }

            // Minimal Chevron Down (▼)
            Button {
                step(by: -1)
                onFocus()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isFocused ? (isHoveringDown ? .white : color.opacity(0.85)) : .white.opacity(isHoveringDown ? 0.9 : 0.25))
                    .frame(width: 28, height: 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringDown = $0 }

            // Unit Label (saat / dk / sn)
            Text(label)
                .font(.system(size: 8.5, weight: isFocused ? .semibold : .medium, design: .rounded))
                .foregroundColor(isFocused ? color : Color.white.opacity(0.38))

            // Subtle Apple Indicator Bar (Zero Capsules, Pure Minimal Line)
            RoundedRectangle(cornerRadius: 1)
                .fill(isFocused ? color : Color.clear)
                .frame(width: 14, height: 2)
                .padding(.top, 1)
        }
        .frame(width: 34, height: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
        .overlay(
            ScrollWheelModifier { steps in
                step(by: steps)
                onFocus()
            }
        )
    }

    private func step(by delta: Int) {
        var newVal = value + delta
        if newVal > range.upperBound {
            newVal = range.lowerBound
        } else if newVal < range.lowerBound {
            newVal = range.upperBound
        }
        value = newVal
    }
}

// MARK: - AppKit Scroll & Drag Catcher (120 FPS Trackpad & Mouse Wheel Support)

final class ScrollWheelCatcherView: NSView {

    var onScroll: ((Int) -> Void)?
    private var accumulatedDelta: CGFloat = 0.0
    private var lastDragY: CGFloat = 0.0
    private var isDragging: Bool = false

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 6.0
        accumulatedDelta += delta

        let threshold: CGFloat = 7.0
        if abs(accumulatedDelta) >= threshold {
            let steps = Int(accumulatedDelta / threshold)
            accumulatedDelta -= CGFloat(steps) * threshold
            onScroll?(steps)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func mouseDown(with event: NSEvent) {
        lastDragY = event.locationInWindow.y
        isDragging = false
        super.mouseDown(with: event)
        nextResponder?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = event.locationInWindow.y
        let diff = currentY - lastDragY
        let threshold: CGFloat = 8.0

        if abs(diff) >= threshold {
            isDragging = true
            let steps = Int(diff / threshold)
            lastDragY += CGFloat(steps) * threshold
            onScroll?(steps)
        }

        super.mouseDragged(with: event)
        nextResponder?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            super.mouseUp(with: event)
            nextResponder?.mouseUp(with: event)
        }
        isDragging = false
    }
}

struct ScrollWheelModifier: NSViewRepresentable {

    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> ScrollWheelCatcherView {
        let view = ScrollWheelCatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCatcherView, context: Context) {
        nsView.onScroll = onScroll
    }
}
