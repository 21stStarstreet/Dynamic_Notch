// SynchronizedLyricsView.swift
// DynamicNotch / Features / NowPlaying
//
// Apple-grade real-time synchronized lyrics drawer inside the expanded notch.
// Features tap-to-seek, smooth kinetic centering, edge-vignette fade masks,
// and rhythmic instrumental breaks.

import SwiftUI

struct SynchronizedLyricsView: View {

    @ObservedObject var viewModel: NowPlayingViewModel
    let observer: MediaObserver

    @State private var hoveredLineId: UUID? = nil
    @State private var autoScrollEnabled: Bool = true
    @State private var manualScrollDebounce: Task<Void, Never>? = nil

    private var accentColor: Color {
        viewModel.accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingLyrics {
                loadingView
            } else if let lyrics = viewModel.currentLyrics, lyrics.hasLyrics {
                if lyrics.isSynced && !lyrics.lines.isEmpty {
                    syncedLyricsList(lyrics: lyrics)
                } else if let plain = lyrics.plainLyrics, !plain.isEmpty {
                    plainLyricsView(text: plain)
                } else {
                    noLyricsView
                }
            } else {
                noLyricsView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .clipped()
    }

    // MARK: - Synchronized Lyrics Stream

    private func syncedLyricsList(lyrics: TrackLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Top breathing space
                    Color.clear.frame(height: 16)

                    // Instrumental prelude if elapsed time < first line
                    if let firstLine = lyrics.lines.first, viewModel.liveElapsedTime < firstLine.timestamp - 1.5 {
                        preludeInstrumentalView
                            .id("prelude_dots")
                    }

                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = (index == viewModel.activeLyricIndex)
                        let isHovered = (hoveredLineId == line.id)

                        lyricLineRow(line: line, isActive: isActive, isHovered: isHovered)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                seekToLine(line, index: index, proxy: proxy)
                            }
                            .onHover { hovering in
                                hoveredLineId = hovering ? line.id : nil
                            }
                    }

                    // Bottom breathing space
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 4)
            }
            // Apple Music signature top and bottom gradient fade
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: viewModel.activeLyricIndex) { _, newIndex in
                guard autoScrollEnabled, let newIndex else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                if let active = viewModel.activeLyricIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(active, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Lyric Line Row

    private func lyricLineRow(line: LyricLine, isActive: Bool, isHovered: Bool) -> some View {
        HStack(spacing: 8) {
            if line.isInstrumental {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                    Text("•••")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(isActive ? accentColor : .white.opacity(0.35))
            } else {
                Text(line.text)
                    .font(.system(size: isActive ? 13.5 : 12.0, weight: isActive ? .bold : .medium))
                    .foregroundColor(
                        isActive
                            ? Color.white
                            : (isHovered ? Color.white.opacity(0.75) : Color.white.opacity(0.35))
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(
                        color: isActive ? accentColor.opacity(0.60) : .clear,
                        radius: 8,
                        x: 0,
                        y: 0
                    )
                    .scaleEffect(isActive ? 1.02 : 1.0, anchor: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    // MARK: - Tap to Seek Handler

    private func seekToLine(_ line: LyricLine, index: Int, proxy: ScrollViewProxy) {
        // Suspend auto-scroll briefly during manual interaction
        autoScrollEnabled = false
        manualScrollDebounce?.cancel()

        viewModel.liveElapsedTime = line.timestamp
        viewModel.activeLyricIndex = index
        observer.seek(to: line.timestamp)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            proxy.scrollTo(index, anchor: .center)
        }

        manualScrollDebounce = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            autoScrollEnabled = true
        }
    }

    // MARK: - Prelude / Instrumental Dots

    private var preludeInstrumentalView: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accentColor.opacity(0.80))

            Text("Giriş")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.55))

            PulsingDotsView(tint: accentColor)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Plain Lyrics Fallback

    private func plainLyricsView(text: String) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .lineSpacing(4)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Apple-grade subtle indicator badge
            HStack(spacing: 3.5) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 8, weight: .semibold))
                Text(Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Metin Sözler" : "Plain Lyrics")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.40))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .padding(.trailing, 6)
            .padding(.top, 2)
            .help(Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true ? "Bu parça için zaman damgalı (senkronize) söz bulunamadı" : "Synchronized lyrics not available for this track")
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
                .tint(accentColor)

            Text("Şarkı sözleri yükleniyor...")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Empty / Not Found State

    private var noLyricsView: some View {
        VStack(spacing: 6) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.white.opacity(0.28))

            Text("Bu parça için senkronize söz bulunamadı")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Subtle Pulsing Dots Animation Component

struct PulsingDotsView: View {
    let tint: Color
    @State private var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(tint)
                    .frame(width: 4, height: 4)
                    .opacity(isPulsing ? 0.90 : 0.25)
                    .scaleEffect(isPulsing ? 1.15 : 0.85)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: isPulsing
                    )
            }
        }
        .onAppear {
            isPulsing = true
        }
    }
}
