// HotspotManager.swift
// DynamicNotch / Features / Hotspot
//
// Apple-grade coordinator monitoring Personal Hotspot connectivity (iPhone / iPad)
// via CoreWLAN, Continuity Bluetooth LE signals, and IOKit.
// Manages real-time battery tracking, low-battery warning alerts, and Live Activities.

import Foundation
import CoreWLAN
import IOBluetooth
import Network
import Combine
import SwiftUI

@MainActor
final class HotspotManager: ObservableObject {

    static let shared = HotspotManager()

    // MARK: - Published State

    @Published private(set) var currentHotspot: HotspotItem? = nil
    @Published private(set) var isConnectedToHotspot: Bool = false
    @Published private(set) var currentWifiSSID: String? = nil

    /// Callback invoked when tethered device battery drops into low (≤20%) or critical (≤10%) thresholds
    var onLowBatteryAlertTriggered: ((HotspotItem) -> Void)?

    // MARK: - Private State

    private var pollTimer: AnyCancellable?
    private var alertedThresholds: Set<Int> = []
    private var simulatedHotspot: HotspotItem? = nil

    // MARK: - Preferences

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "showHotspotBattery") as? Bool ?? true
    }

    // MARK: - Initialization

    private init() {
        UserDefaults.standard.removeObject(forKey: "hotspotCustomBatteryLevel")
        startMonitoring()
    }

    // MARK: - Network & Hotspot Monitoring

    func startMonitoring() {
        pollTimer?.cancel()
        // Check Wi-Fi and Tethering state every 2.0 seconds for responsive live telemetry
        pollTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshHotspotState()
            }

        refreshHotspotState()
    }

    func refreshHotspotState() {
        guard isEnabled else {
            if isConnectedToHotspot {
                currentHotspot = nil
                isConnectedToHotspot = false
            }
            return
        }

        guard let iface = CWWiFiClient.shared().interface() else {
            self.currentWifiSSID = nil
            if let sim = simulatedHotspot {
                self.currentHotspot = sim
                self.isConnectedToHotspot = true
            } else if isConnectedToHotspot {
                currentHotspot = nil
                isConnectedToHotspot = false
                alertedThresholds.removeAll()
            }
            return
        }

        // 1. FIRST PRIORITY: Live Apple CoreWLAN Tether Device (Instant Hotspot)
        if let tether = getTetherDeviceInfo(from: iface) {
            self.simulatedHotspot = nil // Real live hardware detected! Clear simulation immediately!
            let name = tether.deviceName ?? "iPhone"
            applyHotspotTelemetry(
                deviceName: name,
                battery: tether.batteryLife,
                signalBars: tether.signalBars,
                cellularType: tether.cellularType
            )
            return
        }

        // 2. SECOND PRIORITY: Check currently joined network (SSID / lastNetworkJoined)
        var networkSSID = iface.ssid()
        var isNetworkHotspot = false

        if networkSSID == nil || networkSSID?.isEmpty == true || networkSSID == "<redacted>" {
            let selLast = Selector(("lastNetworkJoined"))
            if iface.responds(to: selLast),
               let net = iface.perform(selLast)?.takeUnretainedValue() as? CWNetwork {
                networkSSID = net.ssid
                isNetworkHotspot = (net as AnyObject).value(forKey: "isPersonalHotspot") as? Bool ?? false
            }
        }

        self.currentWifiSSID = networkSSID

        if let currentSSID = networkSSID, !currentSSID.isEmpty, currentSSID != "<redacted>" {
            let isHotspot = isNetworkHotspot || checkIsPersonalHotspot(interface: iface, ssid: currentSSID)
            if isHotspot {
                self.simulatedHotspot = nil // Real live hotspot detected!
                let deviceName = sanitizeDeviceName(from: currentSSID)
                let battery = resolveDeviceBattery(for: deviceName, interface: iface)
                let signal = estimateSignalBars(from: iface.rssiValue())

                applyHotspotTelemetry(
                    deviceName: deviceName,
                    battery: battery,
                    signalBars: signal,
                    cellularType: nil
                )
                return
            }
        }

        // 3. THIRD PRIORITY: If user explicitly triggered a debug simulation bench, preserve it
        if let sim = simulatedHotspot {
            self.currentHotspot = sim
            self.isConnectedToHotspot = true
            return
        }

        // 4. No active hotspot connection
        if isConnectedToHotspot {
            self.currentHotspot = nil
            self.isConnectedToHotspot = false
            self.alertedThresholds.removeAll()
        }
    }

    private func applyHotspotTelemetry(
        deviceName: String,
        battery: Int?,
        signalBars: Int?,
        cellularType: String?
    ) {
        if let existing = currentHotspot, existing.deviceName == deviceName, existing.isConnected {
            var updated = existing
            updated.batteryLevel = battery
            updated.signalBars = signalBars
            updated.cellularType = cellularType
            self.currentHotspot = updated
            self.isConnectedToHotspot = true
            checkBatteryThresholds(for: updated)
        } else {
            let newHotspot = HotspotItem(
                id: UUID().uuidString,
                deviceName: deviceName,
                batteryLevel: battery,
                isCharging: false,
                cellularType: cellularType,
                signalBars: signalBars,
                connectedDate: Date(),
                isConnected: true
            )
            self.currentHotspot = newHotspot
            self.isConnectedToHotspot = true
            self.alertedThresholds.removeAll()
            checkBatteryThresholds(for: newHotspot)
        }
    }

    // MARK: - Tether Device Extraction via CoreWLAN SPI

    private struct TetherDeviceInfo {
        var deviceName: String?
        var batteryLife: Int?
        var signalBars: Int?
        var cellularType: String?
    }

    private func getTetherDeviceInfo(from interface: CWInterface) -> TetherDeviceInfo? {
        var tetherObj: NSObject? = nil
        let candidateSelectors = [
            "lastTetherDeviceJoined",
            "tetherDevice",
            "currentTetherDevice"
        ]
        for selName in candidateSelectors {
            let sel = Selector((selName))
            if interface.responds(to: sel),
               let obj = interface.perform(sel)?.takeUnretainedValue() as? NSObject {
                tetherObj = obj
                break
            }
        }
        guard let obj = tetherObj else { return nil }

        let name = (obj.value(forKey: "deviceName") as? String) ?? "iPhone"
        var battery: Int? = nil
        for key in ["batteryLife", "batteryPercent", "batteryPercentage", "batteryLevel", "battery"] {
            if battery != nil { break }
            if let bNum = obj.value(forKey: key) as? NSNumber {
                let dVal = bNum.doubleValue
                if dVal > 1.0 && dVal <= 100.0 {
                    battery = Int(dVal)
                } else if dVal > 0.0 && dVal <= 1.0 {
                    battery = Int(dVal * 100.0)
                } else if dVal == 0.0 {
                    battery = 0
                }
            }
        }

        var signal: Int? = nil
        if let sNum = obj.value(forKey: "signalStrength") as? NSNumber {
            signal = max(1, min(4, sNum.intValue))
        }

        var cellular: String? = nil
        if let typeNum = obj.value(forKey: "networkType") as? NSNumber {
            switch typeNum.intValue {
            case 2: cellular = "5G"
            case 1: cellular = "LTE"
            default: cellular = "5G"
            }
        }

        return TetherDeviceInfo(deviceName: name, batteryLife: battery, signalBars: signal, cellularType: cellular)
    }

    // MARK: - Hotspot Detection Logic

    private func checkIsPersonalHotspot(interface: CWInterface, ssid: String) -> Bool {
        // 1. Direct Apple Vendor Information Element inspection (OUI: 00:17:F2)
        if let cached = interface.cachedScanResults() {
            for network in cached where network.ssid == ssid {
                if let isPH = (network as AnyObject).value(forKey: "isPersonalHotspot") as? Bool, isPH {
                    return true
                }
                if let ieData = network.informationElementData {
                    let appleOUI = Data([0x00, 0x17, 0xF2])
                    if ieData.range(of: appleOUI) != nil {
                        return true
                    }
                }
            }
        }

        // 2. Apple Device Naming Heuristics (e.g. "Mustafa’s iPhone", "iPad", "iPhone (2)")
        let lower = ssid.lowercased()
        if lower.contains("iphone") || lower.contains("ipad") {
            return true
        }

        return false
    }

    private func sanitizeDeviceName(from ssid: String) -> String {
        return ssid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveDeviceBattery(for deviceName: String, interface: CWInterface) -> Int? {
        // 1. Direct CoreWLAN CWTetherDevice via lastTetherDeviceJoined
        if let tether = getTetherDeviceInfo(from: interface), let b = tether.batteryLife {
            return b
        }

        // 2. IOBluetooth paired devices check
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            let targetLower = deviceName.lowercased()
            for dev in paired {
                if let devName = dev.name?.lowercased(),
                   (devName == targetLower || devName.contains(targetLower) || targetLower.contains(devName)) {
                    let sel = Selector(("batteryPercentSingle"))
                    if dev.responds(to: sel),
                       let val = dev.value(forKey: "batteryPercentSingle") as? Int,
                       (1...100).contains(val) {
                        return val
                    }
                }
            }
        }

        // If telemetry is not actively broadcast or unavailable, return nil (visualized honestly as %--)
        return nil
    }

    private func estimateSignalBars(from rssi: Int) -> Int {
        if rssi >= -60 { return 4 }
        if rssi >= -70 { return 3 }
        if rssi >= -80 { return 2 }
        return 1
    }

    private func checkBatteryThresholds(for hotspot: HotspotItem) {
        if hotspot.isCriticalBattery && !alertedThresholds.contains(10) {
            alertedThresholds.insert(10)
            onLowBatteryAlertTriggered?(hotspot)
        } else if hotspot.isLowBattery && !alertedThresholds.contains(20) {
            alertedThresholds.insert(20)
            onLowBatteryAlertTriggered?(hotspot)
        }
    }

    // MARK: - Simulation Bench (Debug / Test only)

    func setCustomBatteryLevel(_ level: Int?) {
        if let level, (1...100).contains(level) {
            UserDefaults.standard.set(level, forKey: "hotspotCustomBatteryLevel")
        } else {
            UserDefaults.standard.removeObject(forKey: "hotspotCustomBatteryLevel")
        }
        if var current = currentHotspot {
            current.batteryLevel = level
            self.currentHotspot = current
        }
    }

    func simulateHotspot(
        deviceName: String = "iPhone",
        batteryLevel: Int? = nil,
        cellularType: String? = nil,
        signalBars: Int? = nil,
        connectedDate: Date? = nil
    ) -> HotspotItem {
        let item = HotspotItem(
            deviceName: deviceName,
            batteryLevel: batteryLevel,
            isCharging: false,
            cellularType: cellularType,
            signalBars: signalBars,
            connectedDate: connectedDate,
            isConnected: true
        )
        self.simulatedHotspot = item
        self.currentHotspot = item
        self.isConnectedToHotspot = true
        return item
    }

    func simulateHotspotUnknownBattery() -> HotspotItem {
        return simulateHotspot(
            deviceName: "iPhone",
            batteryLevel: nil,
            cellularType: nil,
            signalBars: nil,
            connectedDate: nil
        )
    }

    func simulateLowBattery(batteryLevel: Int = 15) -> HotspotItem {
        let item = HotspotItem(
            deviceName: "iPhone",
            batteryLevel: batteryLevel,
            isCharging: false,
            cellularType: nil,
            signalBars: nil,
            connectedDate: Date(),
            isConnected: true
        )
        self.simulatedHotspot = item
        self.currentHotspot = item
        self.isConnectedToHotspot = true
        return item
    }

    func clearSimulation() {
        self.simulatedHotspot = nil
        self.currentHotspot = nil
        self.isConnectedToHotspot = false
        self.alertedThresholds.removeAll()
        refreshHotspotState()
    }
}
