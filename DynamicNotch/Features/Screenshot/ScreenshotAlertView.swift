// ScreenshotAlertView.swift
// DynamicNotch / Features / Screenshot
//
// Apple-grade Vertical Centered Screenshot Card for Dynamic Notch (AirPods Style):
//   1. Top: Minimalist Header Title + Close '✕' button
//   2. Center: Really Big Screenshot Hero Stage (2:1 aspect ratio with live preview)
//   3. Bottom: SADECE APPLE LOGOLARIYLA Dairesel Butonlar (AirDrop, WhatsApp, Paylaşım)

import SwiftUI
import AppKit
import Vision

struct ScreenshotAlertView: View {

    let item: ScreenshotItem
    let observer: ScreenshotObserver
    var notchBottomY: CGFloat = 0
    let onDismiss: () -> Void

    @State private var isHoveringCopy: Bool = false
    @State private var isCopied: Bool = false
    @State private var isHoveringOCR: Bool = false
    @State private var isOCRDone: Bool = false
    @State private var isHoveringAirDrop: Bool = false
    @State private var isHoveringWhatsApp: Bool = false
    @State private var isHoveringShare: Bool = false
    @State private var isHoveringHero: Bool = false
    @State private var isHoveringClose: Bool = false
    @State private var shareButtonView: NSView? = nil

    private let appleBlue     = Color(red: 0.04, green: 0.52, blue: 1.0)
    private let whatsAppGreen = Color(red: 0.16, green: 0.78, blue: 0.38)

    private var isTurkish: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("tr") == true
    }

    private var titleText: String {
        isTurkish ? "Ekran Görüntüsü Alındı" : "Screenshot Captured"
    }

    private let heroWidth: CGFloat  = 240
    private let heroHeight: CGFloat = 114

    var body: some View {
        VStack(spacing: 9) {
            headerView
            heroStageView
            actionButtonsDock
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 1. TOP: Minimalist Header + Close '✕'
    private var headerView: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(item.recognizedText != nil ? (isTurkish ? "Metin Panoya Kopyalandı" : "Text Copied") : titleText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            if item.recognizedText != nil {
                Text("OCR")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.68, green: 0.32, blue: 0.90), Color(red: 0.42, green: 0.28, blue: 0.86)],
                                startPoint: .top, endPoint: .bottom
                            ))
                    )
            }

            Spacer(minLength: 4)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(isHoveringClose ? .white : .white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isHoveringClose ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .help(isTurkish ? "Kapat" : "Dismiss")
        }
        .frame(width: heroWidth)
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    // MARK: - 2. CENTER: Screenshot Hero Stage
    private var heroStageView: some View {
        Button {
            observer.openInPreview(for: item)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.40))
                    .frame(width: heroWidth, height: heroHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(isHoveringHero ? 0.35 : 0.16), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 3)

                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: heroWidth - 2, maxHeight: heroHeight - 2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if isHoveringHero {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .frame(maxWidth: heroWidth - 2, maxHeight: heroHeight - 2)

                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(isTurkish ? "Önizle" : "Preview")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.65))
                            .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 0.8))
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHoveringHero = $0 }
        .help(isTurkish ? "Önizlemede Aç" : "Open in Preview")
    }

    // MARK: - 3. BOTTOM: Dairesel Aksiyon Butonları Dock
    private var actionButtonsDock: some View {
        HStack(spacing: 9) {
            copyButton
            ocrButton
            airDropButton
            whatsAppButton
            shareButton
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var copyButtonFillColor: Color {
        if isCopied {
            return Color.notchGreen.opacity(0.92)
        } else if isHoveringCopy {
            return Color.white.opacity(0.24)
        } else {
            return Color.white.opacity(0.12)
        }
    }

    private var copyButtonStrokeColor: Color {
        if isCopied {
            return Color.white.opacity(0.50)
        } else if isHoveringCopy {
            return Color.white.opacity(0.35)
        } else {
            return Color.white.opacity(0.20)
        }
    }

    private var copyButtonShadowColor: Color {
        isCopied ? Color.notchGreen.opacity(0.45) : Color.black.opacity(0.30)
    }

    // 1. Copy Only Button (Sadece Kopyala)
    private var copyButton: some View {
        Button {
            guard !isCopied else { return }
            observer.copyToClipboard(for: item)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onDismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(copyButtonFillColor)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle().stroke(copyButtonStrokeColor, lineWidth: 1)
                    )
                    .shadow(color: copyButtonShadowColor, radius: 4, x: 0, y: 2)

                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(isHoveringCopy ? 1.08 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHoveringCopy)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringCopy = $0 }
        .help(isTurkish ? "Panoya Kopyala (Sadece Kopyala)" : "Copy to Clipboard")
    }

    // 1b. OCR Text Copy Button (Metni Kopyala)
    private var ocrButton: some View {
        Button {
            guard !isOCRDone else { return }
            Task {
                let recognized = await VisionOCRService.shared.recognizeText(from: item.thumbnail)
                await MainActor.run {
                    if let text = recognized, !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                            isOCRDone = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                            onDismiss()
                        }
                    } else {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isOCRDone ? Color.notchGreen.opacity(0.92) : (isHoveringOCR ? Color(red: 0.58, green: 0.28, blue: 0.86) : Color(red: 0.50, green: 0.22, blue: 0.78).opacity(0.85)))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle().stroke(Color.white.opacity(isHoveringOCR ? 0.40 : 0.22), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.50, green: 0.22, blue: 0.78).opacity(0.35), radius: 4, x: 0, y: 2)

                if isOCRDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(isHoveringOCR ? 1.08 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHoveringOCR)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringOCR = $0 }
        .help(isTurkish ? "Metni Kopyala (OCR)" : "Copy Text (OCR)")
    }

    // 2. AirDrop Button
    private var airDropButton: some View {
        Button {
            observer.shareViaAirDrop(for: item)
            onDismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(isHoveringAirDrop ? appleBlue.opacity(0.95) : appleBlue.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHoveringAirDrop ? 0.40 : 0.22), lineWidth: 1)
                    )
                    .shadow(color: appleBlue.opacity(0.40), radius: 5, x: 0, y: 2)

                AirDropIconView()
            }
            .scaleEffect(isHoveringAirDrop ? 1.08 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHoveringAirDrop)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringAirDrop = $0 }
        .help(isTurkish ? "AirDrop ile Paylaş" : "Share via AirDrop")
    }

    // 3. WhatsApp Button
    private var whatsAppButton: some View {
        Button {
            observer.shareViaWhatsApp(for: item)
            onDismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(isHoveringWhatsApp ? whatsAppGreen.opacity(0.95) : whatsAppGreen.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHoveringWhatsApp ? 0.40 : 0.22), lineWidth: 1)
                    )
                    .shadow(color: whatsAppGreen.opacity(0.40), radius: 5, x: 0, y: 2)

                WhatsAppIconView()
            }
            .scaleEffect(isHoveringWhatsApp ? 1.08 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHoveringWhatsApp)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringWhatsApp = $0 }
        .help(isTurkish ? "WhatsApp ile Paylaş" : "Share via WhatsApp")
    }

    // 4. Universal Share Button
    private var shareButton: some View {
        Button {
            observer.openUniversalSharePicker(
                for: item,
                relativeTo: shareButtonView,
                notchBottomY: notchBottomY
            ) {
                onDismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isHoveringShare ? Color.white.opacity(0.24) : Color.white.opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHoveringShare ? 0.35 : 0.20), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 4, x: 0, y: 2)

                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .offset(y: -1)
            }
            .background(NSViewAccessor { shareButtonView = $0 })
            .scaleEffect(isHoveringShare ? 1.08 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHoveringShare)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringShare = $0 }
        .help(isTurkish ? "Diğer Paylaşım Seçenekleri…" : "More Share Options…")
    }
}

// MARK: - AirDrop Official Icon View

struct AirDropIconView: View {
    private var officialSidebarIcon: NSImage? {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarAirDrop.icns"
        if FileManager.default.fileExists(atPath: path),
           let img = NSImage(contentsOfFile: path) {
            img.isTemplate = true
            return img
        }
        return nil
    }

    var body: some View {
        if let icon = officialSidebarIcon {
            Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
        } else {
            // Elegant Vector Radar Wave Fallback
            AirDropRadarFallback()
                .frame(width: 22, height: 22)
        }
    }
}

/// Fallback radar wave drawing if system icns is ever unreachable
struct AirDropRadarFallback: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)

            ForEach([7.0, 11.0, 15.0], id: \.self) { r in
                Circle()
                    .stroke(Color.white, lineWidth: 1.6)
                    .frame(width: r * 2, height: r * 2)
                    .mask(
                        HStack {
                            Rectangle()
                            Spacer()
                            Rectangle()
                        }
                    )
            }
        }
    }
}

// MARK: - WhatsApp Minimalist White Line Icon View

struct WhatsAppIconView: View {
    var body: some View {
        ZStack {
            // Speech bubble outline in pure white lines
            WhatsAppBubbleOutline()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 20)

            // Phone handset in pure white — diagonal upright angle matching official WhatsApp logo
            Image(systemName: "phone.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(10))
                .offset(x: 0.2, y: -0.2)
        }
        .frame(width: 22, height: 22)
    }
}

/// Precise vector path for WhatsApp speech bubble with pointer tail at bottom-left
struct WhatsAppBubbleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.44

        // Draw circular arc leaving a clean gap at bottom-left (between 120° and 154°)
        // In SwiftUI macOS coordinates: 0° is 3 o'clock, 90° is 6 o'clock, 180° is 9 o'clock.
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(120),
            endAngle: .degrees(154),
            clockwise: true
        )

        // Triangular speech tail pointing to bottom-left
        let tailTip = CGPoint(x: rect.minX + 1.2, y: rect.maxY - 1.2)
        let tailEnd = CGPoint(
            x: center.x + radius * cos(CGFloat(120.0 * .pi / 180.0)),
            y: center.y + radius * sin(CGFloat(120.0 * .pi / 180.0))
        )

        path.addLine(to: tailTip)
        path.addLine(to: tailEnd)
        path.closeSubpath()

        return path
    }
}

// MARK: - NSView Accessor Helper

private struct NSViewAccessor: NSViewRepresentable {
    let onView: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            self.onView(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.onView(nsView)
        }
    }
}

// MARK: - Vision OCR Service (Apple Vision Text Recognition)

final class VisionOCRService {

    static let shared = VisionOCRService()
    private init() {}

    /// Extracts recognized text from an NSImage using Apple's Vision framework.
    func recognizeText(from image: NSImage) async -> String? {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let textLines = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: fullText.isEmpty ? nil : fullText)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["tr-TR", "en-US", "de-DE", "fr-FR", "es-ES"]

            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

