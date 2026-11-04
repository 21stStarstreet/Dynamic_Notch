// NowPlayingView.swift
// DynamicNotch / Features / NowPlaying
//
// Primary media player LiveActivity view inside the expanded notch.
//
// Landscape 3:2 Ratio Layout Architecture
// ────────────────────────────────────────
// • 2-Column Balanced Design:
//   - Column 1 (Left): 68×68 Album Artwork with ambient bloom glow.
//   - Column 2 (Right):
//       - Row 1: Track Title, Artist, source tag, and live 4-bar Audio Visualizer.
//       - Row 2: Full-width lengthened interactive scrubber with timestamps.
//       - Row 3: Centered primary transport controls (Play/Pause CTA) and utility wings.
// • Collapsible Drawers: Synchronized Lyrics and Audio Route Switcher.

import SwiftUI

struct NowPlayingView: View {

    let info: NowPlayingInfo
    let observer: MediaObserver

    @ObservedObject private var viewModel = NowPlayingViewModel.shared
    @State private var isDraggingScrubber = false
    @State private var scrubbedTime: TimeInterval = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main Landscape Card Body (2-Column Architecture)
            HStack(alignment: .center, spacing: 14) {

                // Column 1 (Left): 68×68 Album Artwork with Ambient Glow
                ZStack {
                    if let art = info.artwork {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .blur(radius: 10)
                            .opacity(info.isPlaying ? 0.32 : 0.12)
                            .scaleEffect(info.isPlaying ? 1.04 : 0.96)
                    }

                    AlbumArtView(
                        image: info.artwork,
                        isPlaying: info.isPlaying,
                        size: 68,
                        cornerRadius: 15
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
                .onTapGesture {
                    openMusicApp()
                }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }

                // Column 2 (Right): Track Details, Scrubber & Controls
                VStack(alignment: .leading, spacing: 5) {

                    // Row 1: Title, Artist, & Live Visualizer
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(info.title)
                                    .font(.system(size: 14, weight: .bold))
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

                            HStack(spacing: 4) {
                                Text(info.artist.isEmpty ? "Bilinmeyen Sanatçı" : info.artist)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.68))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                if !info.album.isEmpty {
                                    Text("•")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.30))

                                    Text(info.album)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(.white.opacity(0.40))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openMusicApp()
                        }
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                        }
                    }

                    // Row 2: Lengthened Full-Width Scrubber
                    InteractiveScrubberView(
                        currentTime: isDraggingScrubber ? scrubbedTime : viewModel.liveElapsedTime,
                        duration: info.duration,
                        tint: viewModel.accentColor,
                        onScrubStart: {
                            isDraggingScrubber = true
                            scrubbedTime = viewModel.liveElapsedTime
                            NotchViewModel.shared?.beginControlInteraction()
                        },
                        onScrubChanged: { newTime in
                            scrubbedTime = newTime
                        },
                        onScrubEnd: { finalTime in
                            isDraggingScrubber = false
                            viewModel.liveElapsedTime = finalTime
                            observer.seek(to: finalTime)
                            NotchViewModel.shared?.endControlInteraction()
                        }
                    )

                    // Row 3: Elevated Transport Controls & Action Buttons
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Drawers (Lyrics / Audio Route)
            if viewModel.isLyricsExpanded {
                VStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.75)
                        .padding(.horizontal, 2)
                        .padding(.top, 4)

                    SynchronizedLyricsView(viewModel: viewModel, observer: observer)
                }
                .transition(.opacity)
            } else if viewModel.isAudioRouteExpanded {
                VStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.75)
                        .padding(.horizontal, 2)
                        .padding(.top, 4)

                    AudioRoutePickerView(accentColor: viewModel.accentColor)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
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

// MARK: - Apple-Grade Interactive Scrubber Component

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

    private var remainingTime: TimeInterval {
        max(0, effectiveDuration - currentTime)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left: Elapsed Time (Monospaced with dynamic brightness)
            Text(currentTime.formattedMinutesSeconds)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(isDragging ? 0.95 : (isHovering ? 0.82 : 0.50)))
                .frame(minWidth: 28, alignment: .leading)
                .animation(.easeOut(duration: 0.16), value: isDragging || isHovering)

            // Center: Apple Signature Interactive Scrubber Track
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let height = geo.size.height
                let barHeight: CGFloat = isDragging ? 6.5 : (isHovering ? 5.5 : 4.0)
                let thumbWidth: CGFloat = 19.0
                let thumbHeight: CGFloat = 13.0
                let cornerRadius: CGFloat = 6.0
                let filledWidth = CGFloat(progressFraction) * width
                let thumbOffset = max(0, min(width - thumbWidth, filledWidth - (thumbWidth / 2.0)))
                let thumbCenter = thumbOffset + (thumbWidth / 2.0)
                let barProgressWidth = progressFraction <= 0 ? 0 : (progressFraction >= 0.999 ? width : max(barHeight, thumbCenter))
                let thumbCoverage = min(max((filledWidth - thumbOffset) / thumbWidth, 0.0), 1.0)

                ZStack(alignment: .leading) {
                    // 1. Frosted Glass Background Trough
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.18), location: 0.0),
                                            .init(color: Color.white.opacity(0.04), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .frame(height: barHeight)

                    // 2. Liquid Progress Fill (Clean optical gradient, dead-centered at the thumb)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.85),
                                    tint
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.40), location: 0.0),
                                            .init(color: Color.white.opacity(0.08), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .frame(width: barProgressWidth, height: barHeight)

                    // 3. macOS Apple Liquid Glass Handle with True Optical Refraction
                    LiquidGlassScrubberThumb(
                        width: thumbWidth,
                        height: thumbHeight,
                        cornerRadius: cornerRadius,
                        barHeight: barHeight,
                        thumbCoverage: thumbCoverage,
                        isHovering: isHovering,
                        isDragging: isDragging,
                        tint: tint
                    )
                    .offset(x: thumbOffset)
                }
                .frame(height: height, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard effectiveDuration > 0 else { return }
                            if !isDragging {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    isDragging = true
                                }
                                NotchViewModel.shared?.beginControlInteraction()
                                onScrubStart()
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            }
                            let fraction = min(max(value.location.x / width, 0.0), 1.0)
                            let newTime = fraction * effectiveDuration
                            onScrubChanged(newTime)
                        }
                        .onEnded { value in
                            guard effectiveDuration > 0 else { return }
                            let fraction = min(max(value.location.x / width, 0.0), 1.0)
                            let finalTime = fraction * effectiveDuration
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isDragging = false
                            }
                            onScrubEnd(finalTime)
                            NotchViewModel.shared?.endControlInteraction()
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        }
                )
            }
            .frame(height: 18)
            .onHover { hovering in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                    isHovering = hovering
                }
                NotchViewModel.shared?.isHoveringSlider = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }

            // Right: Remaining Time (Monospaced with dynamic brightness)
            Group {
                if effectiveDuration > 0 {
                    Text("-\(remainingTime.formattedMinutesSeconds)")
                } else {
                    Text("--:--")
                }
            }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(isDragging ? 0.95 : (isHovering ? 0.82 : 0.50)))
            .frame(minWidth: 32, alignment: .trailing)
            .animation(.easeOut(duration: 0.16), value: isDragging || isHovering)
        }
    }
}

// MARK: - macOS Apple-Standard Frosted Glass Scrubber Handle with Optical Refraction

struct LiquidGlassScrubberThumb: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 6.0
    var barHeight: CGFloat = 4.0
    var thumbCoverage: CGFloat = 0.5
    let isHovering: Bool
    let isDragging: Bool
    let tint: Color

    var body: some View {
        let clampedCoverage = min(max(thumbCoverage, 0.0), 1.0)
        let entryWeight = min(max(clampedCoverage * 1.6, 0.0), 1.0)

        ZStack {
            // Layer 1: Directional Contact Shadow (Physical grounding to track, black shadow, NO neon glow)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(isDragging ? 0.42 : (isHovering ? 0.32 : 0.24)))
                .frame(width: width, height: height)
                .offset(y: isDragging ? 1.8 : 1.0)
                .blur(radius: isDragging ? 2.5 : 1.4)

            // Layer 2: Optical Glass Chamber (See-through Fresnel glass with internal bar refraction & color reflection)
            ZStack {
                // 2a. Sub-surface Backdrop (Matches dark notch interior so raw un-refracted track seam is hidden, while preserving dark glass depth at top/bottom)
                Color.black.opacity(0.92)

                // 2b. Ambient Color Dispersion in Glass Volume (Refracts incoming bar tint vertically into the curved lens)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                tint.opacity(0.55 * entryWeight),
                                tint.opacity(0.24 * entryWeight),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.24, y: 0.50),
                            startRadius: 0,
                            endRadius: width * 0.70
                        )
                    )
                    .frame(width: width * 1.05, height: height * 0.92)
                    .blur(radius: 2.4)

                // 2c. Refracted & Magnified Track Core (Barrel-magnified & blurred track passing through the glass without a sharp midpoint cut)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0.96 * entryWeight), location: 0.0),
                                .init(color: tint.opacity(0.78 * entryWeight), location: 0.28),
                                .init(color: tint.opacity(0.38 * entryWeight), location: 0.56),
                                .init(color: Color.white.opacity(0.24), location: 0.82),
                                .init(color: Color.white.opacity(0.18), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.08, height: barHeight * 1.55)
                    .blur(radius: 1.8)

                // 2d. Fresnel Translucent Glass Matrix (Clearer in the middle, frosted at top/bottom curved surfaces)
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.46), location: 0.0),
                        .init(color: Color.white.opacity(0.20), location: 0.36),
                        .init(color: Color.white.opacity(0.18), location: 0.64),
                        .init(color: Color.white.opacity(0.34), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 2e. Chromatic Inner Bevel Reflection (Curved glass walls catch and reflect the surrounding track tint)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0.65 * entryWeight), location: 0.0),
                                .init(color: Color.white.opacity(0.48), location: 0.45),
                                .init(color: Color.white.opacity(0.22), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.6
                    )
                    .blur(radius: 0.8)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // Layer 3: Precision Outer Glass Rim (Crisp Fresnel edge with subtle tint reflection)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.88), location: 0.0),
                            .init(color: Color.white.opacity(0.45), location: 0.50),
                            .init(color: Color.white.opacity(0.24), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
                .frame(width: width, height: height)
        }
        .scaleEffect(isDragging ? 1.22 : (isHovering ? 1.08 : 0.92))
        .opacity(1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isDragging)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isHovering)
    }
}
