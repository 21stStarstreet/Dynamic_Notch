// MediaObserver.swift
// DynamicNotch / Observers
//
// Universal Multi-Engine Now Playing Observer engineered for macOS 14 Sonoma,
// macOS 15 Sequoia, and macOS 26 Tahoe.
//
// Architecture & Detection Hierarchy
// ────────────────────────────────────
// 1. Primary Engine: `MediaRemote.framework`
//    Apple's system-wide Now Playing backbone. Natively captures every media player
//    on macOS: QuickTime Player, Safari, Google Chrome, Arc, Spotify, Apple Music,
//    VLC, IINA, Podcasts, Tidal, TV, and any app using AVPlayer/MPNowPlayingInfoCenter.
//    Listens to system notifications:
//    - `kMRMediaRemoteNowPlayingInfoDidChangeNotification`
//    - `kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification`
//    - `kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification`
//    - `kMRMediaRemoteNowPlayingApplicationDidChangeNotification`
//
// 2. Secondary Engine: `DistributedNotificationCenter`
//    Dedicated real-time push listeners for Spotify and Apple Music (`playerInfo` &
//    `PlaybackStateChanged`) for ultra-low latency metadata and artwork URL resolution.
//
// 3. Smart Asset URL & Local File Parser:
//    When QuickTime Player or VLC plays a local file (MP3, M4A, MOV, MP4), resolves
//    file URLs, formats song/artist names, and extracts embedded ID3 cover art.
//
// Idle Cleanliness & Pause Retention Rule:
// • On initial launch, only publishes if a media player is actively playing (`isPlaying == true`).
// • When playback is paused, stays active in the notch for 5 minutes (300s) before smoothly collapsing.
// • If the player application quits, collapses immediately.

import Foundation
import AppKit
import Combine
import AVFoundation
import SwiftUI

private typealias MRRegisterFunc         = @convention(c) (DispatchQueue) -> Void
private typealias MRGetInfoFunc          = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
private typealias MRGetPIDFunc           = @convention(c) (DispatchQueue, @escaping (pid_t) -> Void) -> Void
private typealias MRGetIsPlayingFunc     = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
private typealias MRGetPlaybackStateFunc = @convention(c) (DispatchQueue, @escaping (UInt32) -> Void) -> Void
private typealias MRSendCommandFunc      = @convention(c) (UInt32, [String: Any]?) -> Bool

final class MediaObserver: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    @Published private(set) var currentTrack: NowPlayingInfo? = nil

    @MainActor var onAccessibilityPermissionRequired: (() -> Void)? = nil

    @MainActor
    func updateCurrentTrackFavoriteState(isFavorited: Bool, trackID: String? = nil) {
        guard var track = currentTrack else { return }
        track.isFavorited = isFavorited
        if let trackID, !trackID.isEmpty {
            track.trackID = trackID
        }
        self.currentTrack = track
        NowPlayingViewModel.shared.isFavorited = isFavorited
    }

    // MARK: - Private Properties

    private var artworkCache: [String: NSImage] = [:]
    private var youtubeDurationCache: [String: TimeInterval] = [:]
    private var lastActiveApp: String = "QuickTime Player"
    private var lastKnownYouTubeURL: URL?
    private var lastKnownYouTubeTitle: String?
    private var pauseTimeoutWorkItem: DispatchWorkItem?
    private var mediaRemoteSyncTimer: AnyCancellable?

    /// Keep paused music active in the notch for 5 minutes (300 seconds) before hiding.
    private let pausedRetentionDuration: TimeInterval = 5 * 60

    /// Master toggle for YouTube media detection across browsers and native apps.
    /// Default is `false` to disable YouTube detection per user preference while preserving all underlying code.
    var isYouTubeDetectionEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "enableYouTubeDetection")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "enableYouTubeDetection")
        }
    }

    // MARK: - Browser & Media Identification Helpers

    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "company.thebrowser.Browser",
        "com.brave.Browser", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Canary",
        "org.mozilla.firefox", "org.mozilla.nightly",
        "com.operasoftware.Opera", "com.operasoftware.OperaNext",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS"
    ]

    func isBrowserApp(_ appName: String, bundleID: String? = nil) -> Bool {
        if let bundleID, Self.browserBundleIDs.contains(bundleID) { return true }
        let browserNames = ["Safari", "Chrome", "Arc", "Brave", "Edge", "Firefox", "Opera", "Vivaldi", "Orion"]
        return browserNames.contains { appName.localizedCaseInsensitiveContains($0) }
    }

    func isBrowserMediaTrack(_ track: NowPlayingInfo?) -> Bool {
        guard let track else { return false }
        if track.appName.localizedCaseInsensitiveContains("YouTube") { return true }
        if track.artist.localizedCaseInsensitiveContains("YouTube") { return true }
        if track.album.localizedCaseInsensitiveContains("YouTube") { return true }
        return isBrowserApp(track.appName)
    }

    // MediaRemote function pointers
    private var mrHandle: UnsafeMutableRawPointer?
    private var mrRegisterNotifications: MRRegisterFunc?
    private var mrGetNowPlayingInfo: MRGetInfoFunc?
    private var mrGetNowPlayingApplicationPID: MRGetPIDFunc?
    private var mrGetNowPlayingApplicationIsPlaying: MRGetIsPlayingFunc?
    private var mrGetNowPlayingApplicationPlaybackState: MRGetPlaybackStateFunc?
    private var mrSendCommand: MRSendCommandFunc?

    // MARK: - Init / Deinit

    init() {
        setupMediaRemoteEngine()
        registerDistributedNotifications()
        registerWorkspaceTerminationObserver()
        fetchCurrentInfo()
    }

    deinit {
        pauseTimeoutWorkItem?.cancel()
        mediaRemoteSyncTimer?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
        if let handle = mrHandle {
            dlclose(handle)
        }
    }

    // MARK: - 1. Universal MediaRemote Engine Setup

    private func setupMediaRemoteEngine() {
        mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        guard let handle = mrHandle else { return }

        if let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            mrRegisterNotifications = unsafeBitCast(regSym, to: MRRegisterFunc.self)
        }
        if let getSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mrGetNowPlayingInfo = unsafeBitCast(getSym, to: MRGetInfoFunc.self)
        }
        if let getPidSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            mrGetNowPlayingApplicationPID = unsafeBitCast(getPidSym, to: MRGetPIDFunc.self)
        }
        if let isPlayingSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            mrGetNowPlayingApplicationIsPlaying = unsafeBitCast(isPlayingSym, to: MRGetIsPlayingFunc.self)
        }
        if let stateSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState") {
            mrGetNowPlayingApplicationPlaybackState = unsafeBitCast(stateSym, to: MRGetPlaybackStateFunc.self)
        }
        if let cmdSym = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(cmdSym, to: MRSendCommandFunc.self)
        }

        // Register for system-wide Now Playing notifications
        mrRegisterNotifications?(DispatchQueue.main)

        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]

        for name in notificationNames {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMediaRemoteNotification(_:)),
                name: NSNotification.Name(name),
                object: nil
            )
        }

        // Register Darwin notification listener for instant system-wide media updates
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observerPtr = Unmanaged.passUnretained(self).toOpaque()
        let darwinCallback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let mySelf = Unmanaged<MediaObserver>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async {
                mySelf.queryMediaRemote(isInitial: false)
            }
        }

        let darwinNotifications = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRNowPlayingPlaybackQueueChangedNotification"
        ]

        for name in darwinNotifications {
            CFNotificationCenterAddObserver(
                darwinCenter,
                observerPtr,
                darwinCallback,
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        // Continuous 1.0s heartbeat poller to immediately catch active playback from any app or browser.
        mediaRemoteSyncTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.queryMediaRemote(isInitial: false)
                self.syncActivePlayerPositionIfNeeded()

                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self, self.isYouTubeDetectionEnabled else { return }
                    if self.currentTrack == nil {
                        _ = self.pollBrowserYouTubeState()
                    }
                }
            }
    }


    @objc private func handleMediaRemoteNotification(_ notification: Notification) {
        queryMediaRemote(isInitial: false)
    }

    // MARK: - 2. MediaRemote Query & Universal Parsing

    func queryMediaRemote(isInitial: Bool = false) {
        guard let mrGetInfo = mrGetNowPlayingInfo, let mrGetPID = mrGetNowPlayingApplicationPID else {
            return
        }

        mrGetPID(DispatchQueue.main) { [weak self] pid in
            guard let self else { return }

            mrGetInfo(DispatchQueue.main) { [weak self] dict in
                guard let self else { return }
                guard let dict = dict, !dict.isEmpty else {
                    // Never let an empty MediaRemote dictionary overwrite Spotify or Apple Music!
                    // Both Spotify and Apple Music manage their own authoritative playback states.
                    if let current = self.currentTrack, current.appName == "Spotify" || current.appName == "Music" {
                        return
                    }
                    if !isInitial, var current = self.currentTrack {
                        if current.isPlaying {
                            current.isPlaying = false
                            current.timestamp = Date()
                            DispatchQueue.main.async {
                                self.currentTrack = current
                                NowPlayingViewModel.shared.sync(with: current)
                                self.handlePlaybackStateChange(isPlaying: false)
                            }
                        }
                    }
                    return
                }

                if let getPlaybackState = self.mrGetNowPlayingApplicationPlaybackState {
                    getPlaybackState(DispatchQueue.main) { [weak self] stateCode in
                        guard let self else { return }
                        // stateCode: 1 = Playing, 2 = Paused, 3 = Stopped
                        let isStatePlaying: Bool? = (stateCode == 1) ? true : (stateCode == 2 || stateCode == 3 ? false : nil)

                        if let isStatePlaying {
                            self.processMediaRemoteDictionary(dict, pid: pid, isSystemPlaying: isStatePlaying, isInitial: isInitial)
                        } else if let getIsPlaying = self.mrGetNowPlayingApplicationIsPlaying {
                            getIsPlaying(DispatchQueue.main) { [weak self] isSystemPlaying in
                                self?.processMediaRemoteDictionary(dict, pid: pid, isSystemPlaying: isSystemPlaying, isInitial: isInitial)
                            }
                        } else {
                            self.processMediaRemoteDictionary(dict, pid: pid, isSystemPlaying: nil, isInitial: isInitial)
                        }
                    }
                } else if let getIsPlaying = self.mrGetNowPlayingApplicationIsPlaying {
                    getIsPlaying(DispatchQueue.main) { [weak self] isSystemPlaying in
                        self?.processMediaRemoteDictionary(dict, pid: pid, isSystemPlaying: isSystemPlaying, isInitial: isInitial)
                    }
                } else {
                    self.processMediaRemoteDictionary(dict, pid: pid, isSystemPlaying: nil, isInitial: isInitial)
                }
            }
        }
    }

    private func processMediaRemoteDictionary(_ dict: [String: Any], pid: pid_t, isSystemPlaying: Bool?, isInitial: Bool) {
        let app = NSRunningApplication(processIdentifier: pid)
        let appName = app?.localizedName ?? lastActiveApp
        lastActiveApp = appName

        let rawTitle  = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let rawArtist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let rawAlbum  = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        let elapsed  = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let rate     = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0

        // Robust isPlaying resolution:
        // 1. Explicit positive playback rate
        // 2. Authoritative system isPlaying == true
        // 3. Or elapsed time moving forward relative to currently tracked track
        var isPlaying = (rate > 0.0) || (isSystemPlaying == true)
        if !isPlaying, let current = currentTrack, current.title == rawTitle, current.appName == appName {
            if elapsed > current.elapsedTime + 0.3 {
                isPlaying = true
            }
        }

        // Never let a paused background app overwrite an actively playing track from another app!
        if let current = currentTrack, current.isPlaying, current.appName != appName, !isPlaying {
            return
        }

        NSLog("[DynamicNotch Media] App: %@ (PID %d), Title: %@, Rate: %.1f, isPlaying: %@", appName, pid, rawTitle, rate, isPlaying ? "YES" : "NO")

        // 1. If playback is paused/stopped and nothing is currently tracked,
        // do not resurrect a ghost/stale track from an idle browser or stopped player.
        if !isPlaying && currentTrack == nil {
            return
        }

        // 2. Only skip entirely if there's genuinely nothing to show (empty title, not playing, nothing tracked).
        // A paused track at 2:43 still needs to be stored so the UI has the correct position
        // if the user opens the notch manually. The NotchViewModel controls auto-show logic.
        if rawTitle.isEmpty && !isPlaying && currentTrack == nil {
            return
        }

        var artwork: NSImage? = nil
        if let data = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: data)
        }

        // Handle Asset URL (e.g. QuickTime Player local files, video, downloads)
        let rawURL = (dict["kMRMediaRemoteNowPlayingInfoAssetURL"] as? URL)
            ?? (dict["kMRMediaRemoteNowPlayingInfoAssetURL"] as? NSURL as URL?)
            ?? (dict["kMRMediaRemoteNowPlayingInfoAssetURL"] as? String).flatMap { URL(string: $0) }

        // Universal Smart Parser for Browsers, YouTube, and Media Sources
        let parsed = parseMediaMetadata(
            rawTitle: rawTitle,
            rawArtist: rawArtist,
            rawAlbum: rawAlbum,
            appName: appName,
            app: app,
            dict: dict,
            assetURL: rawURL,
            existingArtwork: artwork
        )

        let isYouTubeTrack = parsed.appName.localizedCaseInsensitiveContains("YouTube") ||
            rawTitle.localizedCaseInsensitiveContains("youtube") ||
            rawArtist.localizedCaseInsensitiveContains("youtube") ||
            (rawURL?.absoluteString ?? "").localizedCaseInsensitiveContains("youtube.com") ||
            (rawURL?.absoluteString ?? "").localizedCaseInsensitiveContains("youtu.be")

        if !isYouTubeDetectionEnabled && isYouTubeTrack {
            // YouTube detection is disabled per user preference while preserving full engine
            return
        }

        let cacheKey = "\(parsed.appName)-\(parsed.title)-\(parsed.artist)"
        var finalArtwork = parsed.artwork
        if let art = finalArtwork {
            artworkCache[cacheKey] = art
        } else if let cached = artworkCache[cacheKey] {
            finalArtwork = cached
        }

        // kMRMediaRemoteNowPlayingInfoElapsedTime is a SNAPSHOT taken at the last update event
        // (play / pause / seek). kMRMediaRemoteNowPlayingInfoTimestamp is the Date when that
        // snapshot was captured. True live position = elapsed + (now − timestamp) × rate.
        let snapshotDate = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date
        let effectiveRate = (rate > 0) ? rate : (isPlaying ? 1.0 : 0.0)
        let hasElapsedKey = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] != nil)
        let liveElapsed: TimeInterval

        if let ts = snapshotDate, effectiveRate > 0 {
            let drift = max(0, Date().timeIntervalSince(ts))
            if drift < 86400 {
                liveElapsed = max(0, elapsed + drift * effectiveRate)
            } else {
                liveElapsed = elapsed
            }
        } else if hasElapsedKey {
            liveElapsed = elapsed
        } else if isPlaying, let current = currentTrack, current.title == parsed.title, current.elapsedTime > 0 {
            let drift = max(0, Date().timeIntervalSince(current.timestamp))
            liveElapsed = max(0, current.elapsedTime + drift)
        } else {
            liveElapsed = elapsed
        }
        let clampedElapsed = duration > 0 ? min(liveElapsed, duration) : liveElapsed

        var resolvedTrackID: String? = nil
        if parsed.appName.localizedCaseInsensitiveContains("spotify") {
            if let current = currentTrack, current.title == parsed.title, let existingID = current.trackID {
                resolvedTrackID = existingID
            } else if let appleID = self.pollSpotifyCurrentTrackID() {
                resolvedTrackID = appleID
            }
        }

        var track = NowPlayingInfo(
            title: parsed.title,
            artist: parsed.artist,
            album: parsed.album,
            duration: duration,
            elapsedTime: clampedElapsed,
            artwork: finalArtwork,
            isPlaying: isPlaying,
            appName: parsed.appName,
            accentColor: parsed.accentColor,
            trackID: resolvedTrackID,
            timestamp: Date()
        )
        var isFav = MediaFavoritesManager.shared.isFavorited(track: track)
        if !isFav, let current = currentTrack, current.title == track.title, current.artist == track.artist, current.isFavorited {
            isFav = true
        }
        track.isFavorited = isFav

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let tid = resolvedTrackID, SpotifyAPIService.shared.isConnected {
                    track.isFavorited = isFav || SpotifyAPIService.shared.isLiked(spotifyURI: tid)
                }
                self.currentTrack = track
                NowPlayingViewModel.shared.sync(with: track)
                self.handlePlaybackStateChange(isPlaying: isPlaying)
            }
        }
    }

    private func pollSpotifyCurrentTrackID() -> String? {
        let script = "tell application id \"com.spotify.client\" to if player state is playing or player state is paused then return id of current track"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        let output = appleScript.executeAndReturnError(&error).stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    // MARK: - Smart Metadata & YouTube Engine

    private struct ParsedTrackMetadata {
        var title: String
        var artist: String
        var album: String
        var appName: String
        var artwork: NSImage?
        var accentColor: Color?
    }

    private func parseMediaMetadata(
        rawTitle: String,
        rawArtist: String,
        rawAlbum: String,
        appName: String,
        app: NSRunningApplication?,
        dict: [String: Any],
        assetURL: URL?,
        existingArtwork: NSImage?
    ) -> ParsedTrackMetadata {
        let bundleID = app?.bundleIdentifier ?? ""
        let isBrowser = Self.browserBundleIDs.contains(bundleID) ||
            ["Safari", "Chrome", "Arc", "Brave", "Edge", "Firefox", "Opera", "Vivaldi", "Orion"].contains {
                appName.localizedCaseInsensitiveContains($0)
            }

        let isYouTubeApp = appName.localizedCaseInsensitiveContains("YouTube") ||
                           bundleID.localizedCaseInsensitiveContains("YouTube")
        let titleHasYT = rawTitle.localizedCaseInsensitiveContains("youtube")
        let albumHasYT = rawAlbum.localizedCaseInsensitiveContains("youtube")
        let artistHasYT = rawArtist.localizedCaseInsensitiveContains("youtube")
        let urlHasYT = (assetURL?.absoluteString ?? "").localizedCaseInsensitiveContains("youtube.com") ||
                       (assetURL?.absoluteString ?? "").localizedCaseInsensitiveContains("youtu.be")
        let hasRecentYTTab = (lastKnownYouTubeURL != nil)

        var effectiveAssetURL = assetURL
        let isYouTube = isYouTubeApp || (isBrowser && (titleHasYT || albumHasYT || artistHasYT || urlHasYT || hasRecentYTTab))
        if isYouTube && effectiveAssetURL == nil {
            effectiveAssetURL = lastKnownYouTubeURL
        }

        if isYouTube {
            var cleanTitle = rawTitle

            // 0. Strip leading notification badge like "(1) ", "(129) "
            cleanTitle = cleanTitle.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)

            // 1. Strip YouTube and browser title suffixes
            let ytSuffixes = [
                " - YouTube Music", " – YouTube Music", " — YouTube Music",
                " - YouTube", " – YouTube", " — YouTube",
                " | YouTube", " · YouTube",
                " - Google Chrome", " - Safari", " - Arc", " - Brave", " - Firefox", " - Microsoft Edge"
            ]
            for suffix in ytSuffixes {
                if let range = cleanTitle.range(of: suffix, options: .caseInsensitive) {
                    cleanTitle.removeSubrange(range)
                }
            }
            cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            // 2. Strip video clutter tags like (Official Music Video), (Official Audio), [Video], etc.
            let tagsToRemove = [
                #"\s*[\(\[]Official\s+Music\s+Video[\)\]]"#,
                #"\s*[\(\[]Official\s+Video[\)\]]"#,
                #"\s*[\(\[]Official\s+Audio[\)\]]"#,
                #"\s*[\(\[]Official\s+HD\s+Video[\)\]]"#,
                #"\s*[\(\[]Official\s+4K\s+Video[\)\]]"#,
                #"\s*[\(\[]Music\s+Video[\)\]]"#,
                #"\s*[\(\[]Lyric\s+Video[\)\]]"#,
                #"\s*[\(\[]FULL-HD[\)\]]"#,
                #"\s*[\(\[]4K[\)\]]"#,
                #"\s*[\(\[]HD[\)\]]"#,
                #"\s*[\(\[]Video[\)\]]"#,
                #"\s*[\(\[]Audio[\)\]]"#,
                #"\s*[\(\[]Lyrics[\)\]]"#,
                #"\s*[\(\[]Clip\s+Officiel[\)\]]"#
            ]
            for pattern in tagsToRemove {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    cleanTitle = regex.stringByReplacingMatches(
                        in: cleanTitle,
                        options: [],
                        range: NSRange(location: 0, length: cleanTitle.utf16.count),
                        withTemplate: ""
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // 3. Separate Artist & Track if formatted as "Artist - Title"
            var cleanArtist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGenericArtist = cleanArtist.isEmpty ||
                                  cleanArtist == appName ||
                                  cleanArtist.localizedCaseInsensitiveContains("youtube") ||
                                  isBrowser

            if isGenericArtist {
                let delimiters = [" - ", " – ", " — "]
                for delimiter in delimiters {
                    if cleanTitle.contains(delimiter) {
                        let parts = cleanTitle.components(separatedBy: delimiter)
                        if parts.count >= 2 {
                            cleanArtist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            cleanTitle = parts.dropFirst().joined(separator: delimiter).trimmingCharacters(in: .whitespacesAndNewlines)
                            break
                        }
                    }
                }
                if cleanArtist.isEmpty || cleanArtist == appName || cleanArtist.localizedCaseInsensitiveContains("youtube") {
                    cleanArtist = "YouTube"
                }
            }

            if cleanTitle.isEmpty {
                cleanTitle = "YouTube Oynatılıyor"
            }

            let isYTMusic = rawAlbum.localizedCaseInsensitiveContains("Music") ||
                            rawTitle.localizedCaseInsensitiveContains("Music") ||
                            appName.localizedCaseInsensitiveContains("Music")
            let targetAppName = isYTMusic ? "YouTube Music" : "YouTube"
            let ytRed = Color(red: 1.0, green: 0.13, blue: 0.13)

            // 4. Resolve / Download Artwork
            var resolvedArtwork = existingArtwork
            let candidateStrings: [String] = [
                effectiveAssetURL?.absoluteString ?? "",
                dict["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String ?? "",
                dict["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"] as? String ?? "",
                dict["kMRMediaRemoteNowPlayingInfoExternalContentIdentifier"] as? String ?? ""
            ]

            var foundVideoID: String? = nil
            let videoIDPattern = #"(?:v=|youtu\.be\/|embed\/|vi\/)([a-zA-Z0-9_-]{11})"#
            if let regex = try? NSRegularExpression(pattern: videoIDPattern, options: []) {
                for str in candidateStrings where !str.isEmpty {
                    let range = NSRange(location: 0, length: str.utf16.count)
                    if let match = regex.firstMatch(in: str, options: [], range: range), match.numberOfRanges > 1 {
                        let idRange = match.range(at: 1)
                        if let swiftRange = Range(idRange, in: str) {
                            foundVideoID = String(str[swiftRange])
                            break
                        }
                    }
                }
            }

            let ytCacheKey = "YouTube-\(foundVideoID ?? "\(cleanArtist)-\(cleanTitle)")"
            if let cached = artworkCache[ytCacheKey] {
                resolvedArtwork = cached
            } else if let vID = foundVideoID {
                fetchYouTubeThumbnail(videoID: vID, cacheKey: ytCacheKey)
                fetchYouTubeDuration(videoID: vID)
            }

            if resolvedArtwork == nil {
                resolvedArtwork = generateYouTubeArtwork(isMusic: isYTMusic)
                artworkCache[ytCacheKey] = resolvedArtwork
            }

            return ParsedTrackMetadata(
                title: cleanTitle,
                artist: cleanArtist,
                album: rawAlbum.isEmpty ? targetAppName : rawAlbum,
                appName: targetAppName,
                artwork: resolvedArtwork,
                accentColor: ytRed
            )
        }

        // Generic Browser Media (SoundCloud, web podcasts, Twitch, etc.)
        if isBrowser {
            var cleanTitle = rawTitle
            let browserSuffixes = [" - Google Chrome", " - Safari", " - Arc", " - Brave", " - Firefox", " - Microsoft Edge"]
            for suffix in browserSuffixes {
                if let range = cleanTitle.range(of: suffix, options: .caseInsensitive) {
                    cleanTitle.removeSubrange(range)
                }
            }
            cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            var cleanArtist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanArtist.isEmpty || cleanArtist == appName {
                let delimiters = [" - ", " – ", " — "]
                for delimiter in delimiters {
                    if cleanTitle.contains(delimiter) {
                        let parts = cleanTitle.components(separatedBy: delimiter)
                        if parts.count >= 2 {
                            cleanArtist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            cleanTitle = parts.dropFirst().joined(separator: delimiter).trimmingCharacters(in: .whitespacesAndNewlines)
                            break
                        }
                    }
                }
            }
            if cleanArtist.isEmpty {
                cleanArtist = appName
            }
            if cleanTitle.isEmpty {
                cleanTitle = "\(appName) Oynatılıyor"
            }

            return ParsedTrackMetadata(
                title: cleanTitle,
                artist: cleanArtist,
                album: rawAlbum,
                appName: appName,
                artwork: existingArtwork ?? app?.icon,
                accentColor: nil
            )
        }

        // Standard Players (Apple Music, Spotify, QuickTime, VLC, IINA, etc.)
        var finalTitle = rawTitle
        var finalArtist = rawArtist

        if let rawURL = assetURL {
            let fileURL = (rawURL as NSURL).filePathURL ?? rawURL
            if fileURL.isFileURL {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                if finalTitle.isEmpty {
                    if filename.contains(" - ") {
                        let parts = filename.components(separatedBy: " - ")
                        finalArtist = parts[0].trimmingCharacters(in: .whitespaces)
                        finalTitle  = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                    } else {
                        finalTitle = filename
                    }
                }
                if finalArtist.isEmpty {
                    finalArtist = appName
                }
            }
        }

        if finalTitle.isEmpty {
            finalTitle = "\(appName) Oynatılıyor"
        }
        if finalArtist.isEmpty {
            finalArtist = appName
        }

        var resolvedArtwork = existingArtwork
        if resolvedArtwork == nil, let rawURL = assetURL {
            let fileURL = (rawURL as NSURL).filePathURL ?? rawURL
            if fileURL.isFileURL {
                Task { [weak self] in
                    guard let self else { return }
                    let asset = AVURLAsset(url: fileURL)
                    if let items = try? await asset.load(.commonMetadata) {
                        for item in items {
                            if item.commonKey?.rawValue == "artwork" {
                                if let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
                                    await MainActor.run { [weak self] in
                                        guard let self else { return }
                                        if var track = self.currentTrack {
                                            track.setArtwork(image)
                                            self.currentTrack = track
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }

        if resolvedArtwork == nil {
            resolvedArtwork = app?.icon
        }

        return ParsedTrackMetadata(
            title: finalTitle,
            artist: finalArtist,
            album: rawAlbum,
            appName: appName,
            artwork: resolvedArtwork,
            accentColor: nil
        )
    }

    private func fetchYouTubeThumbnail(videoID: String, cacheKey: String) {
        guard let url = URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self, let data, error == nil, let image = NSImage(data: data) else { return }

            DispatchQueue.main.async {
                self.artworkCache[cacheKey] = image
                if var track = self.currentTrack, track.appName.contains("YouTube") {
                    track.setArtwork(image)
                    self.currentTrack = track
                }
            }
        }.resume()
    }

    private func fetchYouTubeDuration(videoID: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, let data, error == nil,
                  let html = String(data: data, encoding: .utf8) else { return }

            var durationSeconds: TimeInterval = 0
            if let match = html.range(of: #""approxDurationMs":"([0-9]+)""#, options: .regularExpression) {
                let matchedStr = String(html[match])
                let digits = matchedStr.filter { $0.isNumber }
                if let ms = Double(digits) {
                    durationSeconds = ms / 1000.0
                }
            } else if let match = html.range(of: #""lengthSeconds":"([0-9]+)""#, options: .regularExpression) {
                let matchedStr = String(html[match])
                let digits = matchedStr.filter { $0.isNumber }
                if let sec = Double(digits) {
                    durationSeconds = sec
                }
            }

            if durationSeconds > 0 {
                DispatchQueue.main.async {
                    self.youtubeDurationCache[videoID] = durationSeconds
                    if var track = self.currentTrack, track.appName.contains("YouTube") {
                        track.duration = durationSeconds
                        self.currentTrack = track
                    }
                }
            }
        }.resume()
    }

    private func generateYouTubeArtwork(isMusic: Bool = false) -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let cornerRadius: CGFloat = 28
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        let gradient = NSGradient(
            starting: NSColor(red: 1.0, green: 0.13, blue: 0.13, alpha: 1.0),
            ending: NSColor(red: 0.82, green: 0.05, blue: 0.05, alpha: 1.0)
        )
        gradient?.draw(in: path, angle: -45)

        // Subtle highlight ring (Apple HIG style)
        NSColor(white: 1.0, alpha: 0.18).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        if isMusic {
            let center = NSPoint(x: size.width / 2, y: size.height / 2)
            let circlePath = NSBezierPath(ovalIn: NSRect(x: 28, y: 28, width: 72, height: 72))
            NSColor(white: 1.0, alpha: 0.35).setStroke()
            circlePath.lineWidth = 4.0
            circlePath.stroke()

            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: center.x - 11, y: center.y - 18))
            triangle.line(to: NSPoint(x: center.x + 19, y: center.y))
            triangle.line(to: NSPoint(x: center.x - 11, y: center.y + 18))
            triangle.close()
            NSColor.white.setFill()
            triangle.fill()
        } else {
            let center = NSPoint(x: size.width / 2, y: size.height / 2)
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: center.x - 14, y: center.y - 23))
            triangle.line(to: NSPoint(x: center.x + 23, y: center.y))
            triangle.line(to: NSPoint(x: center.x - 14, y: center.y + 23))
            triangle.close()
            NSColor.white.setFill()
            triangle.fill()
        }

        image.unlockFocus()
        return image
    }

    private func handlePlaybackStateChange(isPlaying: Bool) {
        if isPlaying {
            cancelPauseTimeout()
        } else {
            updatePauseTimeout(isPlaying: false)
        }
    }

    // MARK: - 3. Distributed Notifications for Spotify & Apple Music (Fast Push)

    private func registerDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        dnc.addObserver(
            self,
            selector: #selector(handleAppleMusicNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        dnc.addObserver(
            self,
            selector: #selector(handleAppleMusicNotification(_:)),
            name: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleSpotifyNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        lastActiveApp = "Spotify"

        let state = info["Player State"] as? String ?? "Paused"
        let isPlaying = (state.lowercased() == "playing")

        let title  = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album  = info["Album"] as? String ?? ""

        if title.isEmpty {
            if var current = currentTrack, current.appName == "Spotify" {
                if current.isPlaying {
                    current.isPlaying = false
                    current.timestamp = Date()
                    DispatchQueue.main.async {
                        self.currentTrack = current
                        NowPlayingViewModel.shared.sync(with: current)
                        self.handlePlaybackStateChange(isPlaying: false)
                    }
                }
            }
            return
        }

        let rawDuration = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let duration = rawDuration > 1000 ? rawDuration / 1000.0 : rawDuration
        let elapsed  = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0

        let cacheKey = "Spotify-\(title)-\(artist)-\(album)"
        let cachedArt = artworkCache[cacheKey]
        let trackID = info["Track ID"] as? String

        var track = NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsed,
            artwork: cachedArt,
            isPlaying: isPlaying,
            appName: "Spotify",
            trackID: trackID
        )
        let isFav = MediaFavoritesManager.shared.isFavorited(track: track)
        track.isFavorited = isFav

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let trackID, SpotifyAPIService.shared.isConnected {
                    track.isFavorited = isFav || SpotifyAPIService.shared.isLiked(spotifyURI: trackID)
                }
                self.currentTrack = track
                NowPlayingViewModel.shared.sync(with: track)
                self.handlePlaybackStateChange(isPlaying: isPlaying)
            }
        }

        if cachedArt == nil {
            fetchSpotifyArtwork(for: cacheKey)
        }
    }

    @objc private func handleAppleMusicNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        lastActiveApp = "Music"

        let state = info["Player State"] as? String ?? "Paused"
        let isPlaying = (state.lowercased() == "playing")

        let title  = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album  = info["Album"] as? String ?? ""

        if title.isEmpty {
            if var current = currentTrack, current.appName == "Music" {
                if current.isPlaying {
                    current.isPlaying = false
                    current.timestamp = Date()
                    DispatchQueue.main.async {
                        self.currentTrack = current
                        NowPlayingViewModel.shared.sync(with: current)
                        self.handlePlaybackStateChange(isPlaying: false)
                    }
                }
            }
            return
        }

        let totalTimeMS = (info["Total Time"] as? NSNumber)?.doubleValue ?? 0
        let duration = totalTimeMS > 0 ? totalTimeMS / 1000.0 : 0
        let elapsed  = (info["Elapsed Time"] as? NSNumber)?.doubleValue ?? 0

        let cacheKey = "Music-\(title)-\(artist)-\(album)"
        let cachedArt = artworkCache[cacheKey]

        var track = NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsed,
            artwork: cachedArt,
            isPlaying: isPlaying,
            appName: "Music"
        )
        track.isFavorited = MediaFavoritesManager.shared.isFavorited(track: track)

        DispatchQueue.main.async {
            self.currentTrack = track
            NowPlayingViewModel.shared.sync(with: track)
            self.handlePlaybackStateChange(isPlaying: isPlaying)
        }

        if cachedArt == nil {
            fetchAppleMusicArtwork(for: cacheKey)
        }
    }

    // MARK: - 3b. Fast Seek & Loop Synchronizer for Music.app & Spotify

    private func syncActivePlayerPositionIfNeeded() {
        guard let current = currentTrack else {
            // When nothing is currently tracked, actively inspect if Music or Spotify is running and playing
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
                if runningBundleIDs.contains("com.spotify.client") {
                    if self.pollSpotifyState() { return }
                }
                if runningBundleIDs.contains("com.apple.Music") {
                    if self.pollAppleMusicState() { return }
                }
            }
            return
        }

        if current.appName == "Music" {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let script = """
                tell application id "com.apple.Music"
                    try
                        return (player state as text) & "|||" & (player position as text)
                    on error
                        return ""
                    end try
                end tell
                """
                guard let output = self.runAppleScript(script), !output.isEmpty else { return }
                let parts = output.components(separatedBy: "|||")
                guard parts.count >= 2 else { return }
                let stateText = parts[0].lowercased()
                let isPlayingNow = stateText.contains("play") || stateText.contains("kpsp")
                guard let pos = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return }

                DispatchQueue.main.async {
                    guard var track = self.currentTrack, track.appName == "Music" else { return }
                    let currentLive = track.currentLiveElapsed
                    let diff = abs(currentLive - pos)
                    let isLooped = (track.isPlaying && currentLive > 5.0 && pos < 3.0)
                    let playStateChanged = (track.isPlaying != isPlayingNow)

                    if playStateChanged || diff > 1.5 || isLooped || (!track.isPlaying && isPlayingNow) {
                        track.isPlaying = isPlayingNow
                        track.elapsedTime = pos
                        track.timestamp = Date()
                        self.currentTrack = track
                        NowPlayingViewModel.shared.sync(with: track)
                        if playStateChanged {
                            self.handlePlaybackStateChange(isPlaying: isPlayingNow)
                        }
                    }
                }
            }
        } else if current.appName == "Spotify" {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let script = """
                tell application id "com.spotify.client"
                    try
                        return (player state as text) & "|||" & (player position as text)
                    on error
                        return ""
                    end try
                end tell
                """
                guard let output = self.runAppleScript(script), !output.isEmpty else { return }
                let parts = output.components(separatedBy: "|||")
                guard parts.count >= 2 else { return }
                let stateText = parts[0].lowercased()
                let isPlayingNow = stateText.contains("play") || stateText.contains("kpsp")
                guard let pos = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return }

                DispatchQueue.main.async {
                    guard var track = self.currentTrack, track.appName == "Spotify" else { return }
                    let currentLive = track.currentLiveElapsed
                    let diff = abs(currentLive - pos)
                    let isLooped = (track.isPlaying && currentLive > 5.0 && pos < 3.0)
                    let playStateChanged = (track.isPlaying != isPlayingNow)

                    if playStateChanged || diff > 1.5 || isLooped || (!track.isPlaying && isPlayingNow) {
                        track.isPlaying = isPlayingNow
                        track.elapsedTime = pos
                        track.timestamp = Date()
                        self.currentTrack = track
                        NowPlayingViewModel.shared.sync(with: track)
                        if playStateChanged {
                            self.handlePlaybackStateChange(isPlaying: isPlayingNow)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. Workspace Termination Observer

    private func registerWorkspaceTerminationObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

        // If the application that was currently playing terminates, collapse immediately
        if let current = currentTrack {
            let matchesDirectApp = (current.appName == app.localizedName || current.appName == app.bundleIdentifier)
            let isTerminatedAppBrowser = isBrowserApp(app.localizedName ?? "", bundleID: app.bundleIdentifier)
            let isCurrentTrackBrowser = isBrowserMediaTrack(current)

            if matchesDirectApp || (isTerminatedAppBrowser && isCurrentTrackBrowser) {
                cancelPauseTimeout()
                DispatchQueue.main.async {
                    self.lastKnownYouTubeURL = nil
                    self.lastKnownYouTubeTitle = nil
                    self.currentTrack = nil
                }
            }
        }
    }

    private func updatePauseTimeout(isPlaying: Bool) {
        pauseTimeoutWorkItem?.cancel()
        pauseTimeoutWorkItem = nil

        if !isPlaying {
            // Retain paused media across ALL players (Spotify, Music, Browsers) for 5 minutes (300 seconds).
            let duration: TimeInterval = pausedRetentionDuration

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.currentTrack?.isPlaying == false {
                    self.lastKnownYouTubeURL = nil
                    self.lastKnownYouTubeTitle = nil
                    self.currentTrack = nil
                }
            }
            pauseTimeoutWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + duration,
                execute: work
            )
        }
    }

    private func cancelPauseTimeout() {
        pauseTimeoutWorkItem?.cancel()
        pauseTimeoutWorkItem = nil
    }

    // MARK: - 5. Initial Polling & Artwork Retrieval

    /// Only activates Now Playing on launch if a player is **currently playing**.
    func fetchCurrentInfo() {
        queryMediaRemote(isInitial: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let runningBundleIDs = Set(
                NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
            )

            if runningBundleIDs.contains("com.spotify.client") {
                if self.pollSpotifyState() { return }
            }

            if runningBundleIDs.contains("com.apple.Music") {
                if self.pollAppleMusicState() { return }
            }

            let browserIDs: Set<String> = [
                "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"
            ]
            if !runningBundleIDs.isDisjoint(with: browserIDs) && self.isYouTubeDetectionEnabled {
                // Give MediaRemote 0.5s to populate authoritative state before falling back to browser tab inspection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.isYouTubeDetectionEnabled else { return }
                    if self.currentTrack == nil {
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            _ = self?.pollBrowserYouTubeState()
                        }
                    }
                }
            }
        }
    }

    private func pollSpotifyState() -> Bool {
        let scriptSource = """
        tell application id "com.spotify.client"
            try
                if (player state as text) contains "play" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDur to duration of current track
                    set tPos to player position
                    set tArt to artwork url of current track
                    try
                        set tId to id of current track
                    on error
                        set tId to ""
                    end try
                    return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDur as string) & "|||" & (tPos as string) & "|||PLAYING|||" & tArt & "|||" & tId
                end if
            end try
        end tell
        return ""
        """

        guard let output = runAppleScript(scriptSource), !output.isEmpty else {
            return false
        }

        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return false }

        let title  = parts[0]
        let artist = parts[1]
        let album  = parts[2]
        let rawDur = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let duration = rawDur > 1000 ? rawDur / 1000.0 : rawDur
        let elapsed  = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let artURLString = parts.count >= 7 ? parts[6] : ""
        let trackID = parts.count >= 8 ? parts[7] : ""

        guard !title.isEmpty else { return false }

        lastActiveApp = "Spotify"
        let cacheKey = "Spotify-\(title)-\(artist)-\(album)"

        DispatchQueue.main.async {
            self.cancelPauseTimeout()
            var track = NowPlayingInfo(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsedTime: elapsed,
                artwork: self.artworkCache[cacheKey],
                isPlaying: true,
                appName: "Spotify",
                trackID: trackID.isEmpty ? nil : trackID
            )
            let isFav = MediaFavoritesManager.shared.isFavorited(track: track)
            track.isFavorited = isFav

            MainActor.assumeIsolated {
                if !trackID.isEmpty && SpotifyAPIService.shared.isConnected {
                    track.isFavorited = isFav || SpotifyAPIService.shared.isLiked(spotifyURI: trackID)
                }
                self.currentTrack = track
                NowPlayingViewModel.shared.sync(with: track)
                self.handlePlaybackStateChange(isPlaying: true)
            }
        }

        if !artURLString.isEmpty, let url = URL(string: artURLString) {
            downloadArtwork(from: url, cacheKey: cacheKey)
        }
        return true
    }

    private func pollAppleMusicState() -> Bool {
        let scriptSource = """
        tell application id "com.apple.Music"
            try
                if (player state as text) contains "play" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDur to duration of current track
                    set tPos to player position
                    try
                        set tFav to (favorited of current track) as string
                    on error
                        set tFav to "false"
                    end try
                    return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDur as string) & "|||" & (tPos as string) & "|||PLAYING|||" & tFav
                end if
            end try
        end tell
        return ""
        """

        guard let output = runAppleScript(scriptSource), !output.isEmpty else {
            return false
        }

        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return false }

        let title  = parts[0]
        let artist = parts[1]
        let album  = parts[2]
        let duration = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let elapsed  = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let isFav = parts.count >= 7 ? (parts[6].lowercased() == "true") : false

        guard !title.isEmpty else { return false }

        lastActiveApp = "Music"
        let cacheKey = "Music-\(title)-\(artist)-\(album)"

        DispatchQueue.main.async {
            self.cancelPauseTimeout()
            var track = NowPlayingInfo(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsedTime: elapsed,
                artwork: self.artworkCache[cacheKey],
                isPlaying: true,
                appName: "Music",
                isFavorited: isFav
            )
            track.isFavorited = isFav || MediaFavoritesManager.shared.isFavorited(track: track)
            self.currentTrack = track
            NowPlayingViewModel.shared.sync(with: track)
        }

        fetchAppleMusicArtwork(for: cacheKey)
        return true
    }

    private func fetchSpotifyArtwork(for cacheKey: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = """
            tell application "Spotify"
                return artwork url of current track
            end tell
            """
            guard let urlString = self?.runAppleScript(script),
                  let url = URL(string: urlString) else { return }
            self?.downloadArtwork(from: url, cacheKey: cacheKey)
        }
    }

    private func fetchAppleMusicArtwork(for cacheKey: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = """
            tell application "Music"
                if (count of artworks of current track) > 0 then
                    return raw data of artwork 1 of current track
                end if
            end tell
            """
            guard let appleScript = NSAppleScript(source: script) else { return }
            var error: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&error)
            guard error == nil else { return }

            let data = descriptor.data
            if !data.isEmpty, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self?.artworkCache[cacheKey] = image
                    if var track = self?.currentTrack {
                        track.setArtwork(image)
                        self?.currentTrack = track
                    }
                }
            }
        }
    }

    private func downloadArtwork(from url: URL, cacheKey: String) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.artworkCache[cacheKey] = image
                if var track = self?.currentTrack {
                    track.setArtwork(image)
                    self?.currentTrack = track
                }
            }
        }.resume()
    }

    // MARK: - Browser YouTube Tab Verification

    func checkIfYouTubeTabExists() -> Bool {
        guard isYouTubeDetectionEnabled else { return false }
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )

        let supportedBrowserIDs: Set<String> = [
            "com.apple.Safari", "com.apple.SafariTechnologyPreview",
            "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
            "company.thebrowser.Browser",
            "com.brave.Browser", "com.brave.Browser.nightly",
            "com.microsoft.edgemac", "com.microsoft.edgemac.Canary"
        ]

        if runningBundleIDs.isDisjoint(with: supportedBrowserIDs) {
            return false
        }

        // 1. Safari
        if runningBundleIDs.contains("com.apple.Safari") || runningBundleIDs.contains("com.apple.SafariTechnologyPreview") {
            let safariApp = runningBundleIDs.contains("com.apple.SafariTechnologyPreview") ? "Safari Technology Preview" : "Safari"
            let script = """
            tell application "\(safariApp)"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "youtu.be/" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "music.youtube.com" then
                                return "true"
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return "false"
            """
            if let result = runAppleScript(script), result.contains("true") {
                return true
            }
        }

        // 2. Google Chrome
        if runningBundleIDs.contains("com.google.Chrome") || runningBundleIDs.contains("com.google.Chrome.canary") || runningBundleIDs.contains("com.google.Chrome.beta") {
            let chromeApp = runningBundleIDs.contains("com.google.Chrome.canary") ? "Google Chrome Canary" : "Google Chrome"
            let script = """
            tell application "\(chromeApp)"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "youtu.be/" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "music.youtube.com" then
                                return "true"
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return "false"
            """
            if let result = runAppleScript(script), result.contains("true") {
                return true
            }
        }

        // 3. Arc Browser
        if runningBundleIDs.contains("company.thebrowser.Browser") {
            let script = """
            tell application "Arc"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "youtu.be/" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "music.youtube.com" then
                                return "true"
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return "false"
            """
            if let result = runAppleScript(script), result.contains("true") {
                return true
            }
        }

        // 4. Brave Browser
        if runningBundleIDs.contains("com.brave.Browser") || runningBundleIDs.contains("com.brave.Browser.nightly") {
            let script = """
            tell application "Brave Browser"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "youtu.be/" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "music.youtube.com" then
                                return "true"
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return "false"
            """
            if let result = runAppleScript(script), result.contains("true") {
                return true
            }
        }

        // 5. Microsoft Edge
        if runningBundleIDs.contains("com.microsoft.edgemac") || runningBundleIDs.contains("com.microsoft.edgemac.Canary") {
            let script = """
            tell application "Microsoft Edge"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "youtu.be/" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "music.youtube.com" then
                                return "true"
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return "false"
            """
            if let result = runAppleScript(script), result.contains("true") {
                return true
            }
        }

        return false
    }

    // MARK: - Browser YouTube Tab Bridge (Safari, Chrome, Arc, Brave, Edge)

    func pollBrowserYouTubeState() -> Bool {
        guard isYouTubeDetectionEnabled else { return false }
        // Do not interrupt actively playing Spotify or Apple Music
        if let current = currentTrack, current.isPlaying && current.appName != "YouTube" {
            return false
        }

        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )

        var foundData: String? = nil

        // 1. Check Safari
        if runningBundleIDs.contains("com.apple.Safari") || runningBundleIDs.contains("com.apple.SafariTechnologyPreview") {
            let safariApp = runningBundleIDs.contains("com.apple.SafariTechnologyPreview") ? "Safari Technology Preview" : "Safari"
            let script = """
            tell application "\(safariApp)"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL contains "youtube.com/watch" or tURL contains "youtu.be/" or tURL contains "youtube.com/shorts" or tURL contains "youtube.com/live" or tURL contains "music.youtube.com" then
                                set tName to name of t
                                set jsData to ""
                                try
                                    set jsData to (do JavaScript "const v = document.querySelector('video'); v ? (v.currentTime + '|||' + v.duration + '|||' + (v.paused ? 'PAUSED' : 'PLAYING')) : ''" in t)
                                end try
                                return tName & "|||" & tURL & "|||" & jsData
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
            if let output = runAppleScript(script), !output.isEmpty {
                foundData = output
            }
        }

        // 2. Check Google Chrome
        if foundData == nil && (runningBundleIDs.contains("com.google.Chrome") || runningBundleIDs.contains("com.google.Chrome.canary") || runningBundleIDs.contains("com.google.Chrome.beta")) {
            let chromeApp = runningBundleIDs.contains("com.google.Chrome.canary") ? "Google Chrome Canary" : "Google Chrome"
            let script = """
            tell application "\(chromeApp)"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL contains "youtube.com/watch" or tURL contains "youtu.be/" or tURL contains "youtube.com/shorts" or tURL contains "youtube.com/live" or tURL contains "music.youtube.com" then
                                set tTitle to title of t
                                set jsData to ""
                                try
                                    set jsData to (execute t javascript "const v = document.querySelector('video'); v ? (v.currentTime + '|||' + v.duration + '|||' + (v.paused ? 'PAUSED' : 'PLAYING')) : ''")
                                end try
                                return tTitle & "|||" & tURL & "|||" & jsData
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
            if let output = runAppleScript(script), !output.isEmpty {
                foundData = output
            }
        }

        // 3. Check Arc Browser
        if foundData == nil && runningBundleIDs.contains("company.thebrowser.Browser") {
            let script = """
            tell application "Arc"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL contains "youtube.com/watch" or tURL contains "youtu.be/" or tURL contains "youtube.com/shorts" or tURL contains "youtube.com/live" or tURL contains "music.youtube.com" then
                                set tTitle to title of t
                                set jsData to ""
                                try
                                    set jsData to (execute t javascript "const v = document.querySelector('video'); v ? (v.currentTime + '|||' + v.duration + '|||' + (v.paused ? 'PAUSED' : 'PLAYING')) : ''")
                                end try
                                return tTitle & "|||" & tURL & "|||" & jsData
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
            if let output = runAppleScript(script), !output.isEmpty {
                foundData = output
            }
        }

        // 4. Check Brave Browser
        if foundData == nil && (runningBundleIDs.contains("com.brave.Browser") || runningBundleIDs.contains("com.brave.Browser.nightly")) {
            let script = """
            tell application "Brave Browser"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL contains "youtube.com/watch" or tURL contains "youtu.be/" or tURL contains "youtube.com/shorts" or tURL contains "youtube.com/live" or tURL contains "music.youtube.com" then
                                set tTitle to title of t
                                set jsData to ""
                                try
                                    set jsData to (execute t javascript "const v = document.querySelector('video'); v ? (v.currentTime + '|||' + v.duration + '|||' + (v.paused ? 'PAUSED' : 'PLAYING')) : ''")
                                end try
                                return tTitle & "|||" & tURL & "|||" & jsData
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
            if let output = runAppleScript(script), !output.isEmpty {
                foundData = output
            }
        }

        // 5. Check Microsoft Edge
        if foundData == nil && (runningBundleIDs.contains("com.microsoft.edgemac") || runningBundleIDs.contains("com.microsoft.edgemac.Canary")) {
            let script = """
            tell application "Microsoft Edge"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            set tURL to URL of t
                            if tURL contains "youtube.com/watch" or tURL contains "youtu.be/" or tURL contains "youtube.com/shorts" or tURL contains "youtube.com/live" or tURL contains "music.youtube.com" then
                                set tTitle to title of t
                                set jsData to ""
                                try
                                    set jsData to (execute t javascript "const v = document.querySelector('video'); v ? (v.currentTime + '|||' + v.duration + '|||' + (v.paused ? 'PAUSED' : 'PLAYING')) : ''")
                                end try
                                return tTitle & "|||" & tURL & "|||" & jsData
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
            if let output = runAppleScript(script), !output.isEmpty {
                foundData = output
            }
        }

        guard let output = foundData, !output.isEmpty else {
            // If YouTube or browser media was previously showing, but the tab is now closed or navigated away
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let current = self.currentTrack, self.isBrowserMediaTrack(current) {
                    self.cancelPauseTimeout()
                    self.lastKnownYouTubeURL = nil
                    self.lastKnownYouTubeTitle = nil
                    self.currentTrack = nil
                }
            }
            return false
        }

        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 2 else { return false }

        let rawTitle = parts[0]
        let rawURLString = parts[1]
        let url = URL(string: rawURLString)

        // Extract video ID from URL
        var videoID: String? = nil
        if let url = url {
            let str = url.absoluteString
            let pattern = #"(?:v=|youtu\.be\/|embed\/|vi\/)([a-zA-Z0-9_-]{11})"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: str.utf16.count)
                if let match = regex.firstMatch(in: str, options: [], range: range), match.numberOfRanges > 1 {
                    if let r = Range(match.range(at: 1), in: str) {
                        videoID = String(str[r])
                    }
                }
            }
        }

        self.lastKnownYouTubeURL = url
        self.lastKnownYouTubeTitle = rawTitle

        var liveElapsed: TimeInterval? = nil
        var liveDuration: TimeInterval? = nil
        var liveIsPlaying: Bool? = nil

        // If JS execution failed (e.g. Safari without "Allow JS from Apple Events"),
        // and we already have valid media metadata from MediaRemote, do not overwrite it with zeros.
        if parts.count < 5 {
            if let current = currentTrack, current.duration > 0 {
                return true
            }
        }

        // If JS execution succeeded (parts has currentTime, duration, state):
        if parts.count >= 5 {
            if let cur = Double(parts[2].replacingOccurrences(of: ",", with: ".")), cur > 0 { liveElapsed = cur }
            if let dur = Double(parts[3].replacingOccurrences(of: ",", with: ".")), dur > 0 { liveDuration = dur }
            let stateStr = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
            if stateStr == "PLAYING" { liveIsPlaying = true }
            else if stateStr == "PAUSED" { liveIsPlaying = false }
        }

        let parsed = parseMediaMetadata(
            rawTitle: rawTitle,
            rawArtist: "",
            rawAlbum: "YouTube",
            appName: "YouTube",
            app: nil,
            dict: [:],
            assetURL: url,
            existingArtwork: nil
        )

        // Resolve Duration
        var resolvedDuration: TimeInterval = 0
        if let liveDur = liveDuration, liveDur > 0 {
            resolvedDuration = liveDur
            if let vid = videoID { youtubeDurationCache[vid] = liveDur }
        } else if let vid = videoID {
            if let cached = youtubeDurationCache[vid] {
                resolvedDuration = cached
            } else {
                fetchYouTubeDuration(videoID: vid)
                resolvedDuration = (currentTrack?.title == parsed.title) ? (currentTrack?.duration ?? 0) : 0
            }
        } else {
            resolvedDuration = (currentTrack?.title == parsed.title) ? (currentTrack?.duration ?? 0) : 0
        }

        // Resolve Elapsed Time
        var resolvedElapsed: TimeInterval = 0
        if let liveEl = liveElapsed {
            resolvedElapsed = liveEl
        } else if let current = currentTrack, current.title == parsed.title {
            resolvedElapsed = current.elapsedTime
        }

        // When JS is unavailable (e.g. Safari without "Allow JS from Apple Events"),
        // preserve the existing isPlaying state rather than blindly defaulting to true.
        // Priority: live JS data > existing track state > MediaRemote system state > false
        let isPlaying: Bool
        if let liveState = liveIsPlaying {
            isPlaying = liveState
        } else if let current = currentTrack, current.title == parsed.title {
            // Same track already tracked — preserve its play/pause state.
            isPlaying = current.isPlaying
        } else {
            // New track, no JS data — ask MediaRemote rather than guessing true.
            // This prevents showing a paused track as "playing" on app start.
            if let mrIsPlaying = mrGetNowPlayingApplicationIsPlaying {
                var result = false
                let sem = DispatchSemaphore(value: 0)
                mrIsPlaying(.global(qos: .utility)) { playing in result = playing; sem.signal() }
                _ = sem.wait(timeout: .now() + 0.3)
                isPlaying = result
            } else {
                isPlaying = false
            }
        }

        let cacheKey = "YouTube-\(parsed.title)-\(parsed.artist)"
        let artwork = artworkCache[cacheKey] ?? parsed.artwork

        let track = NowPlayingInfo(
            title: parsed.title,
            artist: parsed.artist,
            album: parsed.album,
            duration: resolvedDuration,
            elapsedTime: resolvedElapsed,
            artwork: artwork,
            isPlaying: isPlaying,
            appName: "YouTube",
            accentColor: parsed.accentColor
        )

        DispatchQueue.main.async {
            self.currentTrack = track
            NowPlayingViewModel.shared.sync(with: track)
            self.handlePlaybackStateChange(isPlaying: isPlaying)
        }

        return true
    }

    // MARK: - 6. Playback Transport Controls

    @MainActor
    func togglePlayPause() {
        if var track = currentTrack {
            track.isPlaying.toggle()
            track.timestamp = Date()
            currentTrack = track
            NowPlayingViewModel.shared.sync(with: track)
            handlePlaybackStateChange(isPlaying: track.isPlaying)
        }
        sendTransportCommand("playpause", mediaRemoteCmd: 2, mediaKey: 16)
    }

    @MainActor
    func nextTrack() {
        sendTransportCommand("next track", mediaRemoteCmd: 4, mediaKey: 17)
    }

    @MainActor
    func previousTrack() {
        sendTransportCommand("previous track", mediaRemoteCmd: 5, mediaKey: 18)
    }

    @MainActor
    func toggleFavorite(for track: NowPlayingInfo? = nil) {
        let current = track ?? currentTrack

        // Tactile feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        guard let targetTrack = current else { return }

        let targetApp = targetTrack.appName.isEmpty == false ? targetTrack.appName : lastActiveApp
        let isSpotify = targetApp.localizedCaseInsensitiveContains("spotify") ||
                        (targetApp.isEmpty && SpotifyAPIService.shared.isSpotifyRunning) ||
                        (targetTrack.trackID?.contains("spotify") == true)

        if isSpotify {
            Task {
                await SpotifyAPIService.shared.toggleFavorite(track: targetTrack)
            }
        } else if targetApp.localizedCaseInsensitiveContains("music") {
            let isNowFavorited = MediaFavoritesManager.shared.toggleFavorite(for: targetTrack)
            NowPlayingViewModel.shared.isFavorited = isNowFavorited
            toggleAppleMusicFavorite()
        } else {
            let isNowFavorited = MediaFavoritesManager.shared.toggleFavorite(for: targetTrack)
            NowPlayingViewModel.shared.isFavorited = isNowFavorited
        }
    }

    private func toggleAppleMusicFavorite() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let script = """
            tell application id "com.apple.Music"
                try
                    set favorited of current track to not (favorited of current track)
                end try
            end tell
            """
            _ = self?.runAppleScript(script)
        }
    }

    @MainActor
    func seek(to time: TimeInterval) {
        let targetTime = max(0, time)
        let targetApp = currentTrack?.appName.isEmpty == false ? currentTrack!.appName : lastActiveApp

        // 1. Optimistic UI update
        if var track = currentTrack {
            track.elapsedTime = targetTime
            track.timestamp = Date()
            currentTrack = track
            NowPlayingViewModel.shared.liveElapsedTime = targetTime
        }

        // 2. Spotify
        if targetApp == "Spotify" {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                _ = self?.runAppleScript("tell application id \"com.spotify.client\" to set player position to \(targetTime)")
            }
            return
        }

        // 3. Apple Music
        if targetApp == "Music" {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                _ = self?.runAppleScript("tell application id \"com.apple.Music\" to set player position to \(targetTime)")
            }
            return
        }

        // 4. Safari (YouTube / Web video)
        if targetApp.localizedCaseInsensitiveContains("Safari") || targetApp.localizedCaseInsensitiveContains("YouTube") {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let script = """
                tell application "Safari"
                    if (count of windows) > 0 then
                        repeat with w in windows
                            repeat with t in tabs of w
                                set tURL to URL of t
                                if tURL contains "youtube.com/watch" or tURL contains "youtu.be/" then
                                    try
                                        do JavaScript "const v = document.querySelector('video'); if (v) v.currentTime = \(targetTime);" in t
                                    end try
                                    return
                                end if
                            end repeat
                        end repeat
                    end if
                end tell
                """
                _ = self?.runAppleScript(script)
            }
        }

        // 5. Chromium browsers (Chrome, Arc, Brave, Edge) with YouTube tabs
        if targetApp.contains("Chrome") || targetApp.contains("Arc") || targetApp.contains("Brave") || targetApp.contains("Edge") {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let script = """
                tell application "\(targetApp)"
                    if (count of windows) > 0 then
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "youtube.com/watch" or URL of t contains "youtu.be/" then
                                    execute t javascript "const v = document.querySelector('video'); if (v) v.currentTime = \(targetTime);"
                                    return
                                end if
                            end repeat
                        end repeat
                    end if
                end tell
                """
                _ = self?.runAppleScript(script)
            }
        }

        // 6. MediaRemote Command 11 (kMRChangePlaybackPosition) for native system players (QuickTime, Podcasts, etc.)
        if let mrSendCommand = self.mrSendCommand {
            let options: [String: Any] = [
                "kMRMediaRemoteOptionPlaybackPosition": NSNumber(value: targetTime)
            ]
            _ = mrSendCommand(11, options)
        }
    }

    private func sendTransportCommand(_ appleScriptCmd: String, mediaRemoteCmd: UInt32, mediaKey: Int32) {
        let targetApp = currentTrack?.appName.isEmpty == false ? currentTrack!.appName : lastActiveApp
        let isSpotify = (targetApp == "Spotify")
        let isMusic = (targetApp == "Music")
        let hasSpotify = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        let hasMusic = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty

        if isSpotify && hasSpotify {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                _ = self?.runAppleScript("tell application id \"com.spotify.client\" to \(appleScriptCmd)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.syncActivePlayerPositionIfNeeded()
                }
            }
        } else if isMusic && hasMusic {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                _ = self?.runAppleScript("tell application id \"com.apple.Music\" to \(appleScriptCmd)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.syncActivePlayerPositionIfNeeded()
                }
            }
        } else {
            var sent = false
            if let mrSendCommand = self.mrSendCommand {
                sent = mrSendCommand(mediaRemoteCmd, nil)
            }
            if !sent {
                postSystemMediaKey(mediaKey)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.queryMediaRemote(isInitial: false)
            }
        }
    }

    private func postSystemMediaKey(_ key: Int32) {
        func sendKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            guard let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            ev.cgEvent?.post(tap: .cghidEventTap)
        }
        sendKey(down: true)
        sendKey(down: false)
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }

    // MARK: - App Activation / Redirection

    @MainActor
    func openActiveMediaApp(for track: NowPlayingInfo? = nil) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        let target = track ?? currentTrack
        let appName = target?.appName.trimmingCharacters(in: .whitespacesAndNewlines) ?? lastActiveApp
        let lowerName = appName.lowercased()

        // 1. Spotify (check bundle ID and name)
        if lowerName.contains("spotify") || (lowerName.isEmpty && SpotifyAPIService.shared.isSpotifyRunning) {
            activateApp(bundleIdentifier: "com.spotify.client", fallbackNames: ["Spotify"])
            return
        }

        // 2. Apple Music (Handles multilingual: "Music", "Müzik", "Musique", etc.)
        if lowerName.contains("music") || lowerName.contains("müzik") || lowerName.contains("musique") || lowerName.contains("apple music") {
            activateApp(bundleIdentifier: "com.apple.Music", fallbackNames: ["Music", "Müzik", "Musique", "Apple Music"])
            return
        }

        // 3. YouTube detection: If app or artist is YouTube, find the running browser playing media
        if isBrowserMediaTrack(target) || lowerName.contains("youtube") {
            for browserBundle in Self.browserBundleIDs {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: browserBundle).first {
                    activateRunningApp(app)
                    return
                }
            }
        }

        // 4. Known Media Players & Browsers
        let playerMappings: [(identifier: String, names: [String])] = [
            ("com.google.Chrome", ["chrome", "google chrome"]),
            ("com.apple.Safari", ["safari"]),
            ("company.thebrowser.Browser", ["arc"]),
            ("com.brave.Browser", ["brave", "brave browser"]),
            ("com.microsoft.edgemac", ["edge", "microsoft edge"]),
            ("org.mozilla.firefox", ["firefox"]),
            ("com.operasoftware.Opera", ["opera"]),
            ("com.apple.podcasts", ["podcast", "podcasts"]),
            ("com.apple.tv", ["tv", "apple tv"]),
            ("org.videolan.vlc", ["vlc"]),
            ("com.colliderli.iina", ["iina"]),
            ("com.apple.QuickTimePlayerX", ["quicktime", "quicktime player"]),
            ("com.tidal.desktop", ["tidal"]),
            ("com.deezer.deezer-desktop", ["deezer"]),
            ("com.amazon.music", ["amazon music"])
        ]

        for mapping in playerMappings {
            if mapping.names.contains(where: { lowerName.contains($0) }) {
                activateApp(bundleIdentifier: mapping.identifier, fallbackNames: mapping.names)
                return
            }
        }

        // 5. General Running Application Search (fuzzy matching)
        if !appName.isEmpty {
            let runningApps = NSWorkspace.shared.runningApplications
            if let matchedApp = runningApps.first(where: { app in
                if let loc = app.localizedName, loc.localizedCaseInsensitiveContains(appName) || appName.localizedCaseInsensitiveContains(loc) {
                    return true
                }
                if let bid = app.bundleIdentifier, bid.localizedCaseInsensitiveContains(appName) {
                    return true
                }
                return false
            }) {
                activateRunningApp(matchedApp)
                return
            }
        }

        // 6. Intelligent Fallback: Check which major player is actually running
        if SpotifyAPIService.shared.isSpotifyRunning {
            activateApp(bundleIdentifier: "com.spotify.client", fallbackNames: ["Spotify"])
        } else if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            activateApp(bundleIdentifier: "com.apple.Music", fallbackNames: ["Music", "Müzik"])
        }
    }

    private func activateApp(bundleIdentifier: String, fallbackNames: [String]) {
        // Method 1: Find existing running application by bundle identifier
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            activateRunningApp(app)
            return
        }

        // Method 2: AppleScript activation by bundle identifier
        let script = "tell application id \"\(bundleIdentifier)\" to activate"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error == nil {
                return
            }
        }

        // Method 3: Launch or activate via NSWorkspace OpenConfiguration
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return
        }

        // Method 4: Match among running applications by fallback names
        for name in fallbackNames {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                $0.localizedName?.localizedCaseInsensitiveContains(name) == true
            }) {
                activateRunningApp(app)
                return
            }
        }
    }

    private func activateRunningApp(_ app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        // Additional AppleScript raise guarantee for stubborn background panels
        if let bid = app.bundleIdentifier, !bid.isEmpty {
            DispatchQueue.global(qos: .userInteractive).async {
                let script = "tell application id \"\(bid)\" to activate"
                _ = NSAppleScript(source: script)?.executeAndReturnError(nil)
            }
        }
    }
}
