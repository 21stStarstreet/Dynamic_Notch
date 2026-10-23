// AirPodsVideoPlayerView.swift
// DynamicNotch / Features / AirPods
//
// Renders Apple's official AirPods transparent HEVC video loops directly
// inside the Dynamic Notch using AVPlayerLayer with clear background.

import SwiftUI
import AVFoundation
import AppKit

struct AirPodsVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerContainerNSView {
        PlayerContainerNSView(url: url)
    }

    func updateNSView(_ nsView: PlayerContainerNSView, context: Context) {
        nsView.updateURLIfNeeded(url)
    }
}

final class PlayerContainerNSView: NSView {
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var currentURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        setupPlayer(url: url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateURLIfNeeded(_ url: URL) {
        guard currentURL != url else { return }
        setupPlayer(url: url)
    }

    private func setupPlayer(url: URL) {
        self.currentURL = url
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLooper = nil

        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        self.player = queuePlayer

        // Loop seamlessly using Apple's AVPlayerLooper
        self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        self.layer?.addSublayer(layer)
        self.playerLayer = layer

        queuePlayer.isMuted = true
        queuePlayer.play()
    }

    func replay() {
        player?.seek(to: .zero)
        player?.play()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    deinit {
        player?.pause()
        playerLooper = nil
    }
}
