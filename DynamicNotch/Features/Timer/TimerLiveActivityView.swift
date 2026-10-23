// TimerLiveActivityView.swift
// DynamicNotch / Features / Timer
//
// Pixel-perfect replica of the Apple Dynamic Notch Timer interface.
// Matches the user-provided reference design:
// - Left: Custom dark-amber Play/Pause button (#4C2A11) + dark slate Close button (#2E2E2F)
// - Right: "Timer" label in amber (#F8902F) alongside large bold countdown digits (#F8902F)
// - Balanced sizing: 36x36 pt buttons with ample breathing room from the outer edges.

import SwiftUI

struct TimerLiveActivityView: View {

    let item: TimerItem
    @ObservedObject var observer: TimerObserver
    var onCancel: (() -> Void)? = nil

    @State private var isHoveringPause: Bool = false
    @State private var isHoveringCancel: Bool = false

    // Exact color sampled from reference screenshot: #F8902F
    private let timerOrange = Color(red: 0.975, green: 0.565, blue: 0.187)
    // Pause button circular background: #4C2A11
    private let pauseBg     = Color(red: 0.30, green: 0.17, blue: 0.07)
    // Cancel button circular background: #2E2E2F
    private let cancelBg    = Color(red: 0.18, green: 0.18, blue: 0.19)

    var body: some View {
        let currentItem = observer.activeTimer ?? item

        HStack(alignment: .center, spacing: 0) {

            // MARK: - Left Controls (Pause & Cancel) - Enlarged 42x42pt Tactile Circles

            HStack(spacing: 9) {
                // 1. Play / Pause Button (44x44 pt)
                Button {
                    handlePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(pauseBg)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .fill(isHoveringPause ? Color.white.opacity(0.12) : Color.clear)
                            )

                        Image(systemName: currentItem.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 17.5, weight: .bold))
                            .foregroundColor(timerOrange)
                            .offset(x: currentItem.isPaused ? 1.5 : 0)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .onHover { isHoveringPause = $0 }

                // 2. Cancel Button (X) (44x44 pt)
                Button {
                    handleCancel()
                } label: {
                    ZStack {
                        Circle()
                            .fill(cancelBg)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .fill(isHoveringCancel ? Color.white.opacity(0.12) : Color.clear)
                            )

                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(white: 0.85))
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .onHover { isHoveringCancel = $0 }
            }
            .offset(y: 2.0)

            Spacer(minLength: 16)

            // MARK: - Right Controls ("Timer" Label & Digits)

            HStack(alignment: .center, spacing: 8) {
                Text(currentItem.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(timerOrange)

                TimelineView(.animation(minimumInterval: 0.25, paused: currentItem.isPaused)) { context in
                    let rem: TimeInterval = currentItem.isPaused
                        ? (currentItem.remainingWhenPaused ?? currentItem.remaining)
                        : max(0, currentItem.endDate.timeIntervalSince(context.date))
                    let hours = Int(rem) / 3600
                    let minutes = (Int(rem) % 3600) / 60
                    let seconds = Int(rem) % 60
                    let formatted = hours > 0
                        ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                        : String(format: "%02d:%02d", minutes, seconds)

                    Text(formatted)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundColor(timerOrange)
                        .opacity(currentItem.isPaused ? 0.65 : 1.0)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .offset(y: 2.0)
        }
        .frame(height: 44)
    }

    private func handlePlayPause() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        observer.togglePlayPause()
    }

    private func handleCancel() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        observer.cancel()
        onCancel?()
    }
}
