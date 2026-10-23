// NetworkObserver.swift
// DynamicNotch / Observers
//
// Monitors Wi-Fi and VPN connectivity changes via Network.framework.
//
// Engineering details
// ───────────────────
// • NWPathMonitor immediately invokes pathUpdateHandler once upon start() with
//   the current network state. We treat that first invocation as our baseline
//   seed (`hasSeededInitialState = false`) so the app does not flash a fake
//   "Wi-Fi Bağlandı" alert every time it starts up.
// • Subsequent path updates are diffed against the previous state to emit
//   precise transition events (.wifiConnected, .wifiDisconnected, .vpnConnected).
// • Since macOS Sonoma (14.0+), CWWiFiClient.ssid() returns nil unless Location
//   Services permission is granted. We gracefully fall back to an empty string,
//   and NetworkAlertView hides the subtitle line when SSID is empty.

import Foundation
import Network
import CoreWLAN
import CoreLocation
import Darwin

enum NetworkEvent: Equatable {
    case wifiConnected(String)
    case wifiDisconnected
    case vpnConnected(tunnelName: String, connectedDate: Date)
    case noInternet
    case internetRestored
}

final class NetworkObserver: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var hasInternetConnection: Bool          = true
    @Published private(set) var isConnectedToWifi:     Bool          = false
    @Published private(set) var wifiSSID:              String        = ""
    @Published private(set) var isVPNActive:           Bool          = false
    @Published private(set) var vpnConnectedDate:      Date?         = nil
    @Published private(set) var vpnTunnelName:         String        = ""
    @Published private(set) var event:                 NetworkEvent? = nil

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(
        label: "com.local.dynamicnotch.network",
        qos:   .utility
    )

    private let locationManager = CLLocationManager()
    private var hasSeededInitialState: Bool = false
    private var wasInternetConnected:  Bool = true

    override init() {
        super.init()
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - CoreLocation Authorization Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            let freshSSID = resolveCurrentSSID()
            if !freshSSID.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.wifiSSID = freshSSID
                    if self.isConnectedToWifi {
                        self.event = .wifiConnected(freshSSID)
                    }
                }
            }
        }
    }

    // MARK: - SSID Multi-Source Resolution

    func activeWiFiInterfaceName() -> String {
        if let iface = CWWiFiClient.shared().interface()?.interfaceName, !iface.isEmpty {
            return iface
        }
        return "en0"
    }

    func resolveCurrentSSID() -> String {
        // 1. Primary: CoreWLAN Direct API
        let client = CWWiFiClient.shared()
        if let iface = client.interface(), let s = iface.ssid(), !s.isEmpty, s != "<redacted>" {
            return s
        }
        if let ifaces = client.interfaces() {
            for iface in ifaces {
                if let s = iface.ssid(), !s.isEmpty, s != "<redacted>" {
                    return s
                }
            }
        }

        let ifaceName = activeWiFiInterfaceName()

        // 2. System networksetup query
        if let airportSSID = fetchAirportNetworkSSID(interface: ifaceName), !airportSSID.isEmpty {
            return airportSSID
        }

        // 3. DHCP Domain Name & Preferred Networks Correlation
        if let dhcpSSID = fetchDHCPCorrelatedSSID(interface: ifaceName), !dhcpSSID.isEmpty {
            return dhcpSSID
        }

        return ""
    }

    private func fetchAirportNetworkSSID(interface: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getairportnetwork", interface]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let prefix = "Current Wi-Fi Network: "
                if let range = output.range(of: prefix) {
                    let name = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && !name.lowercased().contains("error") && !name.lowercased().contains("not associated") {
                        return name
                    }
                }
            }
        } catch { }
        return nil
    }

    private func fetchDHCPCorrelatedSSID(interface: String) -> String? {
        // 1. Get domain_name from ipconfig getpacket
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        process.arguments = ["getpacket", interface]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var domainCandidate: String? = nil
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    if line.contains("domain_name") {
                        if let colonIdx = line.range(of: ":") {
                            let rawDomain = line[colonIdx.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                            let clean = rawDomain.replacingOccurrences(of: ".local", with: "")
                                .replacingOccurrences(of: ".lan", with: "")
                                .replacingOccurrences(of: ".home", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty && !clean.contains("{") {
                                domainCandidate = clean
                            }
                        }
                    }
                }
            }
        } catch { }

        // 2. Fetch preferred networks list for this interface
        let prefPipe = Pipe()
        let prefProcess = Process()
        prefProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        prefProcess.arguments = ["-listpreferredwirelessnetworks", interface]
        prefProcess.standardOutput = prefPipe
        prefProcess.standardError = FileHandle.nullDevice
        var preferredNetworks: [String] = []
        do {
            try prefProcess.run()
            prefProcess.waitUntilExit()
            let data = prefPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("Preferred networks") {
                        preferredNetworks.append(trimmed)
                    }
                }
            }
        } catch { }

        // 3. Correlate domainCandidate with preferredNetworks
        if let domain = domainCandidate, !domain.isEmpty {
            let normDomain = domain.lowercased().filter { $0.isLetter || $0.isNumber }
            for net in preferredNetworks {
                let normNet = net.lowercased().filter { $0.isLetter || $0.isNumber }
                if normNet == normDomain || normNet.contains(normDomain) || normDomain.contains(normNet) {
                    return net
                }
            }
            if domain.count >= 2 {
                return domain
            }
        }

        // 4. Fallback to top preferred network on this interface
        if let topPreferred = preferredNetworks.first, !topPreferred.isEmpty {
            return topPreferred
        }

        return nil
    }

    private func scheduleSSIDResolutionRetries() {
        let retryDelays: [TimeInterval] = [0.15, 0.4, 0.8, 1.5]
        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isConnectedToWifi else { return }
                let resolved = self.resolveCurrentSSID()
                if !resolved.isEmpty && (self.wifiSSID.isEmpty || self.wifiSSID != resolved) {
                    self.wifiSSID = resolved
                    self.event = .wifiConnected(resolved)
                }
            }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let internetNow = (path.status == .satisfied)
            let wifiNow = path.usesInterfaceType(.wifi) && internetNow
            let ssid    = wifiNow ? self.resolveCurrentSSID() : ""

            // Multi-source VPN detection: NWPath interface check + kernel getifaddrs interface query
            let pathVPN = (path.usesInterfaceType(.other) && internetNow)
            let (kernelVPN, resolvedName) = self.resolveActiveKernelVPN()
            let vpnNow = pathVPN || kernelVPN

            DispatchQueue.main.async {
                if !self.hasSeededInitialState {
                    self.hasSeededInitialState = true
                    self.hasInternetConnection = internetNow
                    self.wasInternetConnected  = internetNow
                    self.isConnectedToWifi     = wifiNow
                    self.wifiSSID              = ssid
                    self.isVPNActive           = vpnNow
                    if vpnNow {
                        self.vpnConnectedDate = Date()
                        self.vpnTunnelName    = resolvedName
                    }
                    if wifiNow && ssid.isEmpty {
                        self.scheduleSSIDResolutionRetries()
                    }
                    return
                }

                let internetLost     = self.wasInternetConnected && !internetNow
                let internetRestored = !self.wasInternetConnected && internetNow
                let wifiChanged      = (wifiNow != self.isConnectedToWifi)
                let vpnChanged       = (vpnNow != self.isVPNActive)

                self.hasInternetConnection = internetNow
                self.wasInternetConnected  = internetNow
                self.isConnectedToWifi     = wifiNow
                self.wifiSSID              = ssid
                self.isVPNActive           = vpnNow

                if internetLost {
                    self.event = .noInternet
                } else if internetRestored {
                    self.event = .internetRestored
                    if wifiNow {
                        let finalSSID = ssid.isEmpty ? self.resolveCurrentSSID() : ssid
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            self.event = .wifiConnected(finalSSID)
                            if finalSSID.isEmpty {
                                self.scheduleSSIDResolutionRetries()
                            }
                        }
                    }
                } else if vpnChanged {
                    if vpnNow {
                        let connectDate = self.vpnConnectedDate ?? Date()
                        self.vpnConnectedDate = connectDate
                        self.vpnTunnelName    = resolvedName
                        self.event = .vpnConnected(tunnelName: resolvedName, connectedDate: connectDate)
                    } else {
                        self.vpnConnectedDate = nil
                        self.vpnTunnelName    = ""
                    }
                } else if wifiChanged {
                    if wifiNow {
                        let finalSSID = ssid.isEmpty ? self.resolveCurrentSSID() : ssid
                        self.event = .wifiConnected(finalSSID)
                        if finalSSID.isEmpty {
                            self.scheduleSSIDResolutionRetries()
                        }
                    } else {
                        self.event = .wifiDisconnected
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Scans active kernel network interfaces via `getifaddrs` for point-to-point tunnels
    /// (`utun`, `ipsec`, `ppp`) established by WireGuard, Tailscale, Cloudflare WARP, or macOS VPNs.
    private func resolveActiveKernelVPN() -> (isActive: Bool, tunnelName: String) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0 else {
            return (false, "VPN Tüneli")
        }
        defer { freeifaddrs(ifaddr) }

        var current = ifaddr
        while current != nil {
            guard let ifa = current?.pointee else { break }
            let flags = Int32(ifa.ifa_flags)
            let isUpAndRunning = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let name = String(cString: ifa.ifa_name)

            if isUpAndRunning && (name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")) {
                let friendly = humanReadableTunnelName(for: name)
                return (true, friendly)
            }
            current = ifa.ifa_next
        }

        return (false, "VPN Tüneli")
    }

    private func humanReadableTunnelName(for interfaceName: String) -> String {
        if interfaceName.hasPrefix("utun") {
            return "WireGuard / UTUN"
        } else if interfaceName.hasPrefix("ipsec") {
            return "IPSec / IKEv2"
        } else if interfaceName.hasPrefix("ppp") {
            return "L2TP / PPP"
        }
        return "Güvenli VPN"
    }

    // MARK: - Simulation Helper

    func setSimulatedVPN(tunnelName: String, connectedDate: Date) {
        self.isVPNActive      = true
        self.vpnTunnelName    = tunnelName
        self.vpnConnectedDate = connectedDate
        self.event            = .vpnConnected(tunnelName: tunnelName, connectedDate: connectedDate)
    }

    func simulateNoInternet() {
        self.hasInternetConnection = false
        self.event                 = .noInternet
    }
}
