// BluetoothObserver.swift
// DynamicNotch / Observers
//
// Observes classic Bluetooth device connections and disconnections via IOBluetooth.
//
// Why IOBluetooth and not CoreBluetooth?
// ────────────────────────────────────────
// CoreBluetooth is designed for apps that *initiate* BLE connections.  It does
// NOT surface connections made by the system for HID devices (keyboards, mice,
// AirPods, headsets).  IOBluetooth receives those events and does not require
// the app to manage any central/peripheral role.

import Foundation
import IOBluetooth
import IOKit

// MARK: - Bluetooth Event

enum BluetoothEvent {
    case connected(String)      // device name
    case disconnected(String)
}

// MARK: - Observer

final class BluetoothObserver: NSObject, ObservableObject {

    @Published private(set) var event: BluetoothEvent? = nil

    /// Latest known battery percentage (0…100) keyed by Bluetooth device name.
    @Published private(set) var deviceBatteryPercentages: [String: Int] = [:]

    /// Detailed per-ear + case battery data for AirPods, keyed by device name.
    @Published private(set) var deviceDetailedBatteries: [String: AirPodsBattery] = [:]

    // Strong reference required — IOBluetoothUserNotification retains nothing
    // for us; we must keep the registration alive.
    private var connectRegistration: IOBluetoothUserNotification?

    override init() {
        super.init()
        connectRegistration = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:))
        )
    }

    deinit {
        connectRegistration?.unregister()
    }

    private var inFlightQueries: Set<String> = []

    // MARK: - Public Query & Simulation Support

    func batteryPercentage(for deviceName: String) -> Int? {
        if let cached = deviceBatteryPercentages[deviceName] {
            return cached
        }
        requestBackgroundBatteryLookup(for: deviceName)
        return nil
    }

    /// Returns the detailed AirPods battery (left, right, case) for the given device name.
    func airPodsBattery(for deviceName: String) -> AirPodsBattery {
        deviceDetailedBatteries[deviceName] ?? AirPodsBattery.unknown
    }

    private func requestBackgroundBatteryLookup(for deviceName: String) {
        guard !inFlightQueries.contains(deviceName) else { return }
        inFlightQueries.insert(deviceName)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let live = self.resolveBatteryPercentage(for: nil, name: deviceName)

            DispatchQueue.main.async {
                self.inFlightQueries.remove(deviceName)
                if let live {
                    self.deviceBatteryPercentages[deviceName] = live
                }
            }
        }
    }

    func setSimulatedBatteryPercentage(_ percentage: Int?, for deviceName: String) {
        if let percentage {
            deviceBatteryPercentages[deviceName] = min(max(percentage, 0), 100)
        } else {
            deviceBatteryPercentages.removeValue(forKey: deviceName)
        }
    }

    /// Injects simulated detailed AirPods battery data (used by the test menu).
    func setSimulatedDetailedBattery(_ battery: AirPodsBattery, for deviceName: String) {
        deviceDetailedBatteries[deviceName] = battery
    }

    /// Triggers a simulated connection event that notifies all listeners (Notch + AirPods card).
    func debugTriggerConnected(name: String, battery: Int? = nil, detailedBattery: AirPodsBattery? = nil) {
        if let battery {
            deviceBatteryPercentages[name] = min(max(battery, 0), 100)
        }
        if let detailedBattery {
            deviceDetailedBatteries[name] = detailedBattery
        }
        self.event = .connected(name)
    }

    // MARK: - Callbacks

    @objc private func deviceDidConnect(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        let name = device.name ?? "Bilinmeyen Cihaz"
        let address = device.addressString

        // Filter out background Apple Continuity/Handoff sync devices (iPhone, iPad, Apple Watch)
        guard isUserFacingPeripheral(device, name: name) else {
            return
        }

        // Register for the complementary disconnect event on this *specific* device.
        device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDidDisconnect(_:device:))
        )

        // 1. Instant in-memory check (AirPods / Beats selectors on device)
        let immediateBattery  = fastDirectBatteryPercentage(for: device)
        let immediateDetailed = fastDetailedBattery(for: device)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let immediateBattery {
                self.deviceBatteryPercentages[name] = immediateBattery
            }
            if immediateDetailed.hasAnyData {
                self.deviceDetailedBatteries[name] = immediateDetailed
            }
            self.event = .connected(name)
        }

        // 2. Perform deep resolution (IOKit + Plist) on a background thread so UI never hitches
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak device] in
            guard let self else { return }
            let deepBattery   = self.resolveBatteryPercentage(for: device, name: name, address: address)
            let deepDetailed  = self.resolveDetailedBattery(for: device, name: name, address: address)
            DispatchQueue.main.async {
                if let deepBattery {
                    self.deviceBatteryPercentages[name] = deepBattery
                }
                if deepDetailed.hasAnyData {
                    self.deviceDetailedBatteries[name] = deepDetailed
                }
            }
        }

        // 3. AirPods AAP battery telemetry often arrives ~350–500ms after the initial ACL connection.
        // Perform follow-up check on background queue so main thread is completely free.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.50) { [weak self, weak device] in
            guard let self else { return }
            let delayedBattery  = self.resolveBatteryPercentage(for: device, name: name, address: address)
            let delayedDetailed = self.resolveDetailedBattery(for: device, name: name, address: address)
            DispatchQueue.main.async {
                if let delayedBattery {
                    self.deviceBatteryPercentages[name] = delayedBattery
                }
                if delayedDetailed.hasAnyData {
                    self.deviceDetailedBatteries[name] = delayedDetailed
                }
            }
        }
    }

    @objc private func deviceDidDisconnect(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        let name = device.name ?? "Bilinmeyen Cihaz"

        // Ignore background devices that were filtered on connect
        guard isUserFacingPeripheral(device, name: name) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deviceBatteryPercentages.removeValue(forKey: name)
            self.deviceDetailedBatteries.removeValue(forKey: name)
            self.inFlightQueries.remove(name)
            self.event = .disconnected(name)
        }
    }

    // MARK: - Peripheral Device Filtering

    /// Determines whether a Bluetooth connection event represents a physical user accessory
    /// (AirPods, headphones, speakers, mice, keyboards, gamepads) rather than an Apple Continuity
    /// background sync ping from an iPhone, iPad, or Apple Watch.
    private func isUserFacingPeripheral(_ device: IOBluetoothDevice, name: String) -> Bool {
        let lower = name.lowercased()

        // 1. Explicitly ignore background Apple ecosystem devices
        let ignoredKeywords = ["iphone", "ipad", "apple watch", "watch"]
        if ignoredKeywords.contains(where: { lower.contains($0) }) {
            return false
        }

        // 2. Check Bluetooth Major Device Class
        // 0x02 = Phone (Cellular, Smartphone)
        // 0x01 = Computer (Mac, PC)
        let majorClass = (device.classOfDevice >> 8) & 0x1F
        if majorClass == 0x02 || majorClass == 0x01 {
            return false
        }

        // 3. Audio & Peripherals are always welcome (AirPods, Beats, Bose, Sony, Mouse, Keyboard, etc.)
        return isAudioDevice(device, name: name) || isPeripheralDevice(device, name: name)
    }

    private func isAudioDevice(_ device: IOBluetoothDevice, name: String) -> Bool {
        let lower = name.lowercased()
        let audioKeywords = [
            "airpods", "beats", "bose", "sony", "galaxy", "samsung",
            "buds", "earbuds", "headphones", "headset", "speaker",
            "soundbar", "audio", "pixel", "jbl", "anker", "soundcore",
            "earphone", "earphones", "huawei", "redmi", "xiaomi",
            "sennheiser", "shure", "jabra", "marshall", "b&o", "kulaklık", "hoparlör"
        ]
        if audioKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        let audioServiceUUID = IOBluetoothSDPUUID(uuid16: 0x110B) // A2DP Audio Sink
        let headsetServiceUUID = IOBluetoothSDPUUID(uuid16: 0x1108) // Headset
        let handsfreeServiceUUID = IOBluetoothSDPUUID(uuid16: 0x111E) // Handsfree

        if device.getServiceRecord(for: audioServiceUUID) != nil ||
           device.getServiceRecord(for: headsetServiceUUID) != nil ||
           device.getServiceRecord(for: handsfreeServiceUUID) != nil {
            return true
        }

        let majorClass = (device.classOfDevice >> 8) & 0x1F
        return majorClass == 0x04 // Audio/Video Major Class
    }

    private func isPeripheralDevice(_ device: IOBluetoothDevice, name: String) -> Bool {
        let lower = name.lowercased()
        let peripheralKeywords = [
            "mouse", "keyboard", "trackpad", "controller", "gamepad",
            "dualsense", "xbox", "klavye", "fare"
        ]
        if peripheralKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        let hidServiceUUID = IOBluetoothSDPUUID(uuid16: 0x1124) // Human Interface Device
        if device.getServiceRecord(for: hidServiceUUID) != nil {
            return true
        }

        let majorClass = (device.classOfDevice >> 8) & 0x1F
        return majorClass == 0x05 // Peripheral Major Class
    }


    // MARK: - Multi-Source Battery Percentage Extraction

    private func fastDirectBatteryPercentage(for device: IOBluetoothDevice) -> Int? {
        let singleSelectors = ["batteryPercentSingle", "batteryPercentCombined"]
        for selName in singleSelectors {
            let sel = NSSelectorFromString(selName)
            if device.responds(to: sel),
               let val = device.value(forKey: selName) as? Int,
               (1...100).contains(val) {
                return val
            }
        }

        let leftSel  = NSSelectorFromString("batteryPercentLeft")
        let rightSel = NSSelectorFromString("batteryPercentRight")
        var earValues: [Int] = []
        if device.responds(to: leftSel),
           let l = device.value(forKey: "batteryPercentLeft") as? Int,
           (1...100).contains(l) {
            earValues.append(l)
        }
        if device.responds(to: rightSel),
           let r = device.value(forKey: "batteryPercentRight") as? Int,
           (1...100).contains(r) {
            earValues.append(r)
        }
        if !earValues.isEmpty {
            return earValues.min()
        }

        return nil
    }

    /// Extracts per-ear + case battery directly from IOBluetooth selectors.
    /// This is fast (no IOKit iteration) and suitable for the connect-time fast path.
    private func fastDetailedBattery(for device: IOBluetoothDevice) -> AirPodsBattery {
        func intVal(_ key: String) -> Int? {
            let sel = NSSelectorFromString(key)
            guard device.responds(to: sel),
                  let v = device.value(forKey: key) as? Int,
                  (1...100).contains(v) else { return nil }
            return v
        }

        let left      = intVal("batteryPercentLeft")
        let right     = intVal("batteryPercentRight")
        let caseLevel = intVal("batteryPercentCase") ?? intVal("chargingCaseBattery")

        return AirPodsBattery(left: left, right: right, caseLevel: caseLevel)
    }

    /// Multi-source resolution that tries IOKit + plist after selector fallback.
    func resolveDetailedBattery(
        for device: IOBluetoothDevice?,
        name: String,
        address: String? = nil
    ) -> AirPodsBattery {
        // Try fast path first
        if let device {
            let fast = fastDetailedBattery(for: device)
            if fast.hasAnyData { return fast }
        }

        // Fall back to the combined percentage as a proxy (shows in both L and R)
        if let combined = resolveBatteryPercentage(for: device, name: name, address: address) {
            return AirPodsBattery(left: combined, right: combined, caseLevel: nil)
        }

        return .unknown
    }

    /// Resolves the battery percentage (1…100) for a connected `IOBluetoothDevice` by checking:
    /// 1. `IOBluetoothDevice` Objective-C battery selectors (`batteryPercentSingle`, `batteryPercentCombined`, L/R)
    /// 2. IOKit `IORegistry` (`AppleDeviceManagementHIDEventService` & Bluetooth HID services)
    /// 3. `/Library/Preferences/com.apple.Bluetooth.plist` (`DeviceCache`)
    func resolveBatteryPercentage(for device: IOBluetoothDevice?, name: String, address: String? = nil) -> Int? {
        if let device, let direct = fastDirectBatteryPercentage(for: device) {
            return direct
        }

        let devAddress = address ?? device?.addressString

        // 2. IOKit IORegistry lookup
        if let ioKitVal = fetchBatteryPercentageFromIOKit(matchingName: name, address: devAddress) {
            return ioKitVal
        }

        // 3. System Bluetooth Preferences Cache (/Library/Preferences/com.apple.Bluetooth.plist)
        if let plistVal = fetchBatteryPercentageFromBluetoothPlist(address: devAddress, name: name) {
            return plistVal
        }

        return nil
    }

    private func fetchBatteryPercentageFromIOKit(matchingName: String, address: String?) -> Int? {
        let targetNameLower = matchingName.lowercased()
        let normalizedTargetAddr = address?
            .lowercased()
            .replacingOccurrences(of: "-", with: ":")

        let serviceNames = ["AppleDeviceManagementHIDEventService", "IOHIDEventService", "IOService"]
        for serviceName in serviceNames {
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(serviceName),
                &iterator
            )
            guard result == KERN_SUCCESS else { continue }

            var service = IOIteratorNext(iterator)
            var foundPct: Int? = nil

            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }

                if foundPct != nil { continue }

                var unmanagedProps: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(
                    service,
                    &unmanagedProps,
                    kCFAllocatorDefault,
                    0
                ) == KERN_SUCCESS,
                let dict = unmanagedProps?.takeRetainedValue() as? [String: Any] else {
                    continue
                }

                let product = (dict["Product"] as? String)?.lowercased() ?? ""
                let devAddr = (dict["DeviceAddress"] as? String)?
                    .lowercased()
                    .replacingOccurrences(of: "-", with: ":") ?? ""

                let nameMatches = !targetNameLower.isEmpty && !product.isEmpty &&
                    (product.contains(targetNameLower) || targetNameLower.contains(product))
                let addrMatches = normalizedTargetAddr != nil && !devAddr.isEmpty && devAddr == normalizedTargetAddr

                guard nameMatches || addrMatches else { continue }

                if let pct = extractBatteryInt(from: dict) {
                    foundPct = pct
                }
            }

            IOObjectRelease(iterator)

            if let foundPct {
                return foundPct
            }
        }

        return nil
    }

    private func fetchBatteryPercentageFromBluetoothPlist(address: String?, name: String) -> Int? {
        let plistPath = "/Library/Preferences/com.apple.Bluetooth.plist"
        guard let root = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
              let deviceCache = root["DeviceCache"] as? [String: [String: Any]] else {
            return nil
        }

        if let address {
            let hyphenKey = address.lowercased().replacingOccurrences(of: ":", with: "-")
            for (key, entry) in deviceCache where key.lowercased() == hyphenKey {
                if let pct = extractBatteryInt(from: entry) {
                    return pct
                }
            }
        }

        let targetLower = name.lowercased()
        for (_, entry) in deviceCache {
            let entryName = ((entry["Name"] as? String) ?? (entry["displayName"] as? String) ?? "").lowercased()
            if !entryName.isEmpty && (entryName == targetLower || entryName.contains(targetLower)) {
                if let pct = extractBatteryInt(from: entry) {
                    return pct
                }
            }
        }

        return nil
    }

    private func extractBatteryInt(from dict: [String: Any]) -> Int? {
        for key in ["BatteryPercent", "BatteryPercentSingle", "BatteryPercentCombined"] {
            if let v = dict[key] as? Int, (1...100).contains(v) {
                return v
            }
        }

        var earLevels: [Int] = []
        if let left = dict["BatteryPercentLeft"] as? Int, (1...100).contains(left) {
            earLevels.append(left)
        }
        if let right = dict["BatteryPercentRight"] as? Int, (1...100).contains(right) {
            earLevels.append(right)
        }
        if !earLevels.isEmpty {
            return earLevels.min()
        }

        return nil
    }
}
