// LyricsService.swift
// DynamicNotch / Services
//
// High-performance asynchronous lyrics engine fetching synchronized (LRC)
// and plain lyrics from LRCLIB and fallback providers with in-memory caching.

import Foundation

final class LyricsService {

    static let shared = LyricsService()

    // MARK: - In-Memory Cache Wrapper

    private final class CachedLyrics {
        let lyrics: TrackLyrics?
        init(_ lyrics: TrackLyrics?) {
            self.lyrics = lyrics
        }
    }

    private let cache = NSCache<NSString, CachedLyrics>()
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 12.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)

        cache.countLimit = 120
    }

    // MARK: - Public API

    /// Fetches synchronized or plain lyrics for the given track info.
    /// Returns cached results instantly if available; otherwise queries LRCLIB and fallbacks asynchronously.
    func fetchLyrics(
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 0
    ) async -> TrackLyrics? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else { return nil }

        let cacheKey = makeCacheKey(title: cleanTitle, artist: cleanArtist)
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached.lyrics
        }

        var plainFallback: TrackLyrics? = nil

        // 1. Attempt exact match on LRCLIB
        if let lyrics = await fetchFromLRCLIBExact(title: cleanTitle, artist: cleanArtist, album: album, duration: duration) {
            if lyrics.isSynced && !lyrics.lines.isEmpty {
                cache.setObject(CachedLyrics(lyrics), forKey: cacheKey as NSString)
                return lyrics
            }
            plainFallback = lyrics
        }

        // 2. Attempt cleaned/sanitized query on LRCLIB
        let (sanitizedTitle, sanitizedArtist) = sanitizeTitleAndArtist(title: cleanTitle, artist: cleanArtist)
        if sanitizedTitle != cleanTitle || sanitizedArtist != cleanArtist {
            if let lyrics = await fetchFromLRCLIBExact(title: sanitizedTitle, artist: sanitizedArtist, album: album, duration: duration) {
                if lyrics.isSynced && !lyrics.lines.isEmpty {
                    cache.setObject(CachedLyrics(lyrics), forKey: cacheKey as NSString)
                    return lyrics
                }
                if plainFallback == nil {
                    plainFallback = lyrics
                }
            }
        }

        // 3. Attempt fuzzy search on LRCLIB (always prioritizes records with syncedLyrics!)
        let searchQuery = "\(sanitizedTitle) \(sanitizedArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
        if let lyrics = await fetchFromLRCLIBSearch(query: searchQuery, originalTitle: cleanTitle, originalArtist: cleanArtist) {
            if lyrics.isSynced && !lyrics.lines.isEmpty {
                cache.setObject(CachedLyrics(lyrics), forKey: cacheKey as NSString)
                return lyrics
            }
            if plainFallback == nil {
                plainFallback = lyrics
            }
        }

        // 4. If any LRCLIB step produced a plain lyrics fallback, return it now
        if let plain = plainFallback, plain.hasLyrics {
            cache.setObject(CachedLyrics(plain), forKey: cacheKey as NSString)
            return plain
        }

        // 5. Secondary fallback: Lyrics.ovh for plain lyrics
        if let plainText = await fetchFromLyricsOVH(title: sanitizedTitle, artist: sanitizedArtist) {
            let lyrics = TrackLyrics(
                trackTitle: cleanTitle,
                artistName: cleanArtist,
                lines: [],
                isSynced: false,
                plainLyrics: plainText
            )
            cache.setObject(CachedLyrics(lyrics), forKey: cacheKey as NSString)
            return lyrics
        }

        // Cache the empty result for 60 seconds to avoid repeating failed network requests
        cache.setObject(CachedLyrics(nil), forKey: cacheKey as NSString)
        return nil
    }

    // MARK: - LRCLIB Providers

    private struct LRCLIBRecord: Decodable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private func fetchFromLRCLIBExact(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> TrackLyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 10 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("DynamicNotch/\(AppConfig.version) (https://github.com/mustafatiras/DynamicNotch)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let record = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
            return buildTrackLyrics(from: record, title: title, artist: artist)
        } catch {
            return nil
        }
    }

    private func fetchFromLRCLIBSearch(
        query: String,
        originalTitle: String,
        originalArtist: String
    ) async -> TrackLyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("DynamicNotch/\(AppConfig.version) (https://github.com/mustafatiras/DynamicNotch)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)

            // Prefer first match that has syncedLyrics; otherwise first that has plainLyrics
            if let bestSynced = records.first(where: { ($0.syncedLyrics?.isEmpty == false) }) {
                return buildTrackLyrics(from: bestSynced, title: originalTitle, artist: originalArtist)
            } else if let bestPlain = records.first(where: { ($0.plainLyrics?.isEmpty == false) }) {
                return buildTrackLyrics(from: bestPlain, title: originalTitle, artist: originalArtist)
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Lyrics.ovh Backup Provider

    private struct LyricsOVHResponse: Decodable {
        let lyrics: String?
    }

    private func fetchFromLyricsOVH(title: String, artist: String) async -> String? {
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("DynamicNotch/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let record = try JSONDecoder().decode(LyricsOVHResponse.self, from: data)
            return record.lyrics
        } catch {
            return nil
        }
    }

    // MARK: - LRC Parser Engine

    func parseLRC(rawContent: String) -> [LyricLine] {
        var lines: [LyricLine] = []

        // Matches [mm:ss.xx], [mm:ss.xxx], [m:ss.xx], [mm:ss]
        // Group 1: Minutes, Group 2: Seconds, Group 3: Subseconds/Milliseconds (optional), Group 4: Text
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let rawLines = rawContent.components(separatedBy: .newlines)

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let nsString = trimmed as NSString
            let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }

                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))

                let minutes = Double(minStr) ?? 0.0
                let seconds = Double(secStr) ?? 0.0

                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let fracStr = nsString.substring(with: match.range(at: 3))
                    if let rawFrac = Double(fracStr) {
                        fraction = rawFrac / pow(10.0, Double(fracStr.count))
                    }
                }

                let timestamp = (minutes * 60.0) + seconds + fraction

                var text = ""
                if match.numberOfRanges >= 5 && match.range(at: 4).location != NSNotFound {
                    text = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                }

                // Check for instrumental markers
                let isInstrumental = text.isEmpty || text == "♪" || text.lowercased().contains("instrumental")

                lines.append(LyricLine(
                    timestamp: timestamp,
                    text: text,
                    isInstrumental: isInstrumental
                ))
            }
        }

        return lines.sorted(by: { $0.timestamp < $1.timestamp })
    }

    private func buildTrackLyrics(from record: LRCLIBRecord, title: String, artist: String) -> TrackLyrics {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let parsedLines = parseLRC(rawContent: synced)
            if !parsedLines.isEmpty {
                return TrackLyrics(
                    trackTitle: title,
                    artistName: artist,
                    lines: parsedLines,
                    isSynced: true,
                    plainLyrics: record.plainLyrics
                )
            }
        }

        return TrackLyrics(
            trackTitle: title,
            artistName: artist,
            lines: [],
            isSynced: false,
            plainLyrics: record.plainLyrics
        )
    }

    // MARK: - Sanitization & Key Utilities

    private func makeCacheKey(title: String, artist: String) -> String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    private func sanitizeTitleAndArtist(title: String, artist: String) -> (String, String) {
        var cleanTitle = title

        // Remove typical stream/metadata suffixes that break exact search
        let patterns = [
            #" - Remastered.*$"#,
            #" - \d{4} Remaster.*$"#,
            #" \(Remastered.*\)"#,
            #" \[Remastered.*\]"#,
            #" - Single Version.*$"#,
            #" - Deluxe Edition.*$"#,
            #" - Bonus Track.*$"#,
            #" - Live.*$"#,
            #" \(Live.*\)"#,
            #" \(feat\..*?\)"#,
            #" \[feat\..*?\]"#,
            #" \(with.*?\)"#,
            #" \[with.*?\]"#
        ]

        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: cleanTitle.utf16.count)
                cleanTitle = regex.stringByReplacingMatches(in: cleanTitle, options: [], range: range, withTemplate: "")
            }
        }

        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleanTitle.isEmpty ? title : cleanTitle, artist)
    }
}
