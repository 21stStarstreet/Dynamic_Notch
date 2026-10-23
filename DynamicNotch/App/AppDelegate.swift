// AppDelegate.swift
// DynamicNotch / App
//
// Central application coordinator.
// Responsibilities:
//   - Suppress Dock icon (accessory activation policy)
//   - Instantiate NotchViewModel (owns all observers)
//   - Instantiate NotchWindowController and wire it to the ViewModel
//   - Place a status bar item with Settings, Quick Simulation, and Quit menu items
//   - On first launch, poll MediaObserver for active music playback

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned Objects

    private var notchViewModel: NotchViewModel!
    private var notchWindowController: NotchWindowController!
    private var statusItem: NSStatusItem!
    private var settingsWindowController: SettingsWindowController?
    private var clipboardHotKeyManager: ClipboardHotKeyManager?
    private var timerHotKeyManager: TimerHotKeyManager?
    private var hideHotKeyManager: HideHotKeyManager?
    private var keyboardBrightnessHotKeyManager: KeyboardBrightnessHotKeyManager?
    private var externalDriveHotKeyManager: ExternalDriveHotKeyManager?
    private var calendarHotKeyManager: CalendarHotKeyManager?
    private var hotspotHotKeyManager: HotspotHotKeyManager?
    private var quickNoteHotKeyManager: QuickNoteHotKeyManager?
    private var quickReminderHotKeyManager: QuickReminderHotKeyManager?
    private var spotifyPermissionHotKeyManager: SpotifyPermissionHotKeyManager?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and application switcher; run purely as a menu-bar accessory.
        NSApp.setActivationPolicy(.accessory)

        // Setup standard Main Menu so standard Cmd+A/C/V/X/Z shortcuts work in all text fields
        setupMainMenu()

        // Register custom URL scheme handler for dynamicnotch://
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // ViewModel owns and starts all system observers.
        notchViewModel = NotchViewModel()
        notchViewModel.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        // Window controller creates and displays the notch NSWindow in Compact mode
        // (small wings on the left and right of the physical notch).
        notchWindowController = NotchWindowController(viewModel: notchViewModel)
        notchViewModel.windowController = notchWindowController

        // Present Welcome & Onboarding experience FIRST, before anything else!
        NotchOnboardingManager.shared.checkFirstLaunch()

        // Initialize global shortcut manager for Option + Shift + V or Cmd hold to open clipboard history
        clipboardHotKeyManager = ClipboardHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "V", "action": "clipboard"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleClipboardManager()
            }
        }

        // Initialize global shortcut manager for Option + Shift + T to open Timer
        timerHotKeyManager = TimerHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "T", "action": "timer"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleTimerManager()
            }
        }

        // Initialize global shortcut manager for Option + Shift + H to toggle hide/show Notch
        hideHotKeyManager = HideHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "H", "action": "hideNotch"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleHideNotch()
            }
        }

        // Initialize global shortcut manager for Keyboard Brightness (Option + F5/F6 or Ctrl + Option + Arrow)
        keyboardBrightnessHotKeyManager = KeyboardBrightnessHotKeyManager(
            onStepUp: { [weak self] fine in
                self?.notchViewModel.stepKeyboardBrightnessUp(fine: fine)
            },
            onStepDown: { [weak self] fine in
                self?.notchViewModel.stepKeyboardBrightnessDown(fine: fine)
            }
        )

        // Initialize global shortcut manager for Option + Shift + E to toggle External Drive card
        externalDriveHotKeyManager = ExternalDriveHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "E", "action": "externalDrive"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleExternalDriveManager()
            }
        }

        // Initialize global shortcut manager for Option + Shift + C to toggle Calendar card
        calendarHotKeyManager = CalendarHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "C", "action": "calendar"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleCalendarManager()
            }
        }

        // Initialize global shortcut manager for Option + Shift + P to toggle Hotspot card
        hotspotHotKeyManager = HotspotHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "P", "action": "hotspot"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleHotspotManager()
            }
        }

        // Initialize global shortcut manager for Option + Shift + N to open Quick Note
        quickNoteHotKeyManager = QuickNoteHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "N", "action": "quickNote"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleQuickNote()
            }
        }

        // Initialize global shortcut manager for Option + Shift + R to open Quick Reminder
        quickReminderHotKeyManager = QuickReminderHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "R", "action": "quickReminder"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleQuickReminder()
            }
        }

        // Initialize global test shortcut manager for Option + Shift + S to test Spotify Permission Dialog
        spotifyPermissionHotKeyManager = SpotifyPermissionHotKeyManager { [weak self] in
            NotificationCenter.default.post(
                name: .notchShortcutTriggered,
                object: nil,
                userInfo: ["key": "S", "action": "spotifyPermission"]
            )
            if !NotchOnboardingManager.shared.isOnboardingActive {
                self?.notchViewModel.toggleSpotifyPermissionDialog()
            }
        }

        setupStatusBarItem()

        // Poll active media players (Spotify / Apple Music) shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.notchViewModel.mediaObserver.fetchCurrentInfo()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Explicit teardown is handled by deinit of observers.
    }

    // MARK: - System Edit Menu Setup (Cmd + A, C, V, X, Z)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Submenu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "DynamicNotch'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 2. Edit Submenu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Düzen")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "capsule.fill",
                accessibilityDescription: "DynamicNotch"
            )
        }

        let menu = NSMenu()

        // Release Version Header (Soluk / Dimmed)
        let versionItem = NSMenuItem(title: "DynamicNotch v\(AppConfig.version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        // Timer Submenu for fast everyday productivity
        let timerMenu = NSMenu()
        addMenuItem(to: timerMenu, title: "1 Dakika", action: #selector(startTimer1m))
        addMenuItem(to: timerMenu, title: "5 Dakika", action: #selector(startTimer5m))
        addMenuItem(to: timerMenu, title: "10 Dakika", action: #selector(startTimer10m))
        addMenuItem(to: timerMenu, title: "15 Dakika", action: #selector(startTimer15m))
        addMenuItem(to: timerMenu, title: "25 Dakika (Pomodoro)", action: #selector(startTimer25m))
        timerMenu.addItem(.separator())
        addMenuItem(to: timerMenu, title: "Zamanlayıcıyı Durdur / İptal Et", action: #selector(cancelTimer))

        let timerSubmenuItem = NSMenuItem(title: "Zamanlayıcı (Timer) Başlat", action: nil, keyEquivalent: "")
        timerSubmenuItem.submenu = timerMenu
        menu.addItem(timerSubmenuItem)

        // Keyboard Backlight Submenu for instant everyday control
        let kbMenu = NSMenu()
        addMenuItem(to: kbMenu, title: "Parlaklığı Artır (⌥F6 veya ⌃⌥↑)", action: #selector(stepKeyboardBrightnessUp))
        addMenuItem(to: kbMenu, title: "Parlaklığı Azalt (⌥F5 veya ⌃⌥↓)", action: #selector(stepKeyboardBrightnessDown))
        kbMenu.addItem(.separator())
        addMenuItem(to: kbMenu, title: "%0 (Işığı Kapat)", action: #selector(setKeyboardBrightness0))
        addMenuItem(to: kbMenu, title: "%25", action: #selector(setKeyboardBrightness25))
        addMenuItem(to: kbMenu, title: "%50", action: #selector(setKeyboardBrightness50))
        addMenuItem(to: kbMenu, title: "%75", action: #selector(setKeyboardBrightness75))
        addMenuItem(to: kbMenu, title: "%100 (Maksimum)", action: #selector(setKeyboardBrightness100))

        let kbSubmenuItem = NSMenuItem(title: "Klavye Aydınlatması", action: nil, keyEquivalent: "")
        kbSubmenuItem.submenu = kbMenu
        menu.addItem(kbSubmenuItem)

        // Simulation Submenu for instant verification & testing
        let testMenu = NSMenu()
        addMenuItem(to: testMenu, title: "🎵 Now Playing Göster", action: #selector(testNowPlaying))
        addMenuItem(to: testMenu, title: "⚡️ Şarj Oluyor Göster", action: #selector(testBatteryCharging))
        addMenuItem(to: testMenu, title: "🪫 Düşük Batarya Göster", action: #selector(testBatteryLow))
        addMenuItem(to: testMenu, title: "🔋 Batarya Dolu Göster", action: #selector(testBatteryFull))
        addMenuItem(to: testMenu, title: "🎧 AirPods Bağlandı (Notch)", action: #selector(testBluetooth))
        addMenuItem(to: testMenu, title: "🎧 AirPods Kart Animasyonu (Tam)", action: #selector(testAirPodsCard))
        addMenuItem(to: testMenu, title: "🔊 Ses Seviyesi HUD Göster", action: #selector(testVolume))
        addMenuItem(to: testMenu, title: "🔇 Sessize Alındı / Ses Açıldı Göster", action: #selector(testMuted))
        addMenuItem(to: testMenu, title: "⌨️ Klavye Aydınlatması HUD Göster", action: #selector(testKeyboardBrightness))
        addMenuItem(to: testMenu, title: "🌙 Rahatsız Etmeyin (Odak) Göster", action: #selector(testFocus))
        addMenuItem(to: testMenu, title: "📶 Wi-Fi Bağlandı Göster", action: #selector(testWifi))
        addMenuItem(to: testMenu, title: "🛡 VPN Bağlandı (Uptime Sayacı)", action: #selector(testVPN))
        addMenuItem(to: testMenu, title: "⬇️ İndirme Göster", action: #selector(testDownload))
        addMenuItem(to: testMenu, title: "⏱ Zamanlayıcı (Timer 2dk) Göster", action: #selector(testTimer))
        addMenuItem(to: testMenu, title: "🛸 Çift Canlı Aktivite: Müzik + Zamanlayıcı (Uydu Orb)", action: #selector(testDualLiveActivity))
        addMenuItem(to: testMenu, title: "🛸 Çift Parlaklık: Ekran (Notch) + Klavye (Sol Daire)", action: #selector(testDualBrightness))
        addMenuItem(to: testMenu, title: "🛸 Orkestrasyon: Müzik + Timer + Ses + Parlaklık", action: #selector(testTripleCollision))
        addMenuItem(to: testMenu, title: "🌐 İnternet Bağlantısı Yok Dialogu", action: #selector(testNoInternet))
        addMenuItem(to: testMenu, title: "📸 Ekran Görüntüsü Alındı Dialogu", action: #selector(testScreenshot))
        addMenuItem(to: testMenu, title: "💾 Harici Sürücü Takıldı Simülasyonu", action: #selector(testExternalDrive))
        addMenuItem(to: testMenu, title: "📅 Toplantı Başlıyor Uyarısı (Meet)", action: #selector(testCalendarUpcomingAlert))
        addMenuItem(to: testMenu, title: "📅 Aktif Toplantı Canlı Aktivitesi (Zoom)", action: #selector(testCalendarActiveMeeting))
        addMenuItem(to: testMenu, title: "📶 Hotspot Bağlantısı (Canlı / %--)", action: #selector(testHotspotConnected))
        addMenuItem(to: testMenu, title: "🪫 Hotspot Düşük Batarya (%15) Uyarısı", action: #selector(testHotspotLowBattery))
        addMenuItem(to: testMenu, title: "🔴 Ekran Kaydı Başlat / Bitir (Canlı Aktivite)", action: #selector(testScreenRecordingToggle))
        addMenuItem(to: testMenu, title: "📝 Hızlı Not Ekleme Kartı (⌥⇧N)", action: #selector(openQuickNote))
        addMenuItem(to: testMenu, title: "✅ Hızlı Anımsatıcı Ekleme Kartı (⌥⇧R)", action: #selector(openQuickReminder))
        addMenuItem(to: testMenu, title: "🎵 Spotify Erişim İzni Dialogu (⌥⇧S)", action: #selector(testSpotifyPermission))
        addMenuItem(to: testMenu, title: "✨ Karşılama Ekranı (Onboarding)", action: #selector(showOnboarding))
        testMenu.addItem(.separator())
        addMenuItem(to: testMenu, title: "⏹ Notch'u Sıfırla (Kapat)", action: #selector(testDismiss))

        let testSubmenuItem = NSMenuItem(title: "🧪 Test Bildirimi Gönder", action: nil, keyEquivalent: "")
        testSubmenuItem.submenu = testMenu
        menu.addItem(testSubmenuItem)

        addMenuItem(to: menu, title: "✨ Karşılama ve Tanıtım (Onboarding)", action: #selector(showOnboarding))
        menu.addItem(.separator())

        let clipboardItem = NSMenuItem(
            title: "Pano Geçmişini Aç (⌥⇧V)",
            action: #selector(openClipboard),
            keyEquivalent: ""
        )
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        let hideItem = NSMenuItem(
            title: "Dinamik Çentiği Gizle / Göster (⌥⇧H)",
            action: #selector(toggleHideNotch),
            keyEquivalent: ""
        )
        hideItem.target = self
        menu.addItem(hideItem)

        let driveItem = NSMenuItem(
            title: "Harici Sürücüler (⌥⇧E)",
            action: #selector(openExternalDrives),
            keyEquivalent: ""
        )
        driveItem.target = self
        menu.addItem(driveItem)

        let calendarItem = NSMenuItem(
            title: "Takvim & Toplantılar (⌥⇧C)",
            action: #selector(openCalendarCard),
            keyEquivalent: ""
        )
        calendarItem.target = self
        menu.addItem(calendarItem)

        let hotspotItem = NSMenuItem(
            title: "Kişisel Erişim Noktası (⌥⇧P)",
            action: #selector(openHotspotCard),
            keyEquivalent: ""
        )
        hotspotItem.target = self
        menu.addItem(hotspotItem)

        let noteItem = NSMenuItem(
            title: "Hızlı Not Ekle (⌥⇧N)",
            action: #selector(openQuickNote),
            keyEquivalent: ""
        )
        noteItem.target = self
        menu.addItem(noteItem)

        let reminderItem = NSMenuItem(
            title: "Hızlı Anımsatıcı Ekle (⌥⇧R)",
            action: #selector(openQuickReminder),
            keyEquivalent: ""
        )
        reminderItem.target = self
        menu.addItem(reminderItem)

        let screenshotToggleItem = NSMenuItem(
            title: "Ekran Görüntüsü Bildirimleri",
            action: #selector(toggleScreenshotNotifications(_:)),
            keyEquivalent: ""
        )
        screenshotToggleItem.target = self
        screenshotToggleItem.state = notchViewModel.showScreenshots ? .on : .off
        menu.addItem(screenshotToggleItem)

        let desktopPermItem = NSMenuItem(
            title: "Masaüstü Klasör İznini Aç (Gizlilik)…",
            action: #selector(openDesktopPrivacySettings),
            keyEquivalent: ""
        )
        desktopPermItem.target = self
        menu.addItem(desktopPermItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Ayarlar…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Çıkış",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func addMenuItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(viewModel: notchViewModel)
        }
        settingsWindowController?.show()
    }

    @objc private func startTimer1m()   { notchViewModel.timerObserver.startTimer(duration: 60, title: "1 Dakika") }
    @objc private func startTimer5m()   { notchViewModel.timerObserver.startTimer(duration: 300, title: "5 Dakika") }
    @objc private func startTimer10m()  { notchViewModel.timerObserver.startTimer(duration: 600, title: "10 Dakika") }
    @objc private func startTimer15m()  { notchViewModel.timerObserver.startTimer(duration: 900, title: "15 Dakika") }
    @objc private func startTimer25m()  { notchViewModel.timerObserver.startTimer(duration: 1500, title: "Pomodoro") }
    @objc private func cancelTimer()    { notchViewModel.timerObserver.cancel() }

    @objc private func testNowPlaying()      { notchViewModel.simulateNowPlaying() }
    @objc private func testBatteryCharging() { notchViewModel.simulateBatteryCharging() }
    @objc private func testBatteryLow()      { notchViewModel.simulateBatteryLow() }
    @objc private func testBatteryFull()     { notchViewModel.simulateBatteryFull() }
    @objc private func testBluetooth()       { notchViewModel.simulateBluetoothConnected() }
    @objc private func testVolume()          { notchViewModel.simulateVolumeHUD() }
    @objc private func testMuted()           { notchViewModel.simulateMuted() }
    @objc private func testKeyboardBrightness() { notchViewModel.simulateKeyboardBrightnessHUD() }
    @objc private func testDualBrightness()  { notchViewModel.simulateDualBrightness() }
    @objc private func testTripleCollision() { notchViewModel.simulateTripleCollision() }
    @objc private func stepKeyboardBrightnessUp() { notchViewModel.stepKeyboardBrightnessUp() }
    @objc private func stepKeyboardBrightnessDown() { notchViewModel.stepKeyboardBrightnessDown() }
    @objc private func setKeyboardBrightness0() { notchViewModel.setKeyboardBrightness(0.0) }
    @objc private func setKeyboardBrightness25() { notchViewModel.setKeyboardBrightness(0.25) }
    @objc private func setKeyboardBrightness50() { notchViewModel.setKeyboardBrightness(0.50) }
    @objc private func setKeyboardBrightness75() { notchViewModel.setKeyboardBrightness(0.75) }
    @objc private func setKeyboardBrightness100() { notchViewModel.setKeyboardBrightness(1.0) }
    @objc private func testFocus()           { notchViewModel.simulateFocusChanged() }
    @objc private func testWifi()            { notchViewModel.simulateWifiConnected() }
    @objc private func testVPN()             { notchViewModel.simulateVPNConnected() }
    @objc private func testDownload()        { notchViewModel.simulateDownload() }
    @objc private func testTimer()           { notchViewModel.simulateTimer() }
    @objc private func testNoInternet()      { notchViewModel.simulateNoInternet() }
    @objc private func testScreenshot()      { notchViewModel.simulateScreenshot() }
    @objc private func testDismiss()         { notchViewModel.dismiss() }
    @objc private func showOnboarding()      { NotchOnboardingManager.shared.restartOnboarding() }
    @objc private func openClipboard()       { notchViewModel.toggleClipboardManager() }
    @objc private func toggleHideNotch()     { notchViewModel.toggleHideNotch() }

    @objc private func toggleScreenshotNotifications(_ sender: NSMenuItem) {
        notchViewModel.showScreenshots.toggle()
        sender.state = notchViewModel.showScreenshots ? .on : .off
    }

    @objc private func openDesktopPrivacySettings() {
        ScreenshotObserver.openPrivacySettings()
    }

    @objc private func testAirPodsCard() {
        notchViewModel.simulateBluetoothConnected()
    }

    @objc private func testDualLiveActivity() {
        notchViewModel.simulateNowPlaying()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.notchViewModel.simulateTimer()
        }
    }


    @objc private func openExternalDrives() {
        notchViewModel.toggleExternalDriveManager()
    }

    @objc private func testExternalDrive() {
        let dummy = ExternalDriveItem(
            id: "test-t7-simulation",
            name: "Samsung T7 Shield",
            url: URL(fileURLWithPath: "/Volumes/Samsung T7 Shield"),
            mountPath: "/Volumes/Samsung T7 Shield",
            totalCapacityBytes: 1_000_000_000_000,
            availableCapacityBytes: 642_000_000_000,
            usedCapacityBytes: 358_000_000_000,
            usedPercentage: 0.358,
            driveType: .ssd,
            isEjectable: true,
            isRemovable: true
        )
        notchViewModel.handleIncoming(.externalDrive([dummy]))
    }

    @objc private func openCalendarCard() {
        notchViewModel.toggleCalendarManager()
    }

    @objc private func testCalendarUpcomingAlert() {
        notchViewModel.simulateCalendarUpcomingAlert()
    }

    @objc private func testCalendarActiveMeeting() {
        notchViewModel.simulateCalendarActiveLiveActivity()
    }

    @objc private func openHotspotCard() {
        notchViewModel.toggleHotspotManager()
    }

    @objc private func testHotspotConnected() {
        notchViewModel.simulateHotspotConnected(batteryLevel: nil)
    }

    @objc private func testHotspotUnknownBattery() {
        notchViewModel.simulateHotspotUnknownBattery()
    }

    @objc private func testHotspotLowBattery() {
        notchViewModel.simulateHotspotLowBattery()
    }

    @objc private func testScreenRecordingToggle() {
        notchViewModel.simulateScreenRecordingToggle()
    }

    @objc private func openQuickNote() {
        notchViewModel.toggleQuickNote()
    }

    @objc private func openQuickReminder() {
        notchViewModel.toggleQuickReminder()
    }

    @objc private func testSpotifyPermission() {
        notchViewModel.toggleSpotifyPermissionDialog()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - URL Scheme Handler

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "dynamicnotch" {
                SpotifyAPIService.shared.handleCallbackURL(url)
            }
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        if url.scheme == "dynamicnotch" {
            SpotifyAPIService.shared.handleCallbackURL(url)
        }
    }
}
