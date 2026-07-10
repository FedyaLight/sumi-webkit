import Foundation

@MainActor
final class TabFaviconPresentationRefreshOwner {
    private let notificationCenter: NotificationCenter
    private let debounceNanoseconds: UInt64
    private let tabsNeedingRefresh: () -> [Tab]

    private var faviconCacheObserver: NSObjectProtocol?
    private var pendingRefreshTask: Task<Void, Never>?

    init(
        notificationCenter: NotificationCenter,
        debounceNanoseconds: UInt64,
        tabsNeedingRefresh: @escaping () -> [Tab]
    ) {
        self.notificationCenter = notificationCenter
        self.debounceNanoseconds = debounceNanoseconds
        self.tabsNeedingRefresh = tabsNeedingRefresh
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func startObserving() {
        guard faviconCacheObserver == nil else { return }
        faviconCacheObserver = notificationCenter.addObserver(
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
            notificationCenter.removeObserver(faviconCacheObserver)
            self.faviconCacheObserver = nil
        }
    }

    private func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        let debounceNanoseconds = debounceNanoseconds
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
        for tab in tabsNeedingRefresh() where tab.faviconIsTemplateGlobePlaceholder {
            _ = tab.applyCachedFaviconOrPlaceholder(for: tab.url)
        }
    }
}
