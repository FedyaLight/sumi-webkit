import Foundation

enum StartupNormalTabMaterializationPolicy {
    static func shouldDefer(
        appliedProtectionLevel: SumiProtectionLevel,
        hasFinishedStartupProtectionRestore: Bool
    ) -> Bool {
        appliedProtectionLevel != .off && !hasFinishedStartupProtectionRestore
    }
}

@MainActor
final class BrowserStartupProtectionRuntime {
    struct Dependencies {
        let appliedProtectionLevel: () -> SumiProtectionLevel
        let restoreAppliedProtectionLevelForStartup: () async throws -> Void
        let tab: (UUID) -> Tab?
        let allWindows: () -> [BrowserWindowState]
        let prepareBackgroundTabIfNeeded: (Tab) -> Void
        let schedulePrepareVisibleWebViews: (BrowserWindowState) -> Void
        let refreshCompositor: (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies
    private var startupProtectionRestoreTask: Task<Void, Never>?
    private(set) var hasFinishedProtectionRestore = false
    private var deferredBackgroundTabIds: Set<UUID> = []

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var shouldDeferNormalTabMaterializationDuringStartup: Bool {
        StartupNormalTabMaterializationPolicy.shouldDefer(
            appliedProtectionLevel: dependencies.appliedProtectionLevel(),
            hasFinishedStartupProtectionRestore: hasFinishedProtectionRestore
        )
    }

    func beginProtectionRestoreForStartupIfNeeded() {
        guard !hasFinishedProtectionRestore else { return }
        guard startupProtectionRestoreTask == nil else { return }
        guard !RuntimeDiagnostics.isRunningTests else {
            finishStartupProtectionRestore()
            return
        }

        startupProtectionRestoreTask = Task { @MainActor [weak self] in
            await self?.restoreProtectionForStartupIfNeeded()
        }
    }

    func canMaterializeWebViewDuringStartup(_ tab: Tab) -> Bool {
        if ExtensionUtils.isExtensionOwnedURL(tab.url) || tab.webExtensionContextOverride != nil {
            return true
        }
        return !tab.requiresPrimaryWebView || !shouldDeferNormalTabMaterializationDuringStartup
    }

    func deferBackgroundTabUntilStartupReady(_ tab: Tab) {
        deferredBackgroundTabIds.insert(tab.id)
    }

    func cancelProtectionRestoreTask() {
        startupProtectionRestoreTask?.cancel()
        startupProtectionRestoreTask = nil
    }

    private func restoreProtectionForStartupIfNeeded() async {
        let startupTrace = StartupPerformanceTrace.protectionRestoreStarted()
        defer {
            StartupPerformanceTrace.protectionRestoreFinished(startupTrace)
            finishStartupProtectionRestore()
        }

        do {
            try await dependencies.restoreAppliedProtectionLevelForStartup()
        } catch {
            RuntimeDiagnostics.debug(
                "Protection startup restore failed: \(error.localizedDescription)",
                category: "Protection"
            )
        }
    }

    func finishStartupProtectionRestore() {
        guard !hasFinishedProtectionRestore else { return }
        hasFinishedProtectionRestore = true

        let deferredBackgroundTabs = deferredBackgroundTabIds
        deferredBackgroundTabIds.removeAll()
        for tabId in deferredBackgroundTabs {
            guard let tab = dependencies.tab(tabId) else { continue }
            dependencies.prepareBackgroundTabIfNeeded(tab)
        }

        for windowState in dependencies.allWindows() {
            dependencies.schedulePrepareVisibleWebViews(windowState)
            dependencies.refreshCompositor(windowState)
        }

#if DEBUG
        Task { @MainActor in
            await Task.yield()
            StartupPerformanceTrace.postStartupIdlePoint()
        }
#endif
    }

#if DEBUG
    func drainProtectionRestoreTaskForTests(cancel: Bool = false) async {
        if cancel {
            startupProtectionRestoreTask?.cancel()
        }
        if let startupProtectionRestoreTask {
            await startupProtectionRestoreTask.value
            self.startupProtectionRestoreTask = nil
        }
    }
#endif
}

extension BrowserStartupProtectionRuntime.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            appliedProtectionLevel: { [weak browserManager] in
                browserManager?.protectionCoordinator.settings.appliedLevel ?? .off
            },
            restoreAppliedProtectionLevelForStartup: { [weak browserManager] in
                guard let browserManager else { return }
                _ = try await browserManager.protectionCoordinator.restoreAppliedLevelForStartup()
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            prepareBackgroundTabIfNeeded: { [weak browserManager] tab in
                browserManager?.prepareBackgroundTabAfterStartupProtectionRestore(tab)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            }
        )
    }
}
