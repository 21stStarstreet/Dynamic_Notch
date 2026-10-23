// SettingsView.swift
// DynamicNotch / UI / Settings
//
// User preferences panel backed by @AppStorage (UserDefaults), plus an
// interactive simulation bench to test LiveActivities, Alerts, and Priority Queue
// behavior on demand.

import SwiftUI

struct SettingsView: View {

    var viewModel: NotchViewModel?

    @AppStorage("notchEnabled")          private var notchEnabled: Bool = true
    @AppStorage("showNowPlaying")        private var showNowPlaying: Bool = true
    @AppStorage("showBattery")           private var showBattery: Bool = true
    @AppStorage("showBluetooth")         private var showBluetooth: Bool = true
    @AppStorage("showVolume")            private var showVolume: Bool = true
    @AppStorage("showBrightness")        private var showBrightness: Bool = true
    @AppStorage("showDownloads")         private var showDownloads: Bool = true
    @AppStorage("showTimer")             private var showTimer: Bool = true
    @AppStorage("showScreenshots")       private var showScreenshots: Bool = true
    @AppStorage("showKeyboardBrightness") private var showKeyboardBrightness: Bool = true
    @AppStorage("showExternalDrives")    private var showExternalDrives: Bool = true
    @AppStorage("showCalendarEvents")    private var showCalendarEvents: Bool = true
    @AppStorage("showHotspotBattery")    private var showHotspotBattery: Bool = true
    @AppStorage("showQuickNote")         private var showQuickNote: Bool = true
    @AppStorage("calendarAlertLeadTimeMinutes") private var calendarAlertLeadTimeMinutes: Int = 10
    @AppStorage("notchPresentationMode") private var notchPresentationMode: String = "automatic"
    @AppStorage("floatingIslandPosition") private var floatingIslandPosition: String = "belowMenuBar"
    @AppStorage("animationStyle")        private var animationStyle: String = "spring"
    @AppStorage("notchWidthMultiplier")  private var widthMultiplier: Double = 1.0

    @ObservedObject private var spotifyService = SpotifyAPIService.shared

    var body: some View {
        Form {
            Section("Genel") {
                Toggle("DynamicNotch Aktif", isOn: $notchEnabled)
                    .onChange(of: notchEnabled) { _, enabled in
                        if !enabled {
                            viewModel?.dismiss()
                        }
                    }
            }

            Section("Özellikler") {
                Toggle("Now Playing (Müzik & Medya)", isOn: $showNowPlaying)
                Toggle("Batarya Bildirimleri",        isOn: $showBattery)
                Toggle("Bluetooth Bağlantıları",      isOn: $showBluetooth)
                Toggle("Ses Seviyesi HUD",            isOn: $showVolume)
                Toggle("Ekran Parlaklığı HUD",        isOn: $showBrightness)
                Toggle("Klavye Aydınlatması HUD",     isOn: $showKeyboardBrightness)
                Toggle("İndirme İlerlemesi",          isOn: $showDownloads)
                Toggle("Zamanlayıcı (Timer & Pomodoro)", isOn: $showTimer)
                Toggle("Ekran Görüntüsü Bildirimleri", isOn: $showScreenshots)
                Toggle("Harici Sürücüler (SSD, USB, SD, DMG)", isOn: $showExternalDrives)
                Toggle("Takvim & Toplantı Bildirimleri (EventKit)", isOn: $showCalendarEvents)
                if showCalendarEvents {
                    Picker("Bildirim Zamanı", selection: $calendarAlertLeadTimeMinutes) {
                        Text("5 dakika önce").tag(5)
                        Text("10 dakika önce").tag(10)
                        Text("15 dakika önce").tag(15)
                        Text("30 dakika önce").tag(30)
                    }
                }
                Toggle("Kişisel Erişim Noktası (Hotspot)", isOn: $showHotspotBattery)
                Toggle("Hızlı Not (Apple Notlar Entegrasyonu)", isOn: $showQuickNote)
            }

            Section("Spotify & Favori Entegrasyonu") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(spotifyService.isConnected ? Color(red: 0.114, green: 0.843, blue: 0.376) : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(spotifyService.isConnected ? (spotifyService.userDisplayName != nil ? "Bağlı: \(spotifyService.userDisplayName!)" : "Spotify Bağlantısı Aktif") : "Spotify Bağlantısı Bekleniyor")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        if spotifyService.isConnected {
                            Button("Bağlantıyı Kes") {
                                spotifyService.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Spotify'a Bağlan") {
                                spotifyService.startAuthFlow()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    Text("Spotify'da önceden beğendiğiniz parçaları çentikte anlık algılamak ve doğrudan favorilere ekleyip çıkarmak için resmi Spotify Web API (OAuth 2.0 PKCE) kullanılır. Hem Ücretsiz hem Premium hesaplarla çalışır ve Mac App Store standartlarına %100 uygundur.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let status = spotifyService.statusMessage, !status.isEmpty {
                        Text(status)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Ekran & Dinamik Ada Formu") {
                Picker("Sunum Modu", selection: $notchPresentationMode) {
                    Text("Otomatik (Donanım Algılama)").tag("automatic")
                    Text("Yüzen Ada (Floating Capsule)").tag("floatingCapsule")
                    Text("Fiziksel Çentik (Physical Notch)").tag("physicalNotch")
                }
                .onChange(of: notchPresentationMode) { _, _ in
                    NotificationCenter.default.post(name: .notchPresentationModeChanged, object: nil)
                }

                if notchPresentationMode == "floatingCapsule" || (!NotchPositionCalculator.hasPhysicalNotch() && notchPresentationMode == "automatic") {
                    Picker("Yüzen Ada Konumu", selection: $floatingIslandPosition) {
                        Text("Menü Çubuğunun Altında (8pt Boşluk)").tag("belowMenuBar")
                        Text("Ekranın En Üstünde (10pt Boşluk)").tag("screenTop")
                    }
                    .onChange(of: floatingIslandPosition) { _, _ in
                        NotificationCenter.default.post(name: .notchPresentationModeChanged, object: nil)
                    }

                    Text("Fiziksel çentiği olmayan ekranlarda (iMac, Mac mini, MacBook Air M1 veya harici monitörler) ada, 360° bağımsız yüzen ve sıvı cam efektli bir kapsül olarak konumlandırılır.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Görünüm & Animasyon") {
                Picker("Animasyon Stili", selection: $animationStyle) {
                    Text("Spring (Dynamic Island)").tag("spring")
                    Text("Yumuşak (Ease)").tag("ease")
                    Text("Hızlı (Snappy)").tag("fast")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Genişlik Çarpanı")
                    Slider(value: $widthMultiplier, in: 0.8...1.4, step: 0.05)
                    Text("\(Int(round(widthMultiplier * 100)))%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
            }

            if let viewModel {
                Section("Canlı Test & Öncelik Kuyruğu Simülasyonu") {
                    HStack(spacing: 8) {
                        Button("🎵 Now Playing") {
                            viewModel.simulateNowPlaying()
                        }
                        Button("⬇️ İndirme") {
                            viewModel.simulateDownload()
                        }
                        Button("⏱ Timer") {
                            viewModel.simulateTimer()
                        }
                        Button("⏹ Kapat") {
                            viewModel.dismiss()
                        }
                    }

                    HStack(spacing: 8) {
                        Button("🪫 Düşük Pil") {
                            viewModel.simulateBatteryLow()
                        }
                        Button("⚡️ Şarj") {
                            viewModel.simulateBatteryCharging()
                        }
                        Button("🎧 AirPods") {
                            viewModel.simulateBluetoothConnected()
                        }
                        Button("🔊 Ses HUD") {
                            viewModel.simulateVolumeHUD()
                        }
                    }

                    HStack(spacing: 8) {
                        Button("⚠️ İnternet Yok") {
                            viewModel.simulateNoInternet()
                        }
                        Button("🌐 Wi-Fi") {
                            viewModel.simulateWifiConnected()
                        }
                        Button("🛡 VPN") {
                            viewModel.simulateVPNConnected()
                        }
                        Button("☀️ Parlaklık") {
                            viewModel.simulateBrightnessHUD()
                        }
                    }

                    HStack(spacing: 8) {
                        Button("📸 Screenshot") {
                            viewModel.simulateScreenshot()
                        }
                        Button("📅 Toplantı Uyarısı (Meet)") {
                            viewModel.simulateCalendarUpcomingAlert()
                        }
                        Button("📅 Aktif Toplantı (Zoom)") {
                            viewModel.simulateCalendarActiveLiveActivity()
                        }
                    }

                    HStack(spacing: 8) {
                        Button("📶 Hotspot (%--)") {
                            viewModel.simulateHotspotUnknownBattery()
                        }
                        Button("🔄 Canlı Tara") {
                            HotspotManager.shared.refreshHotspotState()
                            viewModel.toggleHotspotManager()
                        }
                        Button("🪫 Düşük Pil (%15)") {
                            viewModel.simulateHotspotLowBattery()
                        }
                    }

                    HStack(spacing: 8) {
                        Button("📝 Hızlı Not (⌥⇧N)") {
                            viewModel.toggleQuickNote()
                        }
                        Button("🛡️ İzin Uyarısı") {
                            viewModel.simulateAccessibilityPermissionAlert()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 635)
        .onAppear {
            spotifyService.refreshPermissionStatus()
        }
    }
}
