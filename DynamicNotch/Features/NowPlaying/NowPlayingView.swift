// NowPlayingView.swift
// DynamicNotch / Features / NowPlaying
//
// Primary media player LiveActivity view inside the expanded notch.
//
// Layout guarantees
// ─────────────────
// • Left column (`AlbumArtView`): fixed 48×48 pt square, strictly center-cropped.
// • Top row of right column: Track title, artist, audio visualizer, and elevated transport buttons.
// • Bottom row of right column: Full-width lengthened interactive scrubber bar with real-time seeking.

import SwiftUI

struct NowPlayingView: View {

    let info: NowPlayingInfo
    let observer: MediaObserver

    @ObservedObject private var viewModel = NowPlayingViewModel.shared
    @State private var isDraggingScrubber = false
    @State private var scrubbedTime: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {

                // Left: Strictly bounded 48×48 Album Artwork (concentric with outer radius)
                AlbumArtView(
                    image: info.artwork,
                    isPlaying: info.isPlaying,
                    size: 48,
                    cornerRadius: 11
                )
                .contentShape(RoundedRectangle(cornerRadius: 11))
                .onTapGesture {
                    openMusicApp()
                }
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }

                // Right: Multi-row stack with elevated controls and lengthened scrubber
                VStack(alignment: .leading, spacing: 5) {

                    // Top Row: Title, Artist & Elevated Transport Controls
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(info.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                AudioVisualizerView(
                                    isPlaying: info.isPlaying,
                                    tint: viewModel.accentColor,
                                    trackInfo: info,
                                    isCompact: false
                                )
                            }

                            Text(info.artist.isEmpty ? "Bilinmeyen Sanatçı" : info.artist)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.60))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openMusicApp()
                        }
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }

                        // Right: Transport Controls elevated to the top row
                        MediaControlsView(
                            isPlaying: info.isPlaying,
                            onPrevious: { observer.previousTrack() },
                            onTogglePlayPause: { observer.togglePlayPause() },
                            onNext: { observer.nextTrack() },
                            onToggleFavorite: { observer.toggleFavorite(for: info) },
                            isFavorited: viewModel.isFavorited,
                            favoriteTint: favoriteTint,
                            onToggleLyrics: { viewModel.toggleLyrics() },
                            isLyricsActive: viewModel.isLyricsExpanded,
                            onToggleAudioRoute: { viewModel.toggleAudioRoute() },
                            isAudioRouteActive: viewModel.isAudioRouteExpanded,
                            lyricsTint: viewModel.accentColor
                        )
                        .layoutPriority(2)
                    }

                    // Bottom Row: Lengthened Full-Width Interactive Scrubber Bar
                    InteractiveScrubberView(
                        currentTime: isDraggingScrubber ? scrubbedTime : viewModel.liveElapsedTime,
                        duration: info.duration,
                        tint: viewModel.accentColor,
                        onScrubStart: {
                            isDraggingScrubber = true
                            scrubbedTime = viewModel.liveElapsedTime
                        },
                        onScrubChanged: { newTime in
                            scrubbedTime = newTime
                        },
                        onScrubEnd: { finalTime in
                            isDraggingScrubber = false
                            viewModel.liveElapsedTime = finalTime
                            observer.seek(to: finalTime)
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openMusicApp()
            }

            // Synchronized Lyrics Drawer
            if viewModel.isLyricsExpanded {
                VStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.75)
                        .padding(.horizontal, 2)

                    SynchronizedLyricsView(viewModel: viewModel, observer: observer)
                }
                .transition(.opacity)
            } else if viewModel.isAudioRouteExpanded {
                // Audio Route Picker Drawer
                VStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.75)
                        .padding(.horizontal, 2)

                    AudioRoutePickerView(accentColor: viewModel.accentColor)
                }
                .transition(.opacity)
            }
        }
        .background(
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    openMusicApp()
                }
        )
        .onAppear {
            viewModel.sync(with: info)
        }
        .onChange(of: info) { _, newInfo in
            viewModel.sync(with: newInfo)
        }
    }

    private func openMusicApp() {
        observer.openActiveMediaApp(for: info)
    }

    private var favoriteTint: Color {
        let app = info.appName.lowercased()
        if app.contains("spotify") {
            return Color(red: 0.114, green: 0.843, blue: 0.376)
        } else if app.contains("music") {
            return Color(red: 0.98, green: 0.22, blue: 0.38)
        } else {
            return viewModel.accentColor
        }
    }
}

// MARK: - Interactive Scrubber Component

struct InteractiveScrubberView: View {

    let currentTime: TimeInterval
    let duration: TimeInterval
    var tint: Color = .white
    let onScrubStart: () -> Void
    let onScrubChanged: (TimeInterval) -> Void
    let onScrubEnd: (TimeInterval) -> Void

    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false

    private var effectiveDuration: TimeInterval {
        max(duration, 0)
    }

    private var progressFraction: Double {
        guard effectiveDuration > 0 else { return 0 }
        return min(max(currentTime / effectiveDuration, 0.0), 1.0)
    }

    var body: some View {
        HStack(spacing: 7) {

            // Left: Elapsed Time
            Text(currentTime.formattedMinutesSeconds)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .frame(minWidth: 32, alignment: .leading)

            // Center: Lengthened Scrub Bar (Full remaining width)
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let barHeight: CGFloat = (isHovering || isDragging) ? 5.5 : 3.5
                let knobSize: CGFloat = 10.0
                let filledWidth = CGFloat(progressFraction) * width

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: barHeight)

                    // Progress fill
                    Capsule()
                        .fill(tint)
                        .frame(width: max(barHeight, filledWidth), height: barHeight)

                    // Scrubber knob (reveals smoothly on hover or drag)
                    if isHovering || isDragging {
                        Circle()
                            .fill(Color.white)
                            .frame(width: knobSize, height: knobSize)
                            .shadow(color: .black.opacity(0.40), radius: 3, x: 0, y: 1)
                            .offset(x: max(0, min(width - knobSize, filledWidth - knobSize / 2.0)))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: height, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard effectiveDuration > 0 else { return }
                            if !isDragging {
                                isDragging = true
                                onScrubStart()
                            }
                            let fraction = min(max(value.location.x / width, 0.0), 1.0)
                            let newTime = fraction * effectiveDuration
                            onScrubChanged(newTime)
                        }
                        .onEnded { value in
                            guard effectiveDuration > 0 else { return }
                            let fraction = min(max(value.location.x / width, 0.0), 1.0)
                            let finalTime = fraction * effectiveDuration
                            isDragging = false
                            onScrubEnd(finalTime)
                        }
                )
            }
            .frame(height: 14)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHovering = hovering
                }
            }

            // Right: Duration or Remaining Time
            if effectiveDuration > 0 {
                Text(effectiveDuration.formattedMinutesSeconds)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(minWidth: 32, alignment: .trailing)
            } else {
                Text("--:--")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
    }
}
