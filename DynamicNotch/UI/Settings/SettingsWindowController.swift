// SettingsWindowController.swift
// DynamicNotch / UI / Settings
//
// Manages the standalone macOS Preferences window.

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {

    convenience init(viewModel: NotchViewModel? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DynamicNotch Ayarları"
        let hostingView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
