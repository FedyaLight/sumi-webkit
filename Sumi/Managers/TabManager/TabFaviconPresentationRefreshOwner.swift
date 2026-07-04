import Foundation

@MainActor
final class TabFaviconPresentationRefreshOwner {
    struct Dependencies {
        let notificationCenter: NotificationCenter
        let debounceNanoseconds: UInt64
        let tabsNeedingRefresh: () -> [Tab]
        let requestStructuralPublish: () -> Void
    }

    private let dependencies: Dependencies
    private var faviconCacheObserver: NSObjectProtocol?
    private var pendingRefreshTask: Task<Void, Never>?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func startObserving() {
        guard faviconCacheObserver == nil else { return }
        faviconCacheObserver = dependencies.notificationCenter.addObserver(
            forName: .faviconCacheUpdated,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    func stop() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        if let faviconCacheObserver {
            dependencies.notificationCenter.removeObserver(faviconCacheObserver)
            self.faviconCacheObserver = nil
        }
    }

    private func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        let debounceNanoseconds = dependencies.debounceNanoseconds
        pendingRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            self?.pendingRefreshTask = nil
            self?.refreshCachedFaviconPresentation()
        }
    }

    private func refreshCachedFaviconPresentation() {
        for tab in dependencies.tabsNeedingRefresh() where tab.faviconIsTemplateGlobePlaceholder {
            _ = tab.applyCachedFaviconOrPlaceholder(for: tab.url)
        }
        dependencies.requestStructuralPublish()
    }
}

extension TabFaviconPresentationRefreshOwner.Dependencies {
    /// The non-closure `notificationCenter` / `debounceNanoseconds` stay owned by
    /// `TabManager` (the debounce constant is a `TabManager` private static), so they are
    /// passed in explicitly while the collaborator closures are wired here.
    @MainActor
    static func live(
        tabManager: TabManager,
        notificationCenter: NotificationCenter,
        debounceNanoseconds: UInt64
    ) -> Self {
        Self(
            notificationCenter: notificationCenter,
            debounceNanoseconds: debounceNanoseconds,
            tabsNeedingRefresh: { [weak tabManager] in
                guard let tabManager else { return [] }
                return tabManager.regularTabCollectionStateOwner.allTabs()
                    + tabManager.transientTabRegistryOwner.transientShortcutTabs
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.requestStructuralPublish()
            }
        )
    }
}
