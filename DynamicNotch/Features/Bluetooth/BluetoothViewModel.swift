// BluetoothViewModel.swift
// DynamicNotch / Features / Bluetooth

import Foundation
import Combine

@MainActor
final class BluetoothViewModel: ObservableObject {
    @Published private(set) var lastDeviceName: String = ""
    @Published private(set) var isConnected: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(observer: BluetoothObserver) {
        observer.$event
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] event in
                switch event {
                case .connected(let name):
                    self?.lastDeviceName = name
                    self?.isConnected = true
                case .disconnected(let name):
                    self?.lastDeviceName = name
                    self?.isConnected = false
                }
            }
            .store(in: &cancellables)
    }
}
