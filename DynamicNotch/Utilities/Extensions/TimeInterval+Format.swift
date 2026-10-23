// TimeInterval+Format.swift
// DynamicNotch / Utilities / Extensions
//
// Formats seconds into mm:ss or hh:mm:ss strings for media and timer displays.

import Foundation

extension TimeInterval {

    /// Returns a `mm:ss` or `h:mm:ss` formatted string.
    var formattedMinutesSeconds: String {
        guard self.isFinite && self >= 0 else { return "00:00" }
        let totalSeconds = Int(self.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
