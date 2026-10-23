// NSImage+Extensions.swift
// DynamicNotch / Utilities / Extensions
//
// Extracts a vibrant, readable accent color from album artwork so the
// Now Playing progress bar and audio visualizer adapt to the current track.

import AppKit

extension NSImage {

    /// Computes a vibrant accent color from the receiver, ensuring minimum
    /// brightness and saturation so it remains visible against the black notch.
    func dominantAccentColor() -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sampleSize = 16
        var rawData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &rawData,
                  width: sampleSize,
                  height: sampleSize,
                  bitsPerComponent: 8,
                  bytesPerRow: sampleSize * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var weightSum: CGFloat = 0

        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = CGFloat(rawData[i])     / 255.0
            let g = CGFloat(rawData[i + 1]) / 255.0
            let b = CGFloat(rawData[i + 2]) / 255.0

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            // Weight vibrant pixels higher than grey/black/white pixels
            let weight = 0.2 + saturation * 2.0

            totalR += r * weight
            totalG += g * weight
            totalB += b * weight
            weightSum += weight
        }

        guard weightSum > 0 else { return nil }

        let baseColor = NSColor(
            srgbRed: totalR / weightSum,
            green:   totalG / weightSum,
            blue:    totalB / weightSum,
            alpha:   1.0
        )

        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alp: CGFloat = 0
        baseColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alp)

        // Ensure high contrast on pitch-black background
        let adjustedSat = max(sat, 0.55)
        let adjustedBri = max(bri, 0.85)

        return NSColor(hue: hue, saturation: adjustedSat, brightness: adjustedBri, alpha: 1.0)
    }
}
