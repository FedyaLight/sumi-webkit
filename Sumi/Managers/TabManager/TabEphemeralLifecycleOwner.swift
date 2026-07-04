import Foundation

@MainActor
final class TabEphemeralLifecycleOwner {
    struct Dependencies {
        let prepareTabForRuntime: @MainActor (Tab) -> Void
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let visitedLinkStore: @MainActor () -> any BrowserVisitedLinkStoreManaging
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func createEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let nextIndex = windowState.ephemeralTabs.map(\.index).max().map { $0 + 1 } ?? 0
        let newTab = Tab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: nextIndex,
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            visitedLinkStore: dependencies.visitedLinkStore()
        )
        newTab.profileId = profile.id
        dependencies.prepareTabForRuntime(newTab)

        windowState.ephemeralTabs.append(newTab)
        windowState.currentTabId = newTab.id

        RuntimeDiagnostics.emit("🔒 [TabEphemeralLifecycleOwner] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")

        return newTab
    }
}

extension TabEphemeralLifecycleOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            prepareTabForRuntime: { [weak tabManager] tab in
                tabManager?.runtimePreparationOwner.prepare(tab)
            },
            faviconService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconService
            },
            faviconImageService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconImageService
            },
            visitedLinkStore: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.visitedLinkStore
            }
        )
    }
}
