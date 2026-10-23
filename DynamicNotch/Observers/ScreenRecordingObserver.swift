// ScreenRecordingObserver.swift
// DynamicNotch / Observers
//
// Detects when macOS native screen recording (Cmd+Shift+5 / QuickTime)
// is ACTIVELY recording video.
//
// Key Detection Strategy
// ──────────────────────
// 1. Toolbar & Countdown Suppression:
//    When the user invokes Cmd+Shift+5 or when a 5s/10s countdown is active,
//    `com.apple.screencaptureui` is active and NO video file has been opened yet.
//    We suppress the indicator until capture officially commences.
// 2. Open Video File Handle Inspection:
//    The moment countdown hits 0 and video frames start being captured,
//    the recording process (`screencaptureui` / `screencapture`) opens a write handle
//    to the target `.mov` / `.mp4` file.
//    We inspect open file handles via `/usr/sbin/lsof -p <pid> -Fn`.
//    If and only if an active `.mov` / `.mp4` file handle is open, recording is in progress.
// 3. Accurate Start Date:
//    The creation date of the newly created movie file gives the exact
//    timestamp when frames began recording, starting the counter at 00:00.
// 4. Instant Workspace Lifecycle Hook:
//    Listens to `screencaptureui` deactivation and termination notifications
//    to trigger state checks with zero delay the millisecond countdown finishes or recording stops.

import Foundation
import CoreGraphics
import AppKit
import Darwin

@_silgen_name("CGSIsScreenWatcherPresent")
private func CGSIsScreenWatcherPresent() -> Bool

final class ScreenRecordingObserver: ObservableObject {

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var recordingStartDate: Date? = nil

    private var isSimulating: Bool = false
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func startMonitoring() {
        // Fast polling timer (every 0.4s) for smooth state synchronization
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkRecordingState()
        }

        // Instant reaction via NSWorkspace notifications
        let center = NSWorkspace.shared.notificationCenter

        // When screencaptureui deactivates (countdown reaches 0 and recording begins!)
        let deactObs = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.screencaptureui" else { return }
            self?.checkRecordingState()
        }
        workspaceObservers.append(deactObs)

        // When screencaptureui terminates (recording is stopped and saved!)
        let termObs = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.screencaptureui" else { return }
            self?.checkRecordingState()
        }
        workspaceObservers.append(termObs)

        checkRecordingState()
    }

    private func checkRecordingState() {
        guard !isSimulating else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (active, startDate) = Self.detectActiveScreenRecording()
            DispatchQueue.main.async {
                guard let self, !self.isSimulating else { return }
                if self.isRecording != active {
                    if active {
                        self.recordingStartDate = startDate ?? Date()
                        self.isRecording = true
                    } else {
                        self.recordingStartDate = nil
                        self.isRecording = false
                    }
                }
            }
        }
    }

    private static func detectActiveScreenRecording() -> (isRecording: Bool, startDate: Date?) {
        let candidates = findCandidateRecordingPIDs()

        // 1. Toolbar & Countdown Suppression:
        // When the screenshot overlay (toolbar or countdown window) is active and frontmost,
        // recording has NOT started yet.
        let isScreenshotUIActive = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui")
            .contains(where: { $0.isActive })
        if isScreenshotUIActive {
            return (false, nil)
        }

        // If no candidate capture processes exist at all, recording cannot be active
        guard !candidates.isEmpty else {
            return (false, nil)
        }

        // 2. Check each candidate process for an actively open `.mov` / `.mp4` video file handle.
        // During toolbar setup or countdown, the file handle is NOT open yet.
        for candidate in candidates {
            let (isOpen, _, fileStartDate) = checkOpenVideoFile(pid: candidate.pid)
            if isOpen {
                return (true, fileStartDate ?? Date())
            }
        }

        // 3. Fallback: CoreGraphics Screen Watcher check
        // If WindowServer marks screen watcher as present, and screencaptureui is running
        // in the background (i.e. not in toolbar or countdown mode), capture is underway.
        if CGSIsScreenWatcherPresent() {
            return (true, Date())
        }

        return (false, nil)
    }

    /// Finds candidate process IDs responsible for screen recording on macOS:
    /// - `com.apple.screencaptureui` (native Cmd+Shift+5 UI and recording daemon)
    /// - `screencapture` / `screencaptureui` (CLI and background processes via sysctl)
    /// - `com.apple.QuickTimePlayerX` (QuickTime Player screen recording)
    private static func findCandidateRecordingPIDs() -> [(name: String, pid: pid_t)] {
        var candidates: [(String, pid_t)] = []

        // 1. Check running applications with bundle identifiers
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier?.lowercased() {
                if bid == "com.apple.screencaptureui" {
                    candidates.append(("screencaptureui", app.processIdentifier))
                } else if bid == "com.apple.quicktimeplayerx" {
                    candidates.append(("QuickTimePlayerX", app.processIdentifier))
                }
            }
        }

        // 2. Check kernel sysctl for CLI tools or daemons
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return candidates
        }

        let stride = MemoryLayout<kinfo_proc>.stride
        let count = size / stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else {
            return candidates
        }

        let actualCount = size / stride
        for i in 0..<actualCount {
            let name = withUnsafePointer(to: &procs[i].kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 17) { cStr in
                    String(cString: cStr)
                }
            }
            let lower = name.lowercased()
            if lower == "screencapture" || lower == "screencaptureui" {
                let pid = procs[i].kp_proc.p_pid
                if !candidates.contains(where: { $0.1 == pid }) {
                    candidates.append((name, pid))
                }
            }
        }

        return candidates
    }

    /// Inspects open file descriptors of a process to verify active movie writing
    private static func checkOpenVideoFile(pid: pid_t) -> (isOpen: Bool, path: String?, startDate: Date?) {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-p", "\(pid)", "-Fn"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return (false, nil, nil)
            }

            for line in output.components(separatedBy: "\n") {
                // Lines in -Fn format start with 'n', e.g. "n/Users/username/Desktop/Screen Recording.mov"
                guard line.hasPrefix("n") else { continue }
                let path = String(line.dropFirst())
                let lower = path.lowercased()
                if lower.contains(".mov") || lower.contains(".mp4") || lower.contains(".m4v") {
                    if let attr = try? FileManager.default.attributesOfItem(atPath: path) {
                        let creation = (attr[.creationDate] as? Date) ?? (attr[.modificationDate] as? Date) ?? Date()
                        return (true, path, creation)
                    }
                    return (true, path, Date())
                }
            }
        } catch {
            return (false, nil, nil)
        }

        return (false, nil, nil)
    }

    /// Gracefully stop the native screen recording if running
    func stopRecording() {
        if isSimulating {
            DispatchQueue.main.async {
                self.isSimulating = false
                self.recordingStartDate = nil
                self.isRecording = false
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let pkillURL = URL(fileURLWithPath: "/usr/bin/pkill")

            // Terminate screencapture CLI process if active
            let task1 = Process()
            task1.executableURL = pkillURL
            task1.arguments = ["-INT", "-x", "screencapture"]
            try? task1.run()

            // Terminate screencaptureui recording daemon (saves and finalizes the recording)
            let task2 = Process()
            task2.executableURL = pkillURL
            task2.arguments = ["-INT", "-x", "screencaptureui"]
            try? task2.run()
        }
    }

    /// Toggle simulated screen recording for debug and UI testing
    func simulateScreenRecordingToggle() {
        if isRecording {
            isSimulating = false
            recordingStartDate = nil
            isRecording = false
        } else {
            isSimulating = true
            recordingStartDate = Date()
            isRecording = true
        }
    }
}
