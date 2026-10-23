// LyricsModel.swift
// DynamicNotch / Models
//
// Immutable value types for Synchronized (LRC) and Plain lyrics in DynamicNotch.

import Foundation

// MARK: - Single Lyric Line

struct LyricLine: Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: TimeInterval // Playback position in seconds
    let text: String
    let isInstrumental: Bool

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        text: String,
        isInstrumental: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isInstrumental = isInstrumental
    }

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.id == rhs.id &&
        abs(lhs.timestamp - rhs.timestamp) < 0.01 &&
        lhs.text == rhs.text &&
        lhs.isInstrumental == rhs.isInstrumental
    }
}

// MARK: - Track Lyrics Container

struct TrackLyrics: Equatable {
    let trackTitle: String
    let artistName: String
    let lines: [LyricLine]
    let isSynced: Bool
    let plainLyrics: String?

    var hasLyrics: Bool {
        !lines.isEmpty || (plainLyrics != nil && !plainLyrics!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func == (lhs: TrackLyrics, rhs: TrackLyrics) -> Bool {
        lhs.trackTitle == rhs.trackTitle &&
        lhs.artistName == rhs.artistName &&
        lhs.isSynced == rhs.isSynced &&
        lhs.plainLyrics == rhs.plainLyrics &&
        lhs.lines == rhs.lines
    }
}
