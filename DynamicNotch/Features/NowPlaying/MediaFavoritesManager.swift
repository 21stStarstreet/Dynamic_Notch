// MediaFavoritesManager.swift
// DynamicNotch / Features / NowPlaying
//
// Persistent favorites registry and state manager for Spotify & Apple Music tracks.

import Foundation

final class MediaFavoritesManager: @unchecked Sendable {

    static let shared = MediaFavoritesManager()

    private let userDefaultsKey = "DynamicNotch_LikedTracks"
    private let queue = DispatchQueue(label: "com.dynamicnotch.mediafavorites", attributes: .concurrent)
    private var likedTrackKeys: Set<String> = []

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            likedTrackKeys = Set(saved)
        }
    }

    /// Generates normalized unique keys for a track using artist and title.
    func titleArtistKeys(for track: NowPlayingInfo) -> [String] {
        let cleanArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanTitle.isEmpty else { return [] }

        var app = track.appName.lowercased()
        if app.contains("spotify") {
            app = "spotify"
        } else if app.contains("music") {
            app = "music"
        }

        var titles = Set<String>([cleanTitle])
        // Remove remaster, feat, ft, with, live, demo, slowed, etc.
        let strippedTitle = cleanTitle
            .replacingOccurrences(of: #"\s*[\(\[](remaster(ed)?|feat\.?|ft\.?|with|official|demo|live|slowed|reverb|radio edit).*?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*-\s*(remaster(ed)?|radio edit|bonus track|live|demo|slowed|reverb).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !strippedTitle.isEmpty {
            titles.insert(strippedTitle)
        }

        var artists = Set<String>([cleanArtist])
        let primaryArtist = cleanArtist
            .components(separatedBy: CharacterSet(charactersIn: ",/&"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? cleanArtist
        if !primaryArtist.isEmpty {
            artists.insert(primaryArtist)
        }

        var keys = [String]()
        for a in artists {
            for t in titles {
                if !app.isEmpty {
                    keys.append("\(app)::\(a)::\(t)")
                }
                keys.append("any::\(a)::\(t)")
            }
        }
        return keys
    }

    /// Returns all known 22-character Spotify track IDs stored in the favorites database.
    func allLikedTrackIDs() -> Set<String> {
        return queue.sync {
            var ids = Set<String>()
            let pattern = #"[0-9A-Za-z]{22}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return ids }
            for key in likedTrackKeys {
                let range = NSRange(key.startIndex..<key.endIndex, in: key)
                if let match = regex.firstMatch(in: key, options: [], range: range),
                   let swiftRange = Range(match.range, in: key) {
                    ids.insert(String(key[swiftRange]))
                }
            }
            return ids
        }
    }

    private func extractIDVariants(from rawID: String?) -> [String] {
        guard let rawID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawID.isEmpty else {
            return []
        }
        var variants = [rawID]
        let pattern = #"[0-9A-Za-z]{22}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(rawID.startIndex..<rawID.endIndex, in: rawID)
            if let match = regex.firstMatch(in: rawID, options: [], range: range),
               let swiftRange = Range(match.range, in: rawID) {
                let clean = String(rawID[swiftRange])
                variants.append(clean)
                variants.append("spotify:track:\(clean)")
            }
        }
        return Array(Set(variants))
    }

    /// Checks if a Spotify or custom track ID is marked as favorited in the persistent store.
    func isFavorited(trackID: String) -> Bool {
        let idVariants = extractIDVariants(from: trackID)
        guard !idVariants.isEmpty else { return false }
        return queue.sync {
            for variant in idVariants {
                if likedTrackKeys.contains(variant) {
                    return true
                }
            }
            return false
        }
    }

    /// Checks if the track is marked as favorited in the persistent store.
    func isFavorited(track: NowPlayingInfo) -> Bool {
        // 1. First priority: Check exact track ID match if available
        if let tid = track.trackID, !tid.isEmpty, isFavorited(trackID: tid) {
            return true
        }

        // 2. Second priority: Normalized Title & Artist keys
        guard !track.title.isEmpty else { return false }
        let titleKeys = titleArtistKeys(for: track)

        return queue.sync {
            for key in titleKeys {
                if likedTrackKeys.contains(key) {
                    return true
                }
            }
            return false
        }
    }

    /// Toggles the favorite status for a track and persists it to UserDefaults.
    @discardableResult
    func toggleFavorite(for track: NowPlayingInfo) -> Bool {
        let currentlyLiked = isFavorited(track: track)
        let targetState = !currentlyLiked
        setFavorite(targetState, for: track)
        return targetState
    }

    /// Sets explicit favorite status for a track.
    func setFavorite(_ favorited: Bool, for track: NowPlayingInfo) {
        let titleKeys = titleArtistKeys(for: track)
        let idVariants = extractIDVariants(from: track.trackID)
        guard !titleKeys.isEmpty || !idVariants.isEmpty else { return }

        queue.sync(flags: .barrier) {
            if favorited {
                for key in titleKeys {
                    likedTrackKeys.insert(key)
                }
                for variant in idVariants {
                    likedTrackKeys.insert(variant)
                }
            } else {
                for key in titleKeys {
                    likedTrackKeys.remove(key)
                }
                for variant in idVariants {
                    likedTrackKeys.remove(variant)
                }
            }
            UserDefaults.standard.set(Array(likedTrackKeys), forKey: userDefaultsKey)
        }
    }
}
