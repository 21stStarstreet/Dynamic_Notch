// BatteryViewModel.swift
// DynamicNotch / Features / Battery

import Foundation
import Combine

@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var percentage: Int = 100
    @Published private(set) var isCharging: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(observer: BatteryObserver) {
        observer.$percentage
            .receive(on: DispatchQueue.main)
            .assign(to: &$percentage)

        observer.$isCharging
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCharging)
    }
}
