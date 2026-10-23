// ScreenshotObserver.swift
// DynamicNotch / Observers
//
// Bulletproof multi-tier detection engine for macOS screenshots:
//
// Tier 1: System Screencapture UI Lifecycle Observer (NSWorkspace)
//         Detects when `com.apple.screencaptureui` terminates or deactivates
//         (Cmd+Shift+3/4/5) and immediately triggers an instantaneous scan.
// Tier 2: Kernel FSEventStream with Hierarchy Deduplication
//         Monitors Desktop, custom screenshot directories (including location-last),
//         Downloads, Pictures, and Screenshot subfolders with zero dropped events.
// Tier 3: Directory Modification Poller (0.5s timer)
//         Zero-CPU folder mtime comparison across all monitored screenshot folders.
//         Also dynamically syncs macOS screenshot location changes every 3s.
// Tier 4: Clipboard Image Observer (NSPasteboard)
//         Detects screenshots taken to clipboard (Cmd+Ctrl+Shift+3/4).

import Foundation
import AppKit
import Combine
import CoreServices
import Darwin

// MARK: - ScreenshotObserver

final class ScreenshotObserver: ObservableObject {

    // MARK: - Published State

    @Published private(set) var screenshotEvent: ScreenshotItem?

    // MARK: - Private State

    private var eventStream: FSEventStreamRef?
    private var metadataQuery: NSMetadataQuery?
    private var pollTimer: DispatchSourceTimer?
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Ancestor root directories passed to FSEventStreamCreate (deduplicated to prevent overlapping streams)
    private var fseventRoots: [URL] = []

    /// All specific directories whose mtime is tracked and polled every 0.5s
    private var monitoredFolders: [URL] = []
    private var folderLastModDates: [String: Date] = [:]
    private var activeSharePickerDelegate: NSSharingServicePickerDelegate?

    // Thread-safe set of paths already processed
    private let handledQueue = DispatchQueue(label: "com.dynamicnotch.ssobserver.handled", attributes: .concurrent)
    private var _handledPaths: Set<String> = []
    private var handledPaths: Set<String> {
        get { handledQueue.sync { _handledPaths } }
    }
    private func markHandled(_ path: String) {
        let normalized = (path as NSString).standardizingPath
        handledQueue.async(flags: .barrier) { self._handledPaths.insert(normalized) }
    }
    private func isHandled(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        return handledQueue.sync { self._handledPaths.contains(normalized) }
    }

    let validExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
    let processingQueue = DispatchQueue(label: "com.dynamicnotch.ssobserver.processing", qos: .userInitiated)

    // Clipboard tracking
    private var lastPasteboardChangeCount: Int = NSPasteboard.general.changeCount
    private var isSelfWritingPasteboard: Bool = false
    private var lastScreencaptureuiEventTime: Date?

    // Preference refresh tick counter (0.5s * 6 = 3s)
    private var pollTickCount: Int = 0

    // MARK: - Init / Deinit

    init() {
        print("[ScreenshotObserver] 🚀 Başlatılıyor...")
        resolveWatchedFolders()
        setupFSEventStream()
        setupWorkspaceAppObserver()
        setupSpotlightQuery()
        setupPollingTimer()
        print("[ScreenshotObserver] ✅ Tüm 4 izleme katmanı aktif. İzlenen klasörler: \(monitoredFolders.map(\.path))")
    }

    deinit {
        stopWatching()
        print("[ScreenshotObserver] 🛑 Durduruldu.")
    }

    // MARK: - Directory Resolution

    /// Resolves the primary screenshot destination set by macOS.
    /// In macOS, terminal commands write to `location`, while the native Screenshot UI
    /// (Cmd+Shift+5 -> Options -> Other Location) writes to `location-last`.
    static func primaryScreenshotDirectory() -> URL {
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)

        // 1. "location" preference (set by terminal: defaults write com.apple.screencapture location ...)
        if let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = NSString(string: raw).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                print("[ScreenshotObserver] 📁 com.apple.screencapture (location): \(url.path)")
                return url
            }
        }

        // 2. "location-last" preference (set by native macOS Screenshot utility GUI)
        if let rawLast = CFPreferencesCopyAppValue("location-last" as CFString, "com.apple.screencapture" as CFString) as? String,
           !rawLast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = NSString(string: rawLast).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                print("[ScreenshotObserver] 📁 com.apple.screencapture (location-last): \(url.path)")
                return url
            }
        }

        // 3. Fallback to Desktop
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Desktop").expandingTildeInPath)
        print("[ScreenshotObserver] 📁 Masaüstü varsayılan hedefi: \(desktop.path)")
        return desktop.standardizedFileURL
    }

    /// Legacy alias for primaryScreenshotDirectory
    static func resolvedScreenshotDirectory() -> URL {
        primaryScreenshotDirectory()
    }

    /// Helper to find subdirectories matching common screenshot naming patterns
    private static func findScreenshotSubdirectories(in parent: URL) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return results }

        let keywords = ["ekran", "screenshot", "goruntu", "görüntü", "resim", "capture"]

        for fileURL in contents {
            guard let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  vals.isDirectory == true else { continue }

            let name = fileURL.lastPathComponent.lowercased()
            let matches = keywords.contains { name.contains($0) }
            if matches {
                results.append(fileURL.standardizedFileURL)

                // Also check 1 level deeper (e.g. Desktop/Ekran Görüntüleri/Tüm alınan SS'ler)
                if let subContents = try? fm.contentsOfDirectory(
                    at: fileURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for subURL in subContents {
                        if let subVals = try? subURL.resourceValues(forKeys: [.isDirectoryKey]),
                           subVals.isDirectory == true {
                            results.append(subURL.standardizedFileURL)
                        }
                    }
                }
            }
        }
        return results
    }

    private func resolveWatchedFolders() {
        var specificFolders: [URL] = []
        var seenPaths = Set<String>()

        func addFolder(_ url: URL) {
            let std = url.standardizedFileURL
            let path = std.path
            guard !seenPaths.contains(path) else { return }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                seenPaths.insert(path)
                specificFolders.append(std)
            }
        }

        // 1. Primary screenshot destination (reads "location" & "location-last")
        let primary = Self.primaryScreenshotDirectory()
        addFolder(primary)

        // 2. Secondary preferences if "location" and "location-last" differ
        if let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addFolder(URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath))
        }
        if let rawLast = CFPreferencesCopyAppValue("location-last" as CFString, "com.apple.screencapture" as CFString) as? String,
           !rawLast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addFolder(URL(fileURLWithPath: NSString(string: rawLast).expandingTildeInPath))
        }

        // 3. Desktop and any screenshot subfolders on Desktop
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            addFolder(desktop)
            Self.findScreenshotSubdirectories(in: desktop).forEach { addFolder($0) }
        }

        // 4. Pictures and any screenshot subfolders in Pictures
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            addFolder(pictures)
            addFolder(pictures.appendingPathComponent("Screenshots"))
            Self.findScreenshotSubdirectories(in: pictures).forEach { addFolder($0) }
        }

        // 5. Downloads
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            addFolder(downloads)
        }

        // 6. Documents and Screenshots subfolder in Documents
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            addFolder(documents.appendingPathComponent("Screenshots"))
            Self.findScreenshotSubdirectories(in: documents).forEach { addFolder($0) }
        }

        monitoredFolders = specificFolders

        // Build deduplicated roots for FSEventStream:
        // FSEvents watches recursively, so we eliminate any path whose ancestor is already in uniqueRoots.
        var uniqueRoots: [URL] = []
        for candidate in specificFolders {
            let candidatePath = candidate.path
            let isSubfolderOfExisting = uniqueRoots.contains { root in
                let rootPath = root.path
                return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
            }
            if !isSubfolderOfExisting {
                uniqueRoots.removeAll { existing in
                    let existingPath = existing.path
                    return existingPath.hasPrefix(candidatePath + "/")
                }
                uniqueRoots.append(candidate)
            }
        }
        fseventRoots = uniqueRoots

        // Cache initial modification dates and mark pre-existing files as handled
        let now = Date()
        for folder in monitoredFolders {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: folder.path),
               let modDate = attrs[.modificationDate] as? Date {
                folderLastModDates[folder.path] = modDate
            }

            if let files = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for file in files {
                    let vals = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let fileDate = vals?.creationDate ?? vals?.contentModificationDate ?? Date.distantPast
                    if now.timeIntervalSince(fileDate) > 8.0 {
                        markHandled(file.standardizedFileURL.path)
                    }
                }
            }
        }
    }

    /// Dynamically re-checks com.apple.screencapture preferences. If screenshot folder changed, updates live watchers.
    private func refreshWatchedFoldersIfChanged() {
        let currentPrimary = Self.primaryScreenshotDirectory()
        let isKnown = monitoredFolders.contains { $0.path == currentPrimary.path }
        if !isKnown {
            print("[ScreenshotObserver] 🔄 Ekran görüntüsü hedefi değişti: \(currentPrimary.path). İzleyiciler güncelleniyor...")
            resolveWatchedFolders()
            restartFSEventStream()
        }
    }

    // MARK: - Tier 1: Screencapture App Lifecycle Observer (Instantaneous)

    private func setupWorkspaceAppObserver() {
        let center = NSWorkspace.shared.notificationCenter

        // Fires the exact instant screencapture completes (selection mouse-up or Cmd+Shift+3 capture)
        let termObs = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.screencaptureui" else { return }
            print("[ScreenshotObserver] ⚡️ screencaptureui kapandı! Anlık tarama başlatılıyor...")
            self?.lastScreencaptureuiEventTime = Date()
            self?.scanAllWatchedFolders()
        }
        workspaceObservers.append(termObs)

        let deactObs = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.screencaptureui" else { return }
            print("[ScreenshotObserver] ⚡️ screencaptureui pasife geçti! Taranıyor...")
            self?.lastScreencaptureuiEventTime = Date()
            self?.scanAllWatchedFolders()
        }
        workspaceObservers.append(deactObs)
    }

    // MARK: - Tier 2: Kernel FSEventStream

    private func setupFSEventStream() {
        guard !fseventRoots.isEmpty else { return }

        let pathsToWatch = fseventRoots.map(\.path) as CFArray
        print("[ScreenshotObserver] 🔭 FSEventStream başlatılıyor: \(fseventRoots.map(\.path))")

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let observer = Unmanaged<ScreenshotObserver>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

            for path in paths {
                let url = URL(fileURLWithPath: path)
                let ext = url.pathExtension.lowercased()

                if observer.validExtensions.contains(ext) {
                    print("[ScreenshotObserver] 🔔 FSEvent görsel dosya: \(url.lastPathComponent)")
                    observer.processPotentialScreenshot(url: url)
                } else {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        observer.processingQueue.async {
                            observer.scanFolderDirectly(folder: url, recursive: true, maxDepth: 2)
                        }
                    }
                }
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.10, // 100ms ultra-low coalescing latency
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagUseCFTypes
            )
        ) else {
            print("[ScreenshotObserver] ❌ FSEventStreamCreate başarısız oldu!")
            return
        }

        let fsQueue = DispatchQueue(label: "com.dynamicnotch.ssobserver.fsevents", qos: .userInitiated)
        FSEventStreamSetDispatchQueue(stream, fsQueue)
        let started = FSEventStreamStart(stream)
        self.eventStream = stream

        if started {
            print("[ScreenshotObserver] ✅ FSEventStream başarıyla başlatıldı.")
        } else {
            print("[ScreenshotObserver] ❌ FSEventStreamStart BAŞARISIZ!")
        }
    }

    private func restartFSEventStream() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        setupFSEventStream()
    }

    // MARK: - Tier 3: Smart Polling & Clipboard Check (0.5s)

    private func setupPollingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.checkFolderModifications()
            self.checkClipboardForScreenshot()

            self.pollTickCount += 1
            if self.pollTickCount >= 6 {
                self.pollTickCount = 0
                self.refreshWatchedFoldersIfChanged()
            }
        }
        timer.resume()
        self.pollTimer = timer
    }

    private func checkFolderModifications() {
        for folder in monitoredFolders {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: folder.path),
                  let currentModDate = attrs[.modificationDate] as? Date else { continue }

            let lastKnown = folderLastModDates[folder.path] ?? Date.distantPast
            if currentModDate > lastKnown {
                folderLastModDates[folder.path] = currentModDate
                scanFolderDirectly(folder: folder, recursive: false)
            }
        }
    }

    func scanAllWatchedFolders() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            let primary = Self.primaryScreenshotDirectory()
            self.scanFolderDirectly(folder: primary, recursive: true, maxDepth: 2)

            for folder in self.monitoredFolders {
                self.scanFolderDirectly(folder: folder, recursive: false)
            }
        }
    }

    func scanFolderDirectly(folder: URL, recursive: Bool = true, maxDepth: Int = 1) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        for file in files {
            let ext = file.pathExtension.lowercased()
            if validExtensions.contains(ext) {
                let vals = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let fileDate = vals?.creationDate ?? vals?.contentModificationDate ?? Date.distantPast

                if abs(now.timeIntervalSince(fileDate)) <= 120.0 {
                    processPotentialScreenshot(url: file)
                }
            } else if recursive && maxDepth > 0 {
                let vals = try? file.resourceValues(forKeys: [.isDirectoryKey])
                if vals?.isDirectory == true {
                    scanFolderDirectly(folder: file, recursive: recursive, maxDepth: maxDepth - 1)
                }
            }
        }
    }

    // MARK: - Tier 4: Clipboard Screenshot Observer (Cmd+Ctrl+Shift+3/4)

    private func checkClipboardForScreenshot() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = currentCount

        guard !isSelfWritingPasteboard else { return }

        guard let types = pb.types else { return }

        // 1. Files copied in Finder (Cmd+C on image or any file):
        // NEVER treat file copies as screenshots! They belong in the Clipboard History.
        let hasFileURL = types.contains(NSPasteboard.PasteboardType("public.file-url")) ||
                         types.contains(.fileURL) ||
                         types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        if hasFileURL {
            return
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: { $0.isFileURL }) {
            return
        }

        // 2. Ignore web browser copies (Chrome, Safari, Firefox put HTML/URL metadata on clipboard)
        let nonScreenshotTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("public.url-name"),
            NSPasteboard.PasteboardType("Apple Web Archive pasteboard type"),
            NSPasteboard.PasteboardType("com.apple.webarchive")
        ]
        if types.contains(where: { nonScreenshotTypes.contains($0) }) {
            return
        }

        // 3. Ignore vendor app copies (Photoshop, Figma, Slack, Photos, etc.)
        let hasAppMetadata = types.contains { type in
            let r = type.rawValue
            return r.hasPrefix("com.adobe") || r.hasPrefix("com.figma") ||
                   r.hasPrefix("org.videolan") || r.hasPrefix("com.tinyspeck") ||
                   r.hasPrefix("com.apple.Photos")
        }
        if hasAppMetadata {
            return
        }

        // 4. Must contain image data
        guard types.contains(.png) || types.contains(.tiff) else { return }

        // 5. To be a true screenshot taken to clipboard (Cmd+Ctrl+Shift+3 or Cmd+Ctrl+Shift+4):
        // Either screencaptureui was active in the last 4 seconds,
        // OR the pasteboard contains strictly native screencapture output (typically only public.tiff/png).
        let screencaptureuiWasRecent = {
            if let lastTime = lastScreencaptureuiEventTime {
                return Date().timeIntervalSince(lastTime) <= 4.0
            }
            return false
        }()

        if !screencaptureuiWasRecent {
            // macOS Cmd+Ctrl+Shift+3 produces only public.tiff / public.png without rich application types
            if types.count > 4 {
                return
            }
        }

        // Extract image
        guard let image = NSImage(pasteboard: pb) else { return }

        // Save a cached copy to temp directory so AirDrop / WhatsApp / Preview have a valid fileURL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Screenshot_Clipboard_\(Int(Date().timeIntervalSince1970)).png")

        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: tempURL)
        }

        print("[ScreenshotObserver] 📋 Panoya ekran görüntüsü alındı (Gerçek Screenshot kısayolu)!")
        let thumbnail = createThumbnail(from: image, maxDimension: 512)
        let item = ScreenshotItem(fileURL: tempURL, thumbnail: thumbnail, createdAt: Date())

        DispatchQueue.main.async { [weak self] in
            self?.screenshotEvent = item
        }
    }

    // MARK: - Spotlight Query (Tier 2 Fallback)

    private func setupSpotlightQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpotlightResults(query: query)
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpotlightResults(query: query)
        }

        query.start()
        self.metadataQuery = query
    }

    private func handleSpotlightResults(query: NSMetadataQuery) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let now = Date()
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let creationDate = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date.distantPast
            guard abs(now.timeIntervalSince(creationDate)) <= 60.0 else { continue }
            guard !isHandled(url.standardizedFileURL.path) else { continue }
            processPotentialScreenshot(url: url)
        }
    }

    // MARK: - Monitoring Teardown

    private func stopWatching() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        pollTimer?.cancel()
        pollTimer = nil
        metadataQuery?.stop()
        metadataQuery = nil

        let center = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            center.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Screenshot Verification

    private func isScreenshotFile(url: URL) -> Bool {
        // 1. If screencaptureui was recently active (within 5 seconds), this file was generated by it!
        if let lastTime = lastScreencaptureuiEventTime,
           Date().timeIntervalSince(lastTime) <= 5.0 {
            return true
        }

        // 2. Check macOS extended attribute kMDItemIsScreenCapture
        let attrSize = getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0)
        if attrSize > 0 {
            return true
        }

        // 3. Check filename pattern against macOS localized screenshot prefixes
        let filename = url.lastPathComponent.lowercased()
        let prefixes = [
            "ekran resmi", "ekran görüntüsü", "ekran kaydı",
            "screen shot", "screenshot", "screen recording",
            "capture d’écran", "capture d'ecran",
            "bildschirmfoto", "captura de pantalla",
            "istantanea", "schermafbeelding",
            "captura de ecrã", "captura de ecra",
            "снимок экрана", "スクリーンショット", "스크린샷", "屏幕截图"
        ]

        if let customName = CFPreferencesCopyAppValue("name" as CFString, "com.apple.screencapture" as CFString) as? String,
           !customName.isEmpty {
            if filename.hasPrefix(customName.lowercased()) {
                return true
            }
        }

        for prefix in prefixes {
            if filename.hasPrefix(prefix) {
                return true
            }
        }

        return false
    }

    // MARK: - Screenshot Processing Pipeline

    func processPotentialScreenshot(url: URL, retryCount: Int = 0) {
        let path = url.standardizedFileURL.path
        let ext = url.pathExtension.lowercased()

        // 1. Extension filter
        guard validExtensions.contains(ext) else { return }

        // 2. Skip hidden or temporary partial files
        let filename = url.lastPathComponent
        guard !filename.hasPrefix(".") else { return }

        // 3. Deduplication check
        guard !isHandled(path) else { return }

        // 4. Verify that this file is an actual screenshot (not an arbitrary photo, download, or copied image)
        guard isScreenshotFile(url: url) else { return }

        // 5. Check file existence & readiness
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return
        }

        // 5. Check file size
        let fileSize: Int64 = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            if let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = vals.fileSize {
                return Int64(size)
            }
            return 0
        }()

        if fileSize < 100 {
            // File is still being flushed by macOS screencapture daemon
            if retryCount < 15 {
                processingQueue.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                    self?.processPotentialScreenshot(url: url, retryCount: retryCount + 1)
                }
            }
            return
        }

        // 6. Timestamp check (within 120 seconds)
        let now = Date()
        let fileDate: Date = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                return (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date) ?? now
            }
            let vals = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return vals?.creationDate ?? vals?.contentModificationDate ?? now
        }()

        guard abs(now.timeIntervalSince(fileDate)) <= 120.0 else {
            return
        }

        // Mark handled immediately to prevent double alerts
        markHandled(path)
        print("[ScreenshotObserver] 📸 Yeni ekran görüntüsü algılandı: \(filename) (\(fileSize) byte)")

        // Load image and publish
        processingQueue.async { [weak self] in
            self?.loadAndPublish(url: url, attempt: 0)
        }
    }

    private func loadAndPublish(url: URL, attempt: Int) {
        guard let image = NSImage(contentsOf: url) else {
            if attempt < 10 {
                processingQueue.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                    self?.loadAndPublish(url: url, attempt: attempt + 1)
                }
            } else {
                print("[ScreenshotObserver] ❌ Görsel açılamadı: \(url.lastPathComponent)")
            }
            return
        }

        let thumbnail = createThumbnail(from: image, maxDimension: 512)
        let item = ScreenshotItem(fileURL: url, thumbnail: thumbnail, createdAt: Date())

        print("[ScreenshotObserver] 🎉 Ekran görüntüsü bildirim olarak yayınlanıyor: \(url.lastPathComponent)")

        DispatchQueue.main.async { [weak self] in
            self?.screenshotEvent = item
        }
    }

    // MARK: - Thumbnail Generation

    private func createThumbnail(from image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let targetSize = NSSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )

        let result = NSImage(size: targetSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        result.unlockFocus()
        return result
    }

    // MARK: - Share Actions

    func shareViaAirDrop(for item: ScreenshotItem) {
        if let service = NSSharingService(named: .sendViaAirDrop) {
            service.perform(withItems: [item.fileURL])
        } else {
            openUniversalSharePicker(for: item, relativeTo: nil)
        }
    }

    func shareViaWhatsApp(for item: ScreenshotItem) {
        isSelfWritingPasteboard = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.fileURL as NSURL])
        lastPasteboardChangeCount = pb.changeCount
        isSelfWritingPasteboard = false

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let deeplink = URL(string: "whatsapp://") {
            NSWorkspace.shared.open(deeplink)
        } else {
            openUniversalSharePicker(for: item, relativeTo: nil)
        }
    }

    func openUniversalSharePicker(
        for item: ScreenshotItem,
        relativeTo view: NSView? = nil,
        notchBottomY: CGFloat = 0,
        onServiceChosen: (() -> Void)? = nil
    ) {
        let picker = NSSharingServicePicker(items: [item.fileURL])
        let delegate = SharePickerDelegate(onServiceChosen: onServiceChosen)
        self.activeSharePickerDelegate = delegate
        picker.delegate = delegate

        if let v = view, let contentView = v.window?.contentView {
            // Convert button rect into window contentView coordinate space
            let buttonRectInContentView = contentView.convert(v.bounds, from: v)
            
            // X: Horizontally aligned with the button (arrow centered on button's midX)
            // Y: Vertically right where the Dynamic Notch expanded pill border ends
            let borderY: CGFloat = notchBottomY > 0 ? notchBottomY : (buttonRectInContentView.maxY + 32.0)
            let anchorY: CGFloat = contentView.isFlipped ? (borderY - 1.0) : (contentView.bounds.height - borderY)
            let anchorRect = CGRect(
                x: buttonRectInContentView.origin.x,
                y: anchorY,
                width: buttonRectInContentView.width,
                height: 1.0
            )
            let edge: NSRectEdge = contentView.isFlipped ? .maxY : .minY
            picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: edge)
        } else if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let contentView = window.contentView {
            let buttonX = contentView.bounds.midX + 27
            let borderY: CGFloat = notchBottomY > 0 ? notchBottomY : 272.0
            let anchorY: CGFloat = contentView.isFlipped ? (borderY - 1.0) : (contentView.bounds.height - borderY)
            let buttonRect = CGRect(x: buttonX, y: anchorY, width: 38.0, height: 1.0)
            let edge: NSRectEdge = contentView.isFlipped ? .maxY : .minY
            picker.show(relativeTo: buttonRect, of: contentView, preferredEdge: edge)
        }
    }

    func openInPreview(for item: ScreenshotItem) {
        NSWorkspace.shared.open(item.fileURL)
    }

    func copyToClipboard(for item: ScreenshotItem) {
        isSelfWritingPasteboard = true
        let pb = NSPasteboard.general
        pb.clearContents()

        var objectsToCopy: [NSPasteboardWriting] = []
        if let image = NSImage(contentsOf: item.fileURL) {
            objectsToCopy.append(image)
        }
        objectsToCopy.append(item.fileURL as NSURL)

        pb.writeObjects(objectsToCopy)
        lastPasteboardChangeCount = pb.changeCount
        isSelfWritingPasteboard = false
    }

    // MARK: - Simulation

    func simulateScreenshot() {
        print("[ScreenshotObserver] 🎭 Simülasyon başlatılıyor...")

        // Look for existing real screenshots in primary directory and monitored folders
        var candidateFolders = [Self.primaryScreenshotDirectory()]
        candidateFolders.append(contentsOf: monitoredFolders)

        for folder in candidateFolders {
            if let files = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                let imageFiles = files
                    .filter { validExtensions.contains($0.pathExtension.lowercased()) }
                    .sorted {
                        let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        return d1 > d2
                    }

                if let latest = imageFiles.first, let image = NSImage(contentsOf: latest) {
                    let thumb = createThumbnail(from: image, maxDimension: 512)
                    let item = ScreenshotItem(fileURL: latest, thumbnail: thumb, createdAt: Date())
                    print("[ScreenshotObserver] 🎭 Gerçek dosya ile simüle ediliyor: \(latest.lastPathComponent)")
                    DispatchQueue.main.async { [weak self] in self?.screenshotEvent = item }
                    return
                }
            }
        }

        // Synthetic image fallback
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicNotch_MockSS_\(Int(Date().timeIntervalSince1970)).png")
        let mockImage = NSImage(size: NSSize(width: 320, height: 200))
        mockImage.lockFocus()
        NSGradient(
            starting: NSColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
            ending: NSColor(red: 0.6, green: 0.1, blue: 0.9, alpha: 1)
        )?.draw(in: NSRect(x: 0, y: 0, width: 320, height: 200), angle: 45)
        ("DynamicNotch 📸" as NSString).draw(
            at: NSPoint(x: 60, y: 85),
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 20),
                .foregroundColor: NSColor.white
            ]
        )
        mockImage.unlockFocus()

        if let tiff = mockImage.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            try? png.write(to: tempURL)
        }

        print("[ScreenshotObserver] 🎭 Sentetik görsel ile simüle ediliyor.")
        let item = ScreenshotItem(fileURL: tempURL, thumbnail: mockImage, createdAt: Date())
        DispatchQueue.main.async { [weak self] in self?.screenshotEvent = item }
    }

    // MARK: - Privacy Settings Helper

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Share Picker Delegate

private final class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    private let onServiceChosen: (() -> Void)?

    init(onServiceChosen: (() -> Void)?) {
        self.onServiceChosen = onServiceChosen
        super.init()
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service != nil {
            DispatchQueue.main.async { [weak self] in
                self?.onServiceChosen?()
            }
        }
    }
}

