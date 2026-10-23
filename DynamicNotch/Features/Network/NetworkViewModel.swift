// NetworkViewModel.swift
// DynamicNotch / Features / Network

import Foundation
import Combine

@MainActor
final class NetworkViewModel: ObservableObject {
    @Published private(set) var isConnectedToWifi: Bool = false
    @Published private(set) var wifiSSID: String = ""
    @Published private(set) var isVPNActive: Bool = false

    init(observer: NetworkObserver) {
        observer.$isConnectedToWifi
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnectedToWifi)

        observer.$wifiSSID
            .receive(on: DispatchQueue.main)
            .assign(to: &$wifiSSID)

        observer.$isVPNActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isVPNActive)
    }
}
