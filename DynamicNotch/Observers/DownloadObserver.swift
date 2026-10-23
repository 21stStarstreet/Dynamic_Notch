// DownloadObserver.swift
// DynamicNotch / Observers
//
// Monitors ~/Downloads for active in-progress downloads across Safari, Chrome,
// Brave, Edge, Arc, and Firefox.
//
// Engineering details
// ───────────────────
// • Safari creates a package directory `<filename>.download` containing an
//   `Info.plist` with keys `DownloadEntryProgressBytesSoFar` and
//   `DownloadEntryProgressTotalToLoad`. Reading this plist gives exact byte-level
//   progress.
// • Chromium browsers create `<filename>.crdownload` and Firefox creates `<filename>.part`.
//   For these, we track file growth rate and byte size in real time.
// • We combine a kernel-level VNODE `DispatchSourceFileSystemObject` on ~/Downloads
//   with a 0.5s progress polling timer that runs ONLY while at least one active
//   download file is present (zero idle CPU overhead).

import Foundation
import SQLite3

final class DownloadObserver: ObservableObject {

    @Published private(set) var activeDownloads: [DownloadItem] = []

    private let downloadsURL: URL? = FileManager.default.urls(
        for: .downloadsDirectory,
        in: .userDomainMask
    ).first

    private var directoryFileDescriptor: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var metadataQuery: NSMetadataQuery?

    /// Tracks initial observed size for non-Safari downloads to estimate progress
    private var observedPeakBytes: [String: Int64] = [:]

    /// Cached exact total sizes queried from browser databases / plists
    private var knownTotalBytes: [String: Int64] = [:]

    /// Tracks byte deltas and timestamps to calculate smooth download speed (EMA)
    private var speedTracker: [String: SpeedSample] = [:]

    private struct SpeedSample {
        var lastBytes: Int64
        var lastTime: Date
        var currentSpeed: Double // bytes/sec
    }

    // MARK: - Init / Deinit

    init() {
        setupSpotlightQuery()
        setupDirectoryWatcher()
        scanDownloadsDirectory()
    }

    deinit {
        pollTimer?.invalidate()
        metadataQuery?.stop()
        directorySource?.cancel()
    }

    // MARK: - Speed Calculation & Formatting

    private func calculateSpeed(for id: String, currentBytes: Int64) -> Double {
        let now = Date()
        if var sample = speedTracker[id] {
            let elapsed = now.timeIntervalSince(sample.lastTime)
            guard elapsed >= 0.25 else { return sample.currentSpeed }

            let byteDiff = max(0, currentBytes - sample.lastBytes)
            let instantSpeed = Double(byteDiff) / elapsed

            // Exponential moving average (EMA) to smooth out spikes: 30% old + 70% new
            let smoothed = sample.currentSpeed == 0
                ? instantSpeed
                : (sample.currentSpeed * 0.30 + instantSpeed * 0.70)

            sample.currentSpeed = smoothed
            sample.lastBytes = currentBytes
            sample.lastTime = now
            speedTracker[id] = sample
            return smoothed
        } else {
            speedTracker[id] = SpeedSample(
                lastBytes: currentBytes,
                lastTime: now,
                currentSpeed: 0.0
            )
            return 0.0
        }
    }

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "0 KB/s" }
        let mbps = bytesPerSec / 1_048_576.0
        if mbps >= 1.0 {
            return String(format: "%.1f MB/s", mbps)
        } else {
            let kbps = max(1.0, bytesPerSec / 1024.0)
            return String(format: "%.0f KB/s", kbps)
        }
    }

    /// Formats bytes into an ultra-compact string for the right wing (e.g. 45M, 1.2G, 450K)
    static func formatCompactBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0B" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1fG", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1.0 {
            return String(format: "%.0fM", mb)
        }
        let kb = Double(bytes) / 1024.0
        if kb >= 1.0 {
            return String(format: "%.0fK", kb)
        }
        return "\(bytes)B"
    }

    // MARK: - Spotlight Metadata Query

    private func setupSpotlightQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(
            format: "kMDItemFSName LIKE '*.download' OR kMDItemFSName LIKE '*.crdownload' OR kMDItemFSName LIKE '*.part'"
        )
        if let downloadsURL {
            query.searchScopes = [downloadsURL]
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryUpdated),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryUpdated),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
        metadataQuery = query
    }

    @objc private func metadataQueryUpdated() {
        scanDownloadsDirectory()
    }

    // MARK: - Kernel Directory Watcher (FSEvents / kqueue)

    private func setupDirectoryWatcher() {
        guard let url = downloadsURL else { return }

        directoryFileDescriptor = open(url.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.scanDownloadsDirectory()
        }

        source.setCancelHandler { [fd = directoryFileDescriptor] in
            if fd >= 0 {
                close(fd)
            }
        }

        source.resume()
        directorySource = source
    }

    // MARK: - Scanning & Progress Calculation

    private func scanDownloadsDirectory() {
        guard let downloadsURL else { return }

        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var items: [DownloadItem] = []

        for fileURL in urls {
            let ext = fileURL.pathExtension.lowercased()

            if ext == "download" {
                if let safariItem = parseSafariDownloadBundle(at: fileURL) {
                    items.append(safariItem)
                }
            } else if ext == "crdownload" || ext == "part" {
                if let browserItem = parsePartialDownloadFile(at: fileURL) {
                    items.append(browserItem)
                }
            }
        }

        // Clean up stale speed tracking and total byte cache entries
        let activeIDs = Set(items.map { $0.id })
        speedTracker = speedTracker.filter { activeIDs.contains($0.key) }
        knownTotalBytes = knownTotalBytes.filter { activeIDs.contains($0.key) }

        activeDownloads = items
        updatePollingState(hasActiveDownloads: !items.isEmpty)
    }

    // MARK: - Browser Total Size Resolvers

    private func getChromiumHistoryPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let appSupport = "\(home)/Library/Application Support"
        let baseDirs = [
            "\(appSupport)/Google/Chrome",
            "\(appSupport)/Google/Chrome Beta",
            "\(appSupport)/Google/Chrome Canary",
            "\(appSupport)/Arc/User Data",
            "\(appSupport)/BraveSoftware/Brave-Browser",
            "\(appSupport)/Microsoft Edge",
            "\(appSupport)/Chromium",
            "\(appSupport)/Vivaldi",
            "\(appSupport)/com.operasoftware.Opera"
        ]

        var historyPaths: [String] = []
        let fm = FileManager.default
        for base in baseDirs {
            guard fm.fileExists(atPath: base) else { continue }
            let defaultHistory = "\(base)/Default/History"
            if fm.fileExists(atPath: defaultHistory) {
                historyPaths.append(defaultHistory)
            }
            if let subdirs = try? fm.contentsOfDirectory(atPath: base) {
                for sub in subdirs where sub.hasPrefix("Profile ") {
                    let profileHistory = "\(base)/\(sub)/History"
                    if fm.fileExists(atPath: profileHistory) {
                        historyPaths.append(profileHistory)
                    }
                }
            }
            let directHistory = "\(base)/History"
            if fm.fileExists(atPath: directHistory) && !historyPaths.contains(directHistory) {
                historyPaths.append(directHistory)
            }
        }
        return historyPaths
    }

    private func queryChromiumTotalBytes(for cleanName: String, fileURL: URL) -> Int64? {
        if let cached = knownTotalBytes[fileURL.path], cached > 0 {
            return cached
        }

        let paths = getChromiumHistoryPaths()
        let filename = fileURL.lastPathComponent

        for dbPath in paths {
            var db: OpaquePointer?
            if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                sqlite3_busy_timeout(db, 50)
                let query = """
                SELECT total_bytes, target_path, current_path
                FROM downloads
                WHERE (state = 0 OR state = 1) AND total_bytes > 0
                ORDER BY start_time DESC
                LIMIT 15;
                """
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                    while sqlite3_step(statement) == SQLITE_ROW {
                        let total = sqlite3_column_int64(statement, 0)
                        let targetPathStr = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) } ?? ""
                        let currentPathStr = sqlite3_column_text(statement, 2).flatMap { String(cString: $0) } ?? ""

                        let targetURL = URL(fileURLWithPath: targetPathStr)
                        let currentURL = URL(fileURLWithPath: currentPathStr)

                        if targetURL.lastPathComponent == cleanName ||
                            currentURL.lastPathComponent == filename ||
                            targetPathStr.contains(cleanName) ||
                            currentPathStr.contains(cleanName) {
                            sqlite3_finalize(statement)
                            sqlite3_close(db)
                            if total > 0 {
                                knownTotalBytes[fileURL.path] = total
                                return total
                            }
                            return nil
                        }
                    }
                    sqlite3_finalize(statement)
                }
                sqlite3_close(db)
            }
        }
        return nil
    }

    private func querySafariDownloadsPlist(for cleanName: String) -> (downloaded: Int64, total: Int64)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let safariPlistURL = URL(fileURLWithPath: "\(home)/Library/Safari/Downloads.plist")
        guard let data = try? Data(contentsOf: safariPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let entries = (plist["DownloadHistory"] as? [[String: Any]]) ?? (plist["Downloads"] as? [[String: Any]]) ?? []
        for entry in entries {
            let path = (entry["DownloadEntryPath"] as? String) ?? ""
            if path.contains(cleanName) {
                let soFar = (entry["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                let total = (entry["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value ?? 0
                if total > 0 || soFar > 0 {
                    return (downloaded: soFar, total: total)
                }
            }
        }
        return nil
    }

    /// Parses Safari's `.download` bundle Info.plist for exact byte counts.
    private func parseSafariDownloadBundle(at bundleURL: URL) -> DownloadItem? {
        let cleanName = bundleURL.deletingPathExtension().lastPathComponent
        let folderName = bundleURL.deletingLastPathComponent().lastPathComponent.isEmpty
            ? "Downloads"
            : bundleURL.deletingLastPathComponent().lastPathComponent

        let candidateURLs = [
            bundleURL.appendingPathComponent("Info.plist"),
            bundleURL.appendingPathComponent("Contents/Info.plist")
        ]

        var bytesSoFar: Int64 = 0
        var totalBytes: Int64 = knownTotalBytes[bundleURL.path] ?? 0

        for plistURL in candidateURLs {
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {

                if let soFar = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value, soFar > 0 {
                    bytesSoFar = soFar
                }
                if let total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value, total > 0 {
                    totalBytes = total
                }

                if let entry = plist["DownloadEntry"] as? [String: Any] {
                    if let soFar = (entry["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value, soFar > 0 {
                        bytesSoFar = soFar
                    }
                    if let total = (entry["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value, total > 0 {
                        totalBytes = total
                    }
                }

                if bytesSoFar == 0, let soFar = (plist["bytesReceived"] as? NSNumber)?.int64Value, soFar > 0 {
                    bytesSoFar = soFar
                }
                if totalBytes == 0, let total = (plist["totalBytes"] as? NSNumber)?.int64Value, total > 0 {
                    totalBytes = total
                }
                break
            }
        }

        if totalBytes == 0 {
            if let safariInfo = querySafariDownloadsPlist(for: cleanName) {
                if totalBytes == 0 && safariInfo.total > 0 {
                    totalBytes = safariInfo.total
                }
                if bytesSoFar == 0 && safariInfo.downloaded > 0 {
                    bytesSoFar = safariInfo.downloaded
                }
            }
        }

        if bytesSoFar == 0 {
            let fm = FileManager.default
            if let subfiles = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: [.fileSizeKey]) {
                for sub in subfiles where !sub.lastPathComponent.hasSuffix(".plist") {
                    if let size = (try? sub.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                        bytesSoFar += Int64(size)
                    }
                }
            }
        }

        if totalBytes > 0 {
            knownTotalBytes[bundleURL.path] = totalBytes
        }

        let progress: Double
        if totalBytes > 0 {
            progress = min(max(Double(bytesSoFar) / Double(totalBytes), 0.0), 1.0)
        } else {
            progress = 0.0
        }

        let speed = calculateSpeed(for: bundleURL.path, currentBytes: bytesSoFar)

        return DownloadItem(
            id: bundleURL.path,
            filename: cleanName,
            progress: progress,
            totalBytes: totalBytes,
            downloadedBytes: bytesSoFar,
            speedBytesPerSec: speed,
            sourceFolderName: folderName
        )
    }

    /// Parses Chromium `.crdownload` or Firefox `.part` files.
    private func parsePartialDownloadFile(at fileURL: URL) -> DownloadItem? {
        let cleanName = fileURL.deletingPathExtension().lastPathComponent
        let folderName = fileURL.deletingLastPathComponent().lastPathComponent.isEmpty
            ? "Downloads"
            : fileURL.deletingLastPathComponent().lastPathComponent
        let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        let currentBytes = Int64(resourceValues?.fileSize ?? 0)

        // Query real total bytes from browser database (Chromium: Chrome, Arc, Brave, Edge)
        var totalBytes = knownTotalBytes[fileURL.path] ?? 0
        if totalBytes <= 0 {
            if let queried = queryChromiumTotalBytes(for: cleanName, fileURL: fileURL), queried > 0 {
                totalBytes = queried
                knownTotalBytes[fileURL.path] = queried
            }
        }

        let progress: Double
        if totalBytes > 0 {
            progress = min(max(Double(currentBytes) / Double(totalBytes), 0.0), 1.0)
        } else {
            progress = 0.0
        }

        let speed = calculateSpeed(for: fileURL.path, currentBytes: currentBytes)

        return DownloadItem(
            id: fileURL.path,
            filename: cleanName,
            progress: progress,
            totalBytes: totalBytes,
            downloadedBytes: currentBytes,
            speedBytesPerSec: speed,
            sourceFolderName: folderName
        )
    }

    private func updatePollingState(hasActiveDownloads: Bool) {
        if hasActiveDownloads && pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.scanDownloadsDirectory()
            }
        } else if !hasActiveDownloads && pollTimer != nil {
            pollTimer?.invalidate()
            pollTimer = nil
            observedPeakBytes.removeAll()
            speedTracker.removeAll()
            knownTotalBytes.removeAll()
        }
    }
}
