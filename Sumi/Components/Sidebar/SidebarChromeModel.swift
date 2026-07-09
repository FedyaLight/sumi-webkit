//
//  SidebarChromeModel.swift
//  Sumi
//
//

import Combine
import Foundation

/// Aggregates chrome-adjacent managers so `SpacesSideBarView` can observe one
/// object instead of download / updater / extension / now-playing fan-out.
@MainActor
final class SidebarChromeModel: ObservableObject {
    let downloadManager: DownloadManager
    let extensionSurfaceStore: BrowserExtensionSurfaceStore
    let nowPlayingController: SumiNativeNowPlayingController
    let updaterService: SumiUpdaterService

    private var cancellables = Set<AnyCancellable>()

    init(
        browserContext: SidebarBrowserContext,
        nowPlayingController: SumiNativeNowPlayingController,
        updaterService: SumiUpdaterService
    ) {
        self.downloadManager = browserContext.downloadManager
        self.extensionSurfaceStore = browserContext.extensionSurfaceStore
        self.nowPlayingController = nowPlayingController
        self.updaterService = updaterService

        forwardObjectWillChange(from: downloadManager)
        forwardObjectWillChange(from: extensionSurfaceStore)
        forwardObjectWillChange(from: nowPlayingController)
        forwardObjectWillChange(from: updaterService)
    }

    private func forwardObjectWillChange<T: ObservableObject>(from source: T) {
        source.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
