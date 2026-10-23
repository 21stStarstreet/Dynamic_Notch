// ExternalDriveManager.swift
// DynamicNotch / Features / ExternalDrive
//
// Core service managing external drives, SSDs, USB sticks, SD cards, and DMGs.
// Observes macOS volume mount/unmount notifications in real time and provides
// safe, asynchronous device ejection with tactile feedback.

import AppKit
import Combine

extension Notification.Name {
    static let externalDriveDidMount = Notification.Name("ExternalDriveManagerDidMount")
    static let externalDriveDidEject = Notification.Name("ExternalDriveManagerDidEject")
}

@MainActor
final class ExternalDriveManager: ObservableObject {

    static let shared = ExternalDriveManager()

    @Published private(set) var mountedDrives: [ExternalDriveItem] = []
    @Published private(set) var ejectingDriveURLs: Set<URL> = []
    @Published private(set) var lastEjectedDriveName: String? = nil

    private init() {
        setupObservers()
        refreshMountedDrives()
    }

    // MARK: - Drive Scanning & Inspection

    func refreshMountedDrives() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRootFileSystemKey,
            .volumeURLKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        var drives: [ExternalDriveItem] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }

            // 1. Ignore root filesystem and internal core OS volumes
            if values.volumeIsRootFileSystem == true { continue }
            if values.volumeIsInternal == true && values.volumeIsRemovable != true && values.volumeIsEjectable != true {
                continue
            }

            let path = url.path
            // 2. Only consider volumes mounted under /Volumes/
            guard path.hasPrefix("/Volumes/") else { continue }

            // 3. Exclude internal boot volume aliases and Time Machine snapshots
            let lastComponent = url.lastPathComponent.lowercased()
            if path == "/Volumes/Macintosh HD" || lastComponent == "macintosh hd" || lastComponent.contains("time machine") {
                continue
            }

            let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }

            let avail = Int64(values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0))
            let used = max(0, total - avail)
            let percentage = max(0.0, min(1.0, Double(used) / Double(total)))

            let isEjectable = values.volumeIsEjectable ?? true
            let isRemovable = values.volumeIsRemovable ?? true

            // Classify drive type using volume characteristics
            let driveType: ExternalDriveType
            let lowerName = name.lowercased()
            if lowerName.contains("sd card") || lowerName.contains("sdhc") || lowerName.contains("sdxc") || lowerName.contains("eos_digital") {
                driveType = .sdCard
            } else if path.lowercased().hasSuffix(".dmg") || lowerName.hasSuffix(".dmg") || (values.volumeIsRemovable == false && values.volumeIsEjectable == true) {
                driveType = .diskImage
            } else if total >= 240 * 1024 * 1024 * 1024 {
                // Large flash/NVMe storage (>= 240 GB)
                driveType = .ssd
            } else {
                driveType = .usb
            }

            let item = ExternalDriveItem(
                id: url.absoluteString,
                name: name,
                url: url,
                mountPath: path,
                totalCapacityBytes: total,
                availableCapacityBytes: avail,
                usedCapacityBytes: used,
                usedPercentage: percentage,
                driveType: driveType,
                isEjectable: isEjectable,
                isRemovable: isRemovable
            )
            drives.append(item)
        }

        self.mountedDrives = drives
    }

    // MARK: - Observers

    private func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.refreshMountedDrives()
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self?.handleDriveMounted(url: url)
                }
            }
        }

        center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.refreshMountedDrives()
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self?.ejectingDriveURLs.remove(url)
                }
            }
        }

        center.addObserver(
            forName: NSWorkspace.didRenameVolumeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMountedDrives()
            }
        }
    }

    private func handleDriveMounted(url: URL) {
        guard let drive = mountedDrives.first(where: { $0.url == url }) else { return }
        NotificationCenter.default.post(name: .externalDriveDidMount, object: drive)
    }

    // MARK: - Actions

    func eject(drive: ExternalDriveItem, completion: ((Bool) -> Void)? = nil) {
        guard !ejectingDriveURLs.contains(drive.url) else { return }
        ejectingDriveURLs.insert(drive.url)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var success = false
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: drive.url)
                success = true
            } catch {
                print("[ExternalDriveManager] Eject failed: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ejectingDriveURLs.remove(drive.url)
                if success {
                    self.lastEjectedDriveName = drive.name
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    NotificationCenter.default.post(
                        name: .externalDriveDidEject,
                        object: nil,
                        userInfo: ["driveName": drive.name, "success": true]
                    )
                    completion?(true)
                } else {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    NotificationCenter.default.post(
                        name: .externalDriveDidEject,
                        object: nil,
                        userInfo: ["driveName": drive.name, "success": false]
                    )
                    completion?(false)
                }
                self.refreshMountedDrives()
            }
        }
    }

    func ejectAll(completion: ((Bool) -> Void)? = nil) {
        let drives = mountedDrives.filter { $0.isEjectable }
        guard !drives.isEmpty else {
            completion?(true)
            return
        }

        let group = DispatchGroup()
        var allSucceeded = true

        for drive in drives {
            group.enter()
            eject(drive: drive) { success in
                if !success { allSucceeded = false }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion?(allSucceeded)
        }
    }

    func openInFinder(drive: ExternalDriveItem) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: drive.mountPath)
    }
}
