// DynamicNotchApp.swift
// DynamicNotch / App
//
// Pure AppKit @main entry point.
//
// Why not `struct DynamicNotchApp: SwiftUI.App`?
// ──────────────────────────────────────────────
// On macOS 15+ / 26+, `SwiftUI.App` automatically attempts to register the
// process with `com.apple.linkd.autoShortcut` (AppIntents daemon) on every
// view graph update, flooding the console with XPC Code=4097 errors in
// unsandboxed local builds.
// Using a direct `NSApplication` entry point gives us instant startup, zero
// `linkd` XPC noise, and full SwiftUI support via `NotchHostingView`.

import AppKit

@main
enum DynamicNotchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Code-level Application Constants

enum AppConfig {
    static let appName = "DynamicNotch"
    static let version = "1.8.16"
    static let build = "1.8.16"
}
