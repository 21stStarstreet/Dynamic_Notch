// AlbumArtView.swift
// DynamicNotch / UI / Components
//
// Strictly bounded square album artwork component.
//
// Why strict inner frame clipping matters
// ───────────────────────────────────────
// In SwiftUI, applying `.aspectRatio(contentMode: .fill)` to a non-square NSImage
// (such as a 16:9 video/podcast thumbnail) expands the view's layout width beyond
// its parent frame unless `.frame(width: size, height: size)` is applied directly
// to the Image BEFORE `.clipped()`. This implementation guarantees that any image
// aspect ratio is center-cropped to an exact `size × size` square with zero overflow.

import SwiftUI
import AppKit

struct AlbumArtView: View {

    let image: NSImage?
    var isPlaying: Bool = true
    var size: CGFloat = 52.0
    var cornerRadius: CGFloat = 12.0

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(white: 0.24), Color(white: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size, height: size)

                Image(systemName: "music.note")
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        .scaleEffect(isPlaying ? 1.0 : 0.94)
        .animation(SpringConfig.contentTransition, value: isPlaying)
    }
}
