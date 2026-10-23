// OnboardingStep.swift
// DynamicNotch / Features / Onboarding / Models
//
// Apple-grade multi-step onboarding model with localized Turkish copy,
// fluid dimensions, semantic action routing, and visual accents.

import SwiftUI

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome = 1
    case shortcuts = 2
    case permissions = 3
    case support = 4
    case community = 5

    var stepIndex: Int { rawValue }
    var totalSteps: Int { Self.allCases.count }

    var title: String {
        switch self {
        case .welcome:
            return "DynamicNotch'a Hoş Geldiniz"
        case .shortcuts:
            return "Kısayolları Keşfedin"
        case .permissions:
            return "Gerekli İzinleri Onayla"
        case .support:
            return "Projeyi Destekleyin"
        case .community:
            return "Topluluk ve Güncellemeler"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "MacBook'unuzun çentiğini veya ekranınızın üst kısmını akıllı, canlı ve etkileşimli bir kontrol merkezine dönüştürün."
        case .shortcuts:
            return "Çentiğin güçlü özelliklerini klavyenizden tek dokunuşla açın. Aşağıdaki kısayolları klavyenizden tuşlayarak canlı test edin."
        case .permissions:
            return "Ses göstergeleri, Wi-Fi ağları, Bluetooth aygıtları ve medya oynatımını çentikte kusursuz göstermek için sistem erişim izinlerini verin."
        case .support:
            return "DynamicNotch açık kaynaklı ve topluluk destekli bir projedir. GitHub üzerinde bir yıldız (★) vererek projenin büyümesine katkıda bulunabilirsiniz."
        case .community:
            return "Yeni sürümlerden, eklenen özelliklerden ilk siz haberdar olmak ve doğrudan geliştiricilerle iletişim kurmak için Telegram kanalımıza katılın."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome:
            return "Sürdür"
        case .shortcuts:
            return "İzinlere Geç"
        case .permissions, .support:
            return "Sürdür"
        case .community:
            return "Başla"
        }
    }

    var secondaryButtonTitle: String? {
        switch self {
        case .welcome:
            return "Geç"
        case .shortcuts:
            return "Atla"
        case .permissions:
            return "Ayarları Aç"
        case .support:
            return "GitHub'da Aç"
        case .community:
            return "Telegram'a Katıl"
        }
    }

    var secondaryActionURL: URL? {
        switch self {
        case .welcome, .shortcuts:
            return nil
        case .permissions:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")
        case .support:
            return URL(string: "https://github.com/jackson-storm/DynamicNotch")
        case .community:
            return URL(string: "https://t.me/Dynamic_Notch")
        }
    }

    var accentColor: Color {
        switch self {
        case .welcome:
            return Color(red: 0.15, green: 0.65, blue: 1.0)
        case .shortcuts:
            return Color(red: 1.0, green: 0.58, blue: 0.0) // Apple Amber / Orange
        case .permissions:
            return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .support:
            return Color(red: 1.0, green: 0.78, blue: 0.18)
        case .community:
            return Color(red: 0.18, green: 0.65, blue: 0.98)
        }
    }

    func dynamicSize(baseWidth: CGFloat, isNotchless: Bool) -> CGSize {
        switch self {
        case .shortcuts:
            let w = isNotchless ? max(baseWidth + 260, 460) : max(baseWidth + 240, 450)
            return CGSize(width: w, height: 196)
        default:
            let w = isNotchless ? max(baseWidth + 240, 430) : max(baseWidth + 210, 420)
            return CGSize(width: w, height: 182)
        }
    }
}
