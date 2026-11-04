// MediaControlsView.swift
// DynamicNotch / Features / NowPlaying
//
// Playback transport buttons (Previous, prominent Play/Pause, Next) with Apple-grade
// hover feedback, strictly centered geometry, and secondary action wings (Favorite, AirPlay, Lyrics).

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
        HStack(alignment: .center) {
            // Left wing: Favorite button
            if let onToggleFavorite {
                favoriteButton(action: onToggleFavorite)
            }

            Spacer()

            // Center: strictly centered playback transport
            HStack(spacing: 12) {
                transportButton(
                    id: 0,
                    systemName: "backward.fill",
                    iconSize: 13,
                    frameSize: 28,
                    action: onPrevious
                )

                mainPlayPauseButton(action: onTogglePlayPause)

                transportButton(
                    id: 2,
                    systemName: "forward.fill",
                    iconSize: 13,
                    frameSize: 28,
                    action: onNext
                )
            }

            Spacer()

            // Right wing: Lyrics & AirPlay Audio Route
            HStack(spacing: 6) {
                if let onToggleLyrics {
                    lyricsButton(action: onToggleLyrics)
                }

                if let onToggleAudioRoute {
                    audioRouteButton(action: onToggleAudioRoute)
                }
            }
        }
        .frame(height: 36)
    }

    private func mainPlayPauseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.white.opacity(hoveredButton == 1 ? 0.30 : 0.12), radius: 6, x: 0, y: 1)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(.black)
                    .offset(x: isPlaying ? 0 : 1.2)
            }
            .scaleEffect(hoveredButton == 1 ? 1.08 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.65), value: hoveredButton)
            .animation(.spring(response: 0.28, dampingFraction: 0.70), value: isPlaying)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 1 : nil
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(isPlaying ? "Duraklat" : "Oynat")
    }

    private func favoriteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 12.0, weight: .semibold))
                .foregroundColor(isFavorited ? favoriteTint : .white.opacity(hoveredButton == 5 ? 1.0 : 0.70))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isFavorited ? favoriteTint.opacity(0.24) : Color.white.opacity(hoveredButton == 5 ? 0.16 : 0.08))
                )
                .scaleEffect(hoveredButton == 5 ? (isFavorited ? 1.12 : 1.08) : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isFavorited)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 5 : nil
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
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
                        .fill(isAudioRouteActive ? lyricsTint.opacity(0.24) : Color.white.opacity(hoveredButton == 4 ? 0.16 : 0.08))
                )
                .scaleEffect(hoveredButton == 4 ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 4 : nil
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help("Ses Çıkış Cihazları")
    }

    private func lyricsButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isLyricsActive ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(isLyricsActive ? lyricsTint : .white.opacity(hoveredButton == 3 ? 1.0 : 0.70))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isLyricsActive ? lyricsTint.opacity(0.24) : Color.white.opacity(hoveredButton == 3 ? 0.16 : 0.08))
                )
                .scaleEffect(hoveredButton == 3 ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.14), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? 3 : nil
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help("Şarkı Sözleri")
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
                .foregroundColor(.white.opacity(hoveredButton == id ? 1.0 : 0.85))
                .frame(width: frameSize, height: frameSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(hoveredButton == id ? 0.18 : 0.08))
                )
                .scaleEffect(hoveredButton == id ? 1.10 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.65), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredButton = isHovering ? id : nil
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(id == 0 ? "Önceki Parça" : "Sonraki Parça")
    }
}
