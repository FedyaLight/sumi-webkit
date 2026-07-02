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
