// DownloadViewModel.swift
// DynamicNotch / Features / Downloads

import Foundation
import Combine

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published private(set) var activeDownloads: [DownloadItem] = []

    init(observer: DownloadObserver) {
        observer.$activeDownloads
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeDownloads)
    }
}
