// VolumeHUDViewModel.swift
// DynamicNotch / Features / VolumeHUD

import Foundation
import Combine
import SwiftUI

@MainActor
final class VolumeHUDViewModel: ObservableObject {

    static let shared = VolumeHUDViewModel()

    static let notchVolumeAudioRouteToggleRequested = Notification.Name("notchVolumeAudioRouteToggleRequested")

    @Published private(set) var volume: Float = 0.5
    @Published var isAudioRouteExpanded: Bool = false
    @Published var selectedTab: AudioDeviceDirection = .output

    private var cancellables = Set<AnyCancellable>()

    init(observer: VolumeObserver? = nil) {
        if let observer {
            bind(to: observer)
        }
    }

    func bind(to observer: VolumeObserver) {
        observer.$volume
            .receive(on: DispatchQueue.main)
            .assign(to: &$volume)
    }

    func toggleAudioRoute() {
        NotificationCenter.default.post(
            name: Self.notchVolumeAudioRouteToggleRequested,
            object: nil
        )
    }

    func reset() {
        isAudioRouteExpanded = false
        selectedTab = .output
    }
}
