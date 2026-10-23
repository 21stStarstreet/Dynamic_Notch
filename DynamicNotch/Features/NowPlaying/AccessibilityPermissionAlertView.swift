// AccessibilityPermissionAlertView.swift
// DynamicNotch / Features / NowPlaying
//
// Apple-grade Permission Card presented when DynamicNotch requests
// authorization to interact with Spotify.
//
// Design:
// • Symmetrical, squarish aspect ratio with deeply rounded concentric corners (34pt).
// • Centered circular Spotify (100% official brand vector) and DynamicNotch logos side by side at the top.
// • Clean multi-line typographic prompt: "DynamicNotch'a erişim izni vermeniz gerekli".
// • Streamlined, iconless "İzin Ver" capsule button underneath.
// • Subtle close button (X) in the upper corner for smooth dismissal.

import SwiftUI
import AppKit

// MARK: - Official Spotify Brand Sound Waves Shape
// Direct mathematical transcription of Spotify's official SVG vector paths (viewBox: 0 0 24 24).
// Perfectly faithful to the official Spotify Brand Guidelines with zero asset loading dependencies.

struct SpotifyOfficialWavesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        // ── Wave 1: Bottom Wave ──
        path.move(to: p(17.521, 17.340))
        path.addCurve(to: p(16.500, 17.580), control1: p(17.281, 17.699), control2: p(16.861, 17.820))
        path.addCurve(to: p(5.939, 16.439), control1: p(13.680, 15.840), control2: p(10.140, 15.479))
        path.addCurve(to: p(5.040, 15.900), control1: p(5.521, 16.561), control2: p(5.160, 16.260))
        path.addCurve(to: p(5.580, 15.000), control1: p(4.920, 15.479), control2: p(5.220, 15.120))
        path.addCurve(to: p(17.220, 16.320), control1: p(10.140, 13.979), control2: p(14.100, 14.400))
        path.addCurve(to: p(17.521, 17.340), control1: p(17.640, 16.500), control2: p(17.699, 16.979))
        path.closeSubpath()

        // ── Wave 2: Middle Wave ──
        path.move(to: p(18.961, 14.040))
        path.addCurve(to: p(17.700, 14.340), control1: p(18.660, 14.460), control2: p(18.120, 14.640))
        path.addCurve(to: p(5.761, 12.960), control1: p(14.461, 12.360), control2: p(9.541, 11.760))
        path.addCurve(to: p(4.621, 12.360), control1: p(5.282, 13.080), control2: p(4.741, 12.840))
        path.addCurve(to: p(5.221, 11.219), control1: p(4.501, 11.880), control2: p(4.741, 11.339))
        path.addCurve(to: p(18.661, 13.019), control1: p(9.421, 9.959), control2: p(14.821, 10.619))
        path.addCurve(to: p(18.961, 14.279), control1: p(19.081, 13.259), control2: p(19.261, 13.859))
        path.closeSubpath()

        // ── Wave 3: Top Wave ──
        path.move(to: p(19.081, 10.919))
        path.addCurve(to: p(5.160, 9.300), control1: p(15.240, 8.400), control2: p(8.820, 8.160))
        path.addCurve(to: p(3.780, 8.520), control1: p(4.560, 9.480), control2: p(3.960, 9.120))
        path.addCurve(to: p(4.560, 7.140), control1: p(3.600, 7.920), control2: p(3.960, 7.320))
        path.addCurve(to: p(20.040, 8.640), control1: p(8.820, 5.880), control2: p(15.840, 6.180))
        path.addCurve(to: p(20.460, 10.200), control1: p(20.580, 8.940), control2: p(20.760, 9.660))
        path.addCurve(to: p(18.900, 10.560), control1: p(20.160, 10.680), control2: p(19.440, 10.860))
        path.closeSubpath()

        return path
    }
}

// MARK: - Circular Spotify Logo View (100% Official Vector Asset)

struct SpotifyCircularLogoView: View {
    let size: CGFloat

    // Official Spotify brand green
    private let spotifyGreen = Color(red: 0.114, green: 0.843, blue: 0.376)

    var body: some View {
        ZStack {
            // Official green background circle
            Circle()
                .fill(spotifyGreen)

            // Exact official Spotify sound waves
            SpotifyOfficialWavesShape()
                .fill(Color.black.opacity(0.92))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Circular DynamicNotch Logo View

struct DynamicNotchCircularLogoView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            if let icon = NSApp.applicationIconImage, icon.isValid {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
            } else if let icon = NSImage(named: "AppIcon"), icon.isValid {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.25), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Capsule()
                    .fill(Color.black)
                    .frame(width: size * 0.52, height: size * 0.24)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Main Accessibility Permission Alert View

struct AccessibilityPermissionAlertView: View {

    let onGrant: () -> Void
    let onDismiss: () -> Void

    @State private var isHoveringGrant: Bool = false
    @State private var isHoveringDismiss: Bool = false

    private let spotifyGreen = Color(red: 0.114, green: 0.843, blue: 0.376)

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var titleText: String {
        isTurkish
            ? "DynamicNotch’a erişim\nizni vermeniz gerekli"
            : "You need to grant access\nto DynamicNotch"
    }

    private var subtitleText: String {
        isTurkish
            ? "Spotify parçalarını favorilere eklemek için"
            : "To favorite Spotify tracks from the notch"
    }

    private var grantButtonText: String {
        isTurkish ? "İzin Ver" : "Allow"
    }

    private var dismissButtonText: String {
        isTurkish ? "Vazgeç" : "Cancel"
    }

    var body: some View {
        VStack(spacing: 0) {

            // Row 1: Spotify and DynamicNotch Circular Logos Side by Side
            HStack(spacing: 12) {
                SpotifyCircularLogoView(size: 42)
                DynamicNotchCircularLogoView(size: 42)
            }
            .padding(.top, 4)
            .padding(.bottom, 12)

            // Row 2: Multiline Headline & Context Subtitle
            VStack(spacing: 4) {
                Text(titleText)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleText)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            // Row 3: Action Buttons Side by Side (İzin Ver + Vazgeç)
            HStack(spacing: 10) {

                // Primary Action Button: "İzin Ver" (Spotify Green Capsule)
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    onGrant()
                } label: {
                    Text(grantButtonText)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isHoveringGrant
                                            ? [Color(red: 0.20, green: 0.94, blue: 0.46), Color(red: 0.12, green: 0.86, blue: 0.38)]
                                            : [Color(red: 0.18, green: 0.88, blue: 0.42), spotifyGreen],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                                )
                                .shadow(
                                    color: spotifyGreen.opacity(isHoveringGrant ? 0.45 : 0.22),
                                    radius: isHoveringGrant ? 7 : 3,
                                    x: 0,
                                    y: 2
                                )
                        )
                        .scaleEffect(isHoveringGrant ? 1.025 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHoveringGrant)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringGrant = $0 }

                // Secondary Action Button: "Vazgeç" (Apple Gray / Liquid Glass Capsule)
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    onDismiss()
                } label: {
                    Text(dismissButtonText)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(isHoveringDismiss ? 1.0 : 0.88))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isHoveringDismiss
                                            ? [Color.white.opacity(0.24), Color.white.opacity(0.16)]
                                            : [Color.white.opacity(0.16), Color.white.opacity(0.09)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(isHoveringDismiss ? 0.30 : 0.16), lineWidth: 0.8)
                                )
                                .shadow(
                                    color: Color.black.opacity(isHoveringDismiss ? 0.35 : 0.20),
                                    radius: isHoveringDismiss ? 6 : 3,
                                    x: 0,
                                    y: 2
                                )
                        )
                        .scaleEffect(isHoveringDismiss ? 1.025 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHoveringDismiss)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringDismiss = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SpotifySuccessCheckmarkView
// Apple-grade Standalone Animated Vector Checkmark HUD presented when Spotify
// is successfully authorized via OAuth 2.0 PKCE.
// Exact match with the Onboarding Shortcut Trainer completion checkmark.

struct SpotifySuccessCheckmarkView: View {
    var body: some View {
        ZStack {
            AnimatedVectorCheckmarkView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
