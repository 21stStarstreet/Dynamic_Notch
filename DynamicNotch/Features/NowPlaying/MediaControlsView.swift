// MediaControlsView.swift
// DynamicNotch / Features / NowPlaying
//
// Playback transport buttons (Previous, Play/Pause, Next) with hover feedback
// and guaranteed non-compressible layout priority.

import SwiftUI

struct MediaControlsView: View {

    let isPlaying: Bool
    let onPrevious: () -> Void
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void
    var onToggleFavorite: (() -> Void)? = nil
    var isFavorited: Bool = false
    var favoriteTint: Color = Color(red: 0.114, green: 0.843, blue: 0.376)
    var onToggleLyrics: (() -> Void)? = nil
    var isLyricsActive: Bool = false
    var onToggleAudioRoute: (() -> Void)? = nil
    var isAudioRouteActive: Bool = false
    var lyricsTint: Color = .white

    @State private var hoveredButton: Int? = nil

    var body: some View {
        HStack(spacing: 7) {
            transportButton(
                id: 0,
                systemName: "backward.fill",
                iconSize: 13,
                frameSize: 26,
                action: onPrevious
            )

            transportButton(
                id: 1,
                systemName: isPlaying ? "pause.fill" : "play.fill",
                iconSize: 16,
                frameSize: 30,
                action: onTogglePlayPause
            )

            transportButton(
                id: 2,
                systemName: "forward.fill",
                iconSize: 13,
                frameSize: 26,
                action: onNext
            )

            if let onToggleFavorite {
                favoriteButton(action: onToggleFavorite)
            }

            if let onToggleLyrics {
                lyricsButton(action: onToggleLyrics)
            }

            if let onToggleAudioRoute {
                audioRouteButton(action: onToggleAudioRoute)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func favoriteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 12.0, weight: .semibold))
                .foregroundColor(isFavorited ? favoriteTint : .white.opacity(hoveredButton == 5 ? 1.0 : 0.70))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isFavorited ? favoriteTint.opacity(0.22) : Color.white.opacity(hoveredButton == 5 ? 0.16 : 0.06))
                )
                .scaleEffect(hoveredButton == 5 ? (isFavorited ? 1.14 : 1.08) : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isFavorited)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 5 : nil
        }
        .help(isFavorited ? "Favorilerden Çıkar" : "Favorilere Ekle")
    }

    private func audioRouteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 12.0, weight: .semibold))
                .foregroundColor(isAudioRouteActive ? lyricsTint : .white.opacity(hoveredButton == 4 ? 1.0 : 0.70))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isAudioRouteActive ? lyricsTint.opacity(0.22) : Color.white.opacity(hoveredButton == 4 ? 0.16 : 0.06))
                )
                .scaleEffect(hoveredButton == 4 ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 4 : nil
        }
    }

    private func lyricsButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isLyricsActive ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(isLyricsActive ? lyricsTint : .white.opacity(hoveredButton == 3 ? 1.0 : 0.70))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isLyricsActive ? lyricsTint.opacity(0.22) : Color.white.opacity(hoveredButton == 3 ? 0.16 : 0.06))
                )
                .scaleEffect(hoveredButton == 3 ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 3 : nil
        }
    }

    private func transportButton(
        id: Int,
        systemName: String,
        iconSize: CGFloat,
        frameSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white.opacity(hoveredButton == id ? 1.0 : 0.88))
                .frame(width: frameSize, height: frameSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(hoveredButton == id ? 0.16 : 0.06))
                )
                .scaleEffect(hoveredButton == id ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? id : nil
        }
    }
}
