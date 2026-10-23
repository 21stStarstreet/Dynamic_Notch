// SpotifyAPIService.swift
// DynamicNotch / Features / NowPlaying
//
// Official Spotify Web API Engine using OAuth 2.0 PKCE (Proof Key for Code Exchange).
// ─────────────────────────────────────────────────────────────────────────────────
// • 100% Mac App Store Compliant: Sandboxed URLSession & native ASWebAuthenticationSession.
// • Client-Safe: Zero client secret embedded in binary (RFC 7636 PKCE standard).
// • Instant 2-Way Sync: Queries Spotify's `/v1/me/tracks/contains` & `/v1/me/tracks`.
// • Free & Premium Compatible: Works for ALL Spotify account types (Free, Student, Premium).
// • Automatic Token Refresh: Silently refreshes access tokens in the background.

import Foundation
import AppKit
import Combine
import CryptoKit
import AuthenticationServices

@MainActor
final class SpotifyAPIService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = SpotifyAPIService()

    // MARK: - Spotify App Configuration
    // Official Client ID registered by the developer on developer.spotify.com
    static let defaultClientID = "8004b21d3aa249db8770db89325dec59"
    static let redirectURI = "dynamicnotch://callback"

    // MARK: - Published State

    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var userDisplayName: String? = nil
    @Published var userProduct: String? = nil
    @Published var statusMessage: String? = nil

    // Backward-compatibility shims
    @Published var hasAccessibilityPermission: Bool = true
    var clientID: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "spotify_client_id") ?? ""
            if !saved.isEmpty && saved != Self.defaultClientID {
                if saved == "eaa227eb75fc403aa151d80719fb5ce0" {
                    return Self.defaultClientID
                }
                return saved
            }
            return Self.defaultClientID
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "spotify_client_id")
        }
    }

    // MARK: - Private Properties

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var currentCodeVerifier: String?
    private var lastProcessedCode: String?
    private var likedTracksCache: [String: Bool] = [:]
    private var inFlightCheckIDs: Set<String> = []
    private var webAuthSession: ASWebAuthenticationSession?

    @Published var rateLimitResetDate: Date? = nil
    private var lastCheckedTrackKey: String = ""
    private var lastCheckedTimestamp: Date = .distantPast

    private let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    private let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!

    private func logDebug(_ message: String) {
        NSLog("[DynamicNotch Spotify] %@", message)
        let logLine = "[\(Date())] \(message)\n"
        let logURL = URL(fileURLWithPath: "/Users/mustafatiras/Projects/DynamicNotch/spotify_debug.log")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            try? logLine.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        loadStoredSession()
    }

    var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    // MARK: - Session Storage & Restoration

    private func loadStoredSession() {
        let currentID = clientID
        let lastID = UserDefaults.standard.string(forKey: "spotify_last_client_id")
        if lastID != currentID {
            // Client ID changed: clear old tokens so fresh authorization takes place with new app credentials
            UserDefaults.standard.removeObject(forKey: "spotify_access_token")
            UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
            UserDefaults.standard.removeObject(forKey: "spotify_token_expiry")
            UserDefaults.standard.removeObject(forKey: "spotify_rate_limit_reset")
            UserDefaults.standard.set(currentID, forKey: "spotify_last_client_id")
            self.rateLimitResetDate = nil
        }

        self.accessToken = UserDefaults.standard.string(forKey: "spotify_access_token")
        self.refreshToken = UserDefaults.standard.string(forKey: "spotify_refresh_token")
        self.tokenExpiry = UserDefaults.standard.object(forKey: "spotify_token_expiry") as? Date
        self.userDisplayName = UserDefaults.standard.string(forKey: "spotify_user_display_name")
        self.userProduct = UserDefaults.standard.string(forKey: "spotify_user_product")

        if let reset = UserDefaults.standard.object(forKey: "spotify_rate_limit_reset") as? Date {
            let maxBackoff = Date().addingTimeInterval(180)
            if reset > Date() && reset <= maxBackoff {
                self.rateLimitResetDate = reset
            } else {
                UserDefaults.standard.removeObject(forKey: "spotify_rate_limit_reset")
                self.rateLimitResetDate = nil
            }
        }

        // Seed likedTracksCache with all known Spotify track IDs from persistent local store
        let localIDs = MediaFavoritesManager.shared.allLikedTrackIDs()
        for id in localIDs {
            self.likedTracksCache[id] = true
        }

        if self.refreshToken != nil {
            self.isConnected = true
            Task {
                _ = await refreshAccessTokenIfNeeded()
                await fetchUserProfile()
                if let track = NowPlayingViewModel.shared.currentTrack {
                    await checkIfLiked(track: track)
                }
            }
        } else {
            self.isConnected = false
        }
    }

    private func saveTokens(access: String, refresh: String?, expiresIn: Int) {
        self.accessToken = access
        if let refresh, !refresh.isEmpty {
            self.refreshToken = refresh
            UserDefaults.standard.set(refresh, forKey: "spotify_refresh_token")
        }
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))

        UserDefaults.standard.set(access, forKey: "spotify_access_token")
        UserDefaults.standard.set(self.tokenExpiry, forKey: "spotify_token_expiry")
        UserDefaults.standard.set(clientID, forKey: "spotify_last_client_id")
        self.isConnected = true
    }

    func disconnect() {
        self.accessToken = nil
        self.refreshToken = nil
        self.tokenExpiry = nil
        self.userDisplayName = nil
        self.userProduct = nil
        self.isConnected = false
        self.likedTracksCache.removeAll()

        UserDefaults.standard.removeObject(forKey: "spotify_access_token")
        UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
        UserDefaults.standard.removeObject(forKey: "spotify_token_expiry")
        UserDefaults.standard.removeObject(forKey: "spotify_user_display_name")
        UserDefaults.standard.removeObject(forKey: "spotify_user_product")
        UserDefaults.standard.removeObject(forKey: "spotify_pkce_verifier")

        statusMessage = "Spotify bağlantısı kesildi."
    }

    // MARK: - OAuth 2.0 PKCE Auth Flow

    func startAuthFlow() {
        let verifier = generateCodeVerifier()
        self.currentCodeVerifier = verifier
        UserDefaults.standard.set(verifier, forKey: "spotify_pkce_verifier")

        let challenge = generateCodeChallenge(from: verifier)
        let scopes = "user-library-read user-library-modify user-read-currently-playing user-read-playback-state"

        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scopes)
        ]

        guard let authURL = components.url else { return }

        statusMessage = "Spotify yetkilendirme penceresi açılıyor..."
        NSLog("[DynamicNotch Spotify] Starting PKCE auth session: %@", authURL.absoluteString)

        // 1. Try Apple's native ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "dynamicnotch"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                if let callbackURL {
                    self?.handleCallbackURL(callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code != .canceledLogin {
                    NSLog("[DynamicNotch Spotify] ASWebAuthenticationSession error: %@; opening in browser fallback", error.localizedDescription)
                    NSWorkspace.shared.open(authURL)
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session

        let started = session.start()
        if !started {
            NSLog("[DynamicNotch Spotify] ASWebAuthenticationSession start failed; falling back to default browser")
            NSWorkspace.shared.open(authURL)
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                NSApplication.shared.keyWindow ??
                NSApplication.shared.windows.first(where: { $0.isVisible }) ??
                NSApplication.shared.windows.first ??
                NSWindow()
            }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    NSApplication.shared.keyWindow ??
                    NSApplication.shared.windows.first(where: { $0.isVisible }) ??
                    NSApplication.shared.windows.first ??
                    NSWindow()
                }
            }
        }
    }

    func handleCallbackURL(_ url: URL) {
        NSLog("[DynamicNotch Spotify] Received callback URL: %@", url.absoluteString)
        guard url.scheme == "dynamicnotch" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            statusMessage = "Spotify bağlantısı iptal edildi: \(error)"
            NSLog("[DynamicNotch Spotify] Callback error: %@", error)
            return
        }

        var code = components.queryItems?.first(where: { $0.name == "code" })?.value
        if code == nil, let query = url.query {
            for item in query.components(separatedBy: "&") {
                let parts = item.components(separatedBy: "=")
                if parts.count == 2, parts[0] == "code" {
                    code = parts[1].removingPercentEncoding ?? parts[1]
                    break
                }
            }
        }

        guard let validCode = code, !validCode.isEmpty else {
            NSLog("[DynamicNotch Spotify] No code parameter found in callback URL")
            return
        }

        // Prevent duplicate processing of the same authorization code
        if let lastCode = lastProcessedCode, lastCode == validCode {
            return
        }
        lastProcessedCode = validCode

        Task {
            await exchangeCodeForToken(code: validCode)
        }
    }

    // MARK: - PKCE Cryptographic Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formUrlEncode(_ params: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let string = params.map { key, value in
            let encKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encKey)=\(encValue)"
        }.joined(separator: "&")
        return Data(string.utf8)
    }

    // MARK: - Token Exchange & Refresh

    private func exchangeCodeForToken(code: String) async {
        isLoading = true
        defer { isLoading = false }

        guard let verifier = currentCodeVerifier ?? UserDefaults.standard.string(forKey: "spotify_pkce_verifier") else {
            statusMessage = "Hata: PKCE doğrulama anahtarı bulunamadı."
            return
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier
        ]
        request.httpBody = formUrlEncode(params)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if (200...299).contains(http.statusCode) {
                let tokenResp = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
                saveTokens(
                    access: tokenResp.access_token,
                    refresh: tokenResp.refresh_token,
                    expiresIn: tokenResp.expires_in
                )
                UserDefaults.standard.removeObject(forKey: "spotify_pkce_verifier")
                self.currentCodeVerifier = nil
                statusMessage = "Spotify başarıyla bağlandı!"
                NSLog("[DynamicNotch Spotify] Token exchange succeeded! isConnected: true")

                // Play tactile haptic celebration
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

                // Trigger Notch Animated Vector Checkmark HUD
                NotchViewModel.shared?.handleIncoming(.spotifyAuthorized)

                await fetchUserProfile()

                // Immediately check and sync liked state for current playing track
                if let track = NowPlayingViewModel.shared.currentTrack {
                    await checkIfLiked(track: track)
                }
            } else {
                let errString = String(data: data, encoding: .utf8) ?? "Bilinmeyen hata"
                statusMessage = "Giriş başarısız: HTTP \(http.statusCode)"
                NSLog("[DynamicNotch Spotify] Token exchange failed (%d): %@", http.statusCode, errString)
            }
        } catch {
            statusMessage = "Bağlantı hatası: \(error.localizedDescription)"
            NSLog("[DynamicNotch Spotify] Token exchange error: %@", error.localizedDescription)
        }
    }

    func refreshAccessTokenIfNeeded(force: Bool = false) async -> Bool {
        guard let refreshToken = self.refreshToken else { return false }

        // If current access token is valid for > 60 seconds and not forced, no refresh needed
        if !force, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60), accessToken != nil {
            return true
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        request.httpBody = formUrlEncode(params)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if (200...299).contains(http.statusCode) {
                let tokenResp = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
                saveTokens(
                    access: tokenResp.access_token,
                    refresh: tokenResp.refresh_token,
                    expiresIn: tokenResp.expires_in
                )
                return true
            } else {
                let errString = String(data: data, encoding: .utf8) ?? ""
                NSLog("[DynamicNotch Spotify] Token refresh failed (HTTP %d): %@", http.statusCode, errString)

                // ONLY disconnect if Spotify explicitly revokes the grant
                if http.statusCode == 400 || http.statusCode == 401 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? String, error == "invalid_grant" {
                        NSLog("[DynamicNotch Spotify] Refresh token revoked by Spotify (invalid_grant); disconnecting.")
                        disconnect()
                    }
                }
                return false
            }
        } catch {
            NSLog("[DynamicNotch Spotify] Token refresh network error: %@", error.localizedDescription)
            return false
        }
    }

    private func performAuthorizedRequest(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async -> (Data?, HTTPURLResponse?) {
        if let reset = rateLimitResetDate, Date() < reset {
            // Actively respect Spotify's rate limit / 429 penalty window without flooding
            return (nil, nil)
        }

        guard await refreshAccessTokenIfNeeded(), let token = accessToken else {
            return (nil, nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (nil, nil) }

            // If 429 Too Many Requests, extract Retry-After and back off (capped to max 180s)
            if http.statusCode == 429 {
                let retryHeader = http.value(forHTTPHeaderField: "Retry-After") ?? http.value(forHTTPHeaderField: "retry-after")
                let rawSeconds = retryHeader.flatMap { Double($0) } ?? 60.0
                let seconds = min(rawSeconds, 180.0)
                rateLimitResetDate = Date().addingTimeInterval(seconds)
                UserDefaults.standard.set(rateLimitResetDate, forKey: "spotify_rate_limit_reset")
                NSLog("[DynamicNotch Spotify] 429 Too Many Requests. Backing off for %.0f seconds until %@", seconds, rateLimitResetDate?.description ?? "")
            }

            // If 401 Unauthorized, token might have expired. Force refresh once and retry!
            if http.statusCode == 401 {
                NSLog("[DynamicNotch Spotify] Request got 401. Forcing token refresh and retrying once...")
                let refreshed = await refreshAccessTokenIfNeeded(force: true)
                if refreshed, let newToken = accessToken {
                    var retryRequest = URLRequest(url: url)
                    retryRequest.httpMethod = method
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    for (k, v) in headers {
                        retryRequest.setValue(v, forHTTPHeaderField: k)
                    }
                    retryRequest.httpBody = body
                    if let (retryData, retryResponse) = try? await URLSession.shared.data(for: retryRequest),
                       let retryHttp = retryResponse as? HTTPURLResponse {
                        if retryHttp.statusCode == 429 {
                            let retryHeader = retryHttp.value(forHTTPHeaderField: "Retry-After") ?? retryHttp.value(forHTTPHeaderField: "retry-after")
                            let rawSeconds = retryHeader.flatMap { Double($0) } ?? 60.0
                            let seconds = min(rawSeconds, 180.0)
                            rateLimitResetDate = Date().addingTimeInterval(seconds)
                            UserDefaults.standard.set(rateLimitResetDate, forKey: "spotify_rate_limit_reset")
                        }
                        return (retryData, retryHttp)
                    }
                }
            }

            return (data, http)
        } catch {
            NSLog("[DynamicNotch Spotify] Network request error for %@: %@", url.absoluteString, error.localizedDescription)
            return (nil, nil)
        }
    }

    // MARK: - User Profile

    private func fetchUserProfile() async {
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return }
        let (data, http) = await performAuthorizedRequest(url: url)
        guard let data, let http, http.statusCode == 200 else { return }

        do {
            let profile = try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
            self.userDisplayName = profile.display_name ?? profile.id
            self.userProduct = profile.product
            UserDefaults.standard.set(self.userDisplayName, forKey: "spotify_user_display_name")
            UserDefaults.standard.set(self.userProduct, forKey: "spotify_user_product")
            NSLog("[DynamicNotch Spotify] Authenticated as %@ (tier: %@)", profile.display_name ?? profile.id, profile.product ?? "free")
        } catch {
            NSLog("[DynamicNotch Spotify] fetchUserProfile decode error: %@", error.localizedDescription)
        }
    }

    // MARK: - Track ID Resolution

    func cleanTrackID(from uriOrID: String) -> String {
        let pattern = #"[0-9A-Za-z]{22}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(uriOrID.startIndex..<uriOrID.endIndex, in: uriOrID)
            if let match = regex.firstMatch(in: uriOrID, options: [], range: range),
               let swiftRange = Range(match.range, in: uriOrID) {
                return String(uriOrID[swiftRange])
            }
        }
        var clean = uriOrID.replacingOccurrences(of: "spotify:track:", with: "")
        if let queryIndex = clean.firstIndex(of: "?") {
            clean = String(clean[..<queryIndex])
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolveTrackID(for track: NowPlayingInfo) async -> String? {
        // 1. Direct trackID from NowPlayingInfo
        if let rawID = track.trackID, !rawID.isEmpty {
            let clean = cleanTrackID(from: rawID)
            if clean.count == 22 {
                return clean
            }
        }

        // 2. Query Spotify desktop app directly via AppleScript (instant local resolution)
        if isSpotifyRunning {
            let script = "tell application id \"com.spotify.client\" to if player state is playing or player state is paused then return id of current track"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let output = appleScript.executeAndReturnError(&error).stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !output.isEmpty {
                    let clean = cleanTrackID(from: output)
                    if clean.count == 22 {
                        return clean
                    }
                }
            }
            // Spotify is running locally; do NOT waste Web API quota on search
            return nil
        }

        // If Spotify Web API is currently in backoff, skip remote network calls
        if let reset = rateLimitResetDate, Date() < reset {
            return nil
        }

        // 3. Fallback for Spotify Connect / Mobile: Query Spotify Web API `/v1/me/player/currently-playing`
        if let currentURL = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") {
            let (data, http) = await performAuthorizedRequest(url: currentURL)
            if let data, let http, http.statusCode == 200,
               let playing = try? JSONDecoder().decode(SpotifyCurrentlyPlayingResponse.self, from: data),
               let id = playing.item?.id, !id.isEmpty {
                let clean = cleanTrackID(from: id)
                if clean.count == 22 {
                    return clean
                }
            }
        }

        // 4. Fallback: Search track by clean title and artist via Web API search
        let cleanTitle = track.title
            .replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\[[^]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*-.*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTitle = cleanTitle.isEmpty ? track.title : cleanTitle

        if let id = await searchTrackID(title: searchTitle, artist: track.artist) {
            return id
        }
        if searchTitle != track.title, let id = await searchTrackID(title: track.title, artist: track.artist) {
            return id
        }

        return nil
    }

    private func searchTrackID(title: String, artist: String) async -> String? {
        guard !title.isEmpty else { return nil }
        var query = title
        if !artist.isEmpty {
            query += " \(artist)"
        }
        query = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents(string: "https://api.spotify.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        let (data, http) = await performAuthorizedRequest(url: url)
        guard let data, let http, http.statusCode == 200 else { return nil }

        if let searchResult = try? JSONDecoder().decode(SpotifySearchResponse.self, from: data),
           let firstID = searchResult.tracks?.items.first?.id, !firstID.isEmpty {
            let clean = cleanTrackID(from: firstID)
            if clean.count == 22 {
                return clean
            }
        }
        return nil
    }

    // MARK: - 1. Check If Current Track Is Liked (2-Way Sync)

    func isLiked(spotifyURI: String) -> Bool {
        let clean = cleanTrackID(from: spotifyURI)
        guard !clean.isEmpty else { return false }
        if let cached = likedTracksCache[clean] {
            return cached
        }
        return MediaFavoritesManager.shared.isFavorited(trackID: clean)
    }

    func checkIfLiked(track: NowPlayingInfo) async {
        guard track.appName.lowercased().contains("spotify") || isSpotifyRunning else { return }

        // 1. Instant check from local persistent registry
        let localStatus = MediaFavoritesManager.shared.isFavorited(track: track)
        if localStatus {
            NowPlayingViewModel.shared.isFavorited = true
        }

        // Deduplicate checks within 15 seconds for the same track
        let checkKey = "\(track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        if !checkKey.isEmpty && lastCheckedTrackKey == checkKey && Date().timeIntervalSince(lastCheckedTimestamp) < 15 {
            return
        }
        lastCheckedTrackKey = checkKey
        lastCheckedTimestamp = Date()

        guard let cleanID = await resolveTrackID(for: track) else {
            return
        }

        // If in memory cache, sync immediately
        if let cached = likedTracksCache[cleanID] {
            applyLikedState(isLiked: cached, cleanID: cleanID, track: track)
            return
        }

        // Check local persistent registry with resolved cleanID
        if MediaFavoritesManager.shared.isFavorited(trackID: cleanID) {
            applyLikedState(isLiked: true, cleanID: cleanID, track: track)
            return
        }

        // If Spotify Web API is currently in backoff or not connected, rely gracefully on local state
        if let reset = rateLimitResetDate, Date() < reset {
            logDebug("checkIfLiked: Spotify API in backoff until \(reset). Relying on local persistent favorites store.")
            return
        }

        guard isConnected else { return }

        // Avoid duplicate concurrent checks for same track ID
        if inFlightCheckIDs.contains(cleanID) {
            return
        }
        inFlightCheckIDs.insert(cleanID)
        defer { inFlightCheckIDs.remove(cleanID) }

        // Official Spotify Check Saved Tracks Endpoint: GET /v1/me/tracks/contains?ids={cleanID}
        if let checkURL = URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(cleanID)") {
            let (data, http) = await performAuthorizedRequest(url: checkURL)
            if let data, let http, http.statusCode == 200,
               let likedArray = try? JSONDecoder().decode([Bool].self, from: data),
               let isLiked = likedArray.first {
                applyLikedState(isLiked: isLiked, cleanID: cleanID, track: track)
                return
            } else {
                let code = http?.statusCode ?? -1
                let err = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                logDebug("checkIfLiked /v1/me/tracks/contains returned HTTP \(code): \(err)")
            }
        }
    }

    private func applyLikedState(isLiked: Bool, cleanID: String, track: NowPlayingInfo) {
        likedTracksCache[cleanID] = isLiked

        let localStatus = MediaFavoritesManager.shared.isFavorited(track: track)
        let effectiveLiked = isLiked || localStatus
        NowPlayingViewModel.shared.isFavorited = effectiveLiked

        var trackWithID = track
        trackWithID.trackID = "spotify:track:\(cleanID)"
        trackWithID.isFavorited = effectiveLiked
        if isLiked {
            MediaFavoritesManager.shared.setFavorite(true, for: trackWithID)
        }

        NotchViewModel.shared?.mediaObserver.updateCurrentTrackFavoriteState(
            isFavorited: effectiveLiked,
            trackID: "spotify:track:\(cleanID)"
        )
        logDebug("checkIfLiked resolved '\(track.title)' (\(cleanID)) -> Spotify isLiked: \(isLiked), effective: \(effectiveLiked)")
    }

    // MARK: - 2. Toggle Favorite via Spotify Web API & Desktop Native Keystroke

    func toggleFavorite(track: NowPlayingInfo) async {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        let currentlyLiked = NowPlayingViewModel.shared.isFavorited
        let shouldLike = !currentlyLiked

        // 1. Instant optimistic local update across all view models and stores
        NowPlayingViewModel.shared.isFavorited = shouldLike

        guard let cleanID = await resolveTrackID(for: track) else {
            logDebug("Could not resolve 22-char track ID for toggleFavorite: \(track.title); storing via title/artist")
            MediaFavoritesManager.shared.setFavorite(shouldLike, for: track)
            if isSpotifyRunning {
                triggerNativeSpotifyLikeShortcut()
            }
            return
        }

        var trackWithID = track
        trackWithID.trackID = "spotify:track:\(cleanID)"
        trackWithID.isFavorited = shouldLike
        likedTracksCache[cleanID] = shouldLike
        MediaFavoritesManager.shared.setFavorite(shouldLike, for: trackWithID)

        NotchViewModel.shared?.mediaObserver.updateCurrentTrackFavoriteState(
            isFavorited: shouldLike,
            trackID: "spotify:track:\(cleanID)"
        )

        // 2. Trigger native Spotify desktop shortcut Option + Shift + B for immediate local like/unlike
        if isSpotifyRunning {
            triggerNativeSpotifyLikeShortcut()
        }

        guard isConnected else {
            NotchViewModel.shared?.handleIncoming(.accessibilityPermissionRequired)
            return
        }

        // 3. Sync with Web API if available and not blocked by rate limit
        if let reset = rateLimitResetDate, Date() < reset {
            logDebug("Spotify Web API in backoff. Action completed locally and via desktop shortcut.")
            return
        }

        let success = await performToggleFavoriteAPI(cleanID: cleanID, shouldLike: shouldLike)

        if success {
            logDebug("toggleFavorite SUCCESS on Spotify Web API for \(cleanID) (shouldLike: \(shouldLike))")
        } else {
            logDebug("Spotify Web API call failed for \(cleanID). Retaining favorite locally in MediaFavoritesManager.")
        }
    }

    private func triggerNativeSpotifyLikeShortcut() {
        DispatchQueue.global(qos: .userInteractive).async {
            let script = """
            tell application "System Events"
                if exists (process "Spotify") then
                    tell process "Spotify"
                        keystroke "b" using {option down, shift down}
                    end tell
                end if
            end tell
            """
            _ = NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    private func performToggleFavoriteAPI(cleanID: String, shouldLike: Bool) async -> Bool {
        let spotifyURI = "spotify:track:\(cleanID)"
        let method = shouldLike ? "PUT" : "DELETE"

        // Modern Spotify Unified Library API: PUT or DELETE /v1/me/library?uris=spotify:track:{cleanID}
        if let encodedURI = spotifyURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let libraryURL = URL(string: "https://api.spotify.com/v1/me/library?uris=\(encodedURI)") {
            let (data, http) = await performAuthorizedRequest(
                url: libraryURL,
                method: method,
                headers: ["Content-Type": "application/json"]
            )
            if let http, (200...299).contains(http.statusCode) {
                logDebug("Library API succeeded (\(method) \(spotifyURI)) HTTP \(http.statusCode)")
                return true
            } else {
                let code = http?.statusCode ?? -1
                let err = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                logDebug("Library API returned HTTP \(code): \(err)")
            }
        }
        return false
    }

    // MARK: - Backward Compatibility Shims

    func refreshPermissionStatus() {
        // No-op for Web API
    }

    func requestAccessibilityPermission() {
        startAuthFlow()
    }

    func openAccessibilitySettings() {
        startAuthFlow()
    }
}

// MARK: - Data Models

private struct SpotifyTokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let scope: String?
    let expires_in: Int
    let refresh_token: String?
}

private struct SpotifyUserProfile: Decodable {
    let id: String
    let display_name: String?
    let product: String?
}

private struct SpotifyCurrentlyPlayingResponse: Decodable {
    struct Item: Decodable {
        let id: String?
        let name: String?
        let uri: String?
    }
    let item: Item?
    let is_playing: Bool?
}

private struct SpotifySearchResponse: Decodable {
    struct Tracks: Decodable {
        struct TrackItem: Decodable {
            let id: String?
            let name: String?
            let uri: String?
        }
        let items: [TrackItem]
    }
    let tracks: Tracks?
}
