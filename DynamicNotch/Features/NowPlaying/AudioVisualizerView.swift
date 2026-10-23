// AudioVisualizerView.swift
// DynamicNotch / Features / NowPlaying
//
// Dynamic Apple-grade 4-bar audio waveform equalizer driven by TimelineView.
//
// Acoustic Engineering & Dynamics
// ────────────────────────────────
// • Refined, elegant sizing tailored for high-DPI displays (15pt compact, 17.5pt expanded).
// • Musically synchronized 4-band acoustic response with smooth harmonic continuity:
//   - Bar 0 (Bass): Heavy kick drum bursts on the beat with exponential damping.
//   - Bar 1 (Snare / Groove): Crisp offbeat snare claps on beats 2 & 4 with walking bassline.
//   - Bar 2 (Lead Melody): Agile vocal / synth melodies with smooth lyrical vibrato.
//   - Bar 3 (Treble): Crisp eighth-note hi-hat swing and tempo-locked acoustic shimmer (no strobing).
// • Anchored to track metadata (tempo & seeds) and artwork accent color across all modes.

import SwiftUI

struct AudioVisualizerView: View {

    let isPlaying: Bool
    var tint: Color = .white
    var trackInfo: NowPlayingInfo? = nil
    var isCompact: Bool = false

    private var maxHeights: [CGFloat] {
        isCompact
            ? [11.5, 15.0, 13.5, 10.5]
            : [13.5, 17.5, 15.5, 12.0]
    }

    private var pausedHeights: [CGFloat] {
        isCompact
            ? [4.0, 6.5, 4.0, 5.0]
            : [4.5, 7.5, 4.5, 5.5]
    }

    private var barWidth: CGFloat {
        isCompact ? 2.4 : 2.6
    }

    private var spacing: CGFloat {
        isCompact ? 2.0 : 2.2
    }

    private var totalWidth: CGFloat {
        (barWidth * 4) + (spacing * 3)
    }

    private var totalHeight: CGFloat {
        isCompact ? 16 : 18
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isPlaying ? 0.96 : 0.45))
                        .frame(
                            width: barWidth,
                            height: barHeight(for: index, time: t)
                        )
                        .shadow(
                            color: tint.opacity(isPlaying ? 0.40 : 0.0),
                            radius: isCompact ? 1.5 : 2.5,
                            x: 0,
                            y: 0
                        )
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .animation(.spring(response: 0.30, dampingFraction: 0.75), value: isPlaying)
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else {
            return pausedHeights[index]
        }
        let energy = barEnergy(for: index, time: time)
        let minH: CGFloat = isCompact ? 3.0 : 3.2
        let maxH = maxHeights[index]
        return minH + CGFloat(energy) * (maxH - minH)
    }

    private func barEnergy(for index: Int, time: TimeInterval) -> Double {
        let seed: Int
        if let track = trackInfo {
            seed = abs(track.title.hashValue ^ track.artist.hashValue)
        } else {
            seed = 42
        }

        // Upbeat tempo tracking: energetic modern tempo range (114 to 148 BPM)
        let tempo = 114.0 + Double(seed % 35)
        let fBeat = tempo / 60.0 // ~1.9 to 2.47 beats/second

        // Macro phrase cycle (gives rhythmic breathing between verse and chorus energy)
        let phraseCycle = 18.0 + Double(seed % 8)
        let phraseEnergy = 0.82 + 0.18 * sin(time * (Double.pi * 2.0 / phraseCycle) + Double(seed % 7))

        switch index {
        case 0:
            // ── Bar 0: Bass / Kick Drum (Punchy kick on beat, smooth acoustic decay) ──
            let beat0 = (time * fBeat).truncatingRemainder(dividingBy: 1.0)
            let kick = pow(max(0.0, sin(beat0 * Double.pi)), 2.5) * exp(-2.0 * beat0)
            let subGroove = 0.18 * (sin(time * fBeat * 0.5 + Double(seed % 5)) + 1.0)
            let val = (kick * 0.85 + subGroove) * phraseEnergy
            return min(1.0, max(0.08, val))

        case 1:
            // ── Bar 1: Snare & Punchy Mid-Bass (Groovy, tallest energy on beats 2 & 4) ──
            let snarePhase = (time * fBeat + 0.5).truncatingRemainder(dividingBy: 1.0)
            let snare = pow(max(0.0, sin(snarePhase * Double.pi)), 2.8) * exp(-2.0 * snarePhase)
            let groove = 0.35 * (sin(time * fBeat * 1.5 + 1.0) + 1.0)
            let val = (snare * 0.65 + groove * 0.35) * phraseEnergy
            return min(1.0, max(0.10, val))

        case 2:
            // ── Bar 2: Lead Melody & Vocals (Agile, expressive musical curve) ──
            let v1 = sin(time * fBeat * 2.2 + 0.8)
            let v2 = cos(time * fBeat * 1.4 + 2.1)
            let vocalWave = ((v1 * 0.55 + v2 * 0.45) + 1.0) * 0.5
            let val = vocalWave * phraseEnergy * 1.05
            return min(1.0, max(0.08, val))

        case 3:
            // ── Bar 3: Crisp Treble (Eighth-note swing + tempo-locked shimmer, NO strobing) ──
            let swingPhase = (time * fBeat * 2.0 + 0.35).truncatingRemainder(dividingBy: 1.0)
            let swingPulse = pow(max(0.0, sin(swingPhase * Double.pi)), 2.2) * exp(-1.8 * swingPhase)
            let shimmer = 0.22 * (sin(time * fBeat * 3.2 + Double(seed % 4)) + 1.0)
            let val = (swingPulse * 0.72 + shimmer * 0.28) * phraseEnergy
            return min(1.0, max(0.08, val))

        default:
            return 0.5
        }
    }
}
