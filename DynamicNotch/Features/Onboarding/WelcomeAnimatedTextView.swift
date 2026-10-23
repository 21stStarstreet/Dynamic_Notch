// WelcomeAnimatedTextView.swift
// DynamicNotch / Features / Onboarding / Views
//
// Ultra-refined 120 FPS Metal-accelerated animated "welcome" cursive vector
// script with dual-layer neon bloom, gradient stroke and breathing radiance.

import SwiftUI

struct WelcomeAnimatedTextView: View {
    var isSingleRound: Bool = true
    var onCompletion: (() -> Void)? = nil

    @State private var strokeProgress: CGFloat = 0.0
    @State private var isAnimating: Bool = false

    var body: some View {
        ZStack {
            // Layer 1: Soft Ambient Rim (Low glare, gentle aura)
            WelcomeTextShape()
                .trim(from: 0, to: strokeProgress)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.82, blue: 1.00),
                            Color(red: 0.12, green: 0.52, blue: 1.00),
                            Color(red: 0.65, green: 0.38, blue: 0.98)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 5.4, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 2.8)
                .opacity(0.32)

            // Layer 2: Apple Precision Solid Vector Stroke (Thickened & Bold)
            WelcomeTextShape()
                .trim(from: 0, to: strokeProgress)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.32, green: 0.90, blue: 1.00), // Vibrant Cyan
                            Color(red: 0.18, green: 0.62, blue: 1.00), // Electric Blue
                            Color(red: 0.70, green: 0.42, blue: 1.00), // Subtle Violet tint
                            Color.white.opacity(0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
                )
        }
        .frame(width: 210, height: 50)
        .shadow(color: Color(red: 0.15, green: 0.60, blue: 1.0).opacity(0.16), radius: 5, y: 1)
        .onAppear {
            isAnimating = true
            startAnimationCycle()
        }
        .onDisappear {
            isAnimating = false
        }
    }

    private func startAnimationCycle() {
        guard isAnimating else { return }

        // 1. Yazılma Aşaması (0.0 -> 1.0)
        withAnimation(.easeInOut(duration: 2.0)) {
            strokeProgress = 1.0
        }

        // 2. Yazıldıktan sonra tam haliyle bekleme süresi (1.1 saniye)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 + 1.1) {
            guard self.isAnimating else { return }

            // 3. Yavaşça ve kusursuzca silinme aşaması (1.0 -> 0.0)
            withAnimation(.easeInOut(duration: 1.6)) {
                self.strokeProgress = 0.0
            }

            // 4. Silinme bittiği an (1.6s + 0.05s mikro geçiş) pürüzsüzce sıradaki aksiyona aktar
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6 + 0.05) {
                guard self.isAnimating else { return }

                if self.isSingleRound {
                    // 1 tur tamamlandı (yazılış siliniş) -> gecikmesiz, akışkan geçiş başlasın!
                    self.onCompletion?()
                } else {
                    // Çok adımlı Onboarding içindeyse döngüyü sürdür
                    self.startAnimationCycle()
                }
            }
        }
    }
}
