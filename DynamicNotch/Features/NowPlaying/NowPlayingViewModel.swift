// NowPlayingViewModel.swift
// DynamicNotch / Features / NowPlaying
//
// Manages local interpolated playback time, synchronized lyrics engine,
// and artwork accent color extraction for NowPlayingView.

import SwiftUI
import Combine

extension Notification.Name {
    static let notchLyricsToggleRequested = Notification.Name("notchLyricsToggleRequested")
    static let notchAudioRouteToggleRequested = Notification.Name("notchAudioRouteToggleRequested")
}

@MainActor
final class NowPlayingViewModel: ObservableObject {

    static let shared = NowPlayingViewModel()

    @Published var liveElapsedTime: TimeInterval = 0 {
        didSet {
            updateActiveLyricIndex(for: liveElapsedTime)
        }
    }
    @Published var accentColor: Color = .white
    @Published var isFavorited: Bool = false
    @Published var currentTrack: NowPlayingInfo? = nil

    // MARK: - Synchronized Lyrics & Audio Route State

    @Published var currentLyrics: TrackLyrics? = nil
    @Published var isLoadingLyrics: Bool = false
    @Published var lyricsLoadFailed: Bool = false
    @Published var isLyricsExpanded: Bool = false
    @Published var isAudioRouteExpanded: Bool = false
    @Published var activeLyricIndex: Int? = nil

    private var tickTimer: AnyCancellable?
    private var lyricsFetchTask: Task<Void, Never>?

    private var lastSyncedTitle: String = ""
    private var lastSyncedArtist: String = ""
    private var lastIsPlaying: Bool = false
    private var currentDuration: TimeInterval = 0

    func sync(with info: NowPlayingInfo) {
        currentTrack = info
        currentDuration = info.duration
        let isNewTrack = (info.title != lastSyncedTitle || info.artist != lastSyncedArtist)

        if isNewTrack {
            lastSyncedTitle = info.title
            lastSyncedArtist = info.artist
            liveElapsedTime = info.currentLiveElapsed
            isFavorited = MediaFavoritesManager.shared.isFavorited(track: info) || info.isFavorited
            fetchLyrics(for: info)

            if info.appName.lowercased().contains("spotify") || SpotifyAPIService.shared.isSpotifyRunning {
                Task {
                    await SpotifyAPIService.shared.checkIfLiked(track: info)
                }
            }
        } else {
            // Keep local favorites and playback info consistently in sync
            let localFav = MediaFavoritesManager.shared.isFavorited(track: info)
            if localFav {
                if !isFavorited {
                    isFavorited = true
                }
            } else if info.isFavorited != isFavorited {
                isFavorited = info.isFavorited
            }
        }
        if info.isPlaying {
            // MediaRemote / system provides timestamp-corrected live elapsed.
            let serverElapsed = info.currentLiveElapsed
            let divergence = abs(serverElapsed - liveElapsedTime)

            // Detect seek forward/backward (> 2.0s divergence) or loop-back to start (was > 5s, now < 3s)
            let isLoopedBack = (liveElapsedTime > 5.0 && serverElapsed < 3.0)
            if divergence > 2.0 || isLoopedBack {
                liveElapsedTime = serverElapsed
            }
        } else {
            // Paused: snap to the exact reported position.
            liveElapsedTime = info.elapsedTime
        }

        accentColor = info.accentColor

        // Only restart the tick timer when play/pause state actually changes,
        // on a new track, or if the timer died. Recreating every second would interrupt
        // the 1-second counter and cause subtle drift / reset issues.
        let playStateChanged = (info.isPlaying != lastIsPlaying)
        lastIsPlaying = info.isPlaying

        if isNewTrack || playStateChanged || (info.isPlaying && tickTimer == nil) {
            tickTimer?.cancel()
            tickTimer = nil

            if info.isPlaying {
                tickTimer = Timer.publish(every: 1.0, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        let duration = self.currentDuration
                        if duration > 0 {
                            if self.liveElapsedTime < duration {
                                self.liveElapsedTime += 1.0
                            }
                        } else {
                            self.liveElapsedTime += 1.0
                        }
                    }
            }
        }
    }

    // MARK: - Lyrics & Audio Route Management

    func toggleLyrics() {
        NotificationCenter.default.post(
            name: .notchLyricsToggleRequested,
            object: nil
        )
    }

    func toggleAudioRoute() {
        NotificationCenter.default.post(
            name: .notchAudioRouteToggleRequested,
            object: nil
        )
    }

    private func fetchLyrics(for info: NowPlayingInfo) {
        lyricsFetchTask?.cancel()
        currentLyrics = nil
        activeLyricIndex = nil
        lyricsLoadFailed = false
        isLoadingLyrics = true

        let title = info.title
        let artist = info.artist
        let album = info.album
        let duration = info.duration

        lyricsFetchTask = Task { [weak self] in
            let lyrics = await LyricsService.shared.fetchLyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            guard let self, !Task.isCancelled else { return }
            self.isLoadingLyrics = false
            if let lyrics, lyrics.hasLyrics {
                self.currentLyrics = lyrics
                self.lyricsLoadFailed = false
                self.updateActiveLyricIndex(for: self.liveElapsedTime)
            } else {
                self.currentLyrics = nil
                self.lyricsLoadFailed = true
            }
        }
    }

    func updateActiveLyricIndex(for time: TimeInterval) {
        guard let lyrics = currentLyrics, lyrics.isSynced, !lyrics.lines.isEmpty else {
            if activeLyricIndex != nil {
                activeLyricIndex = nil
            }
            return
        }

        // Find the latest lyric line whose timestamp <= current time (+0.15s anticipation window)
        let idx = lyrics.lines.lastIndex(where: { $0.timestamp <= (time + 0.15) })
        if activeLyricIndex != idx {
            activeLyricIndex = idx
        }
    }

    deinit {
        tickTimer?.cancel()
        lyricsFetchTask?.cancel()
    }
}
