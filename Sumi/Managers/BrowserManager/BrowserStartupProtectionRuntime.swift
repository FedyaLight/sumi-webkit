import Foundation
import SumiDomain

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
    private let appliedProtectionLevelAction: () -> SumiProtectionLevel
    private let restoreAppliedProtectionLevelForStartupAction: () async throws -> Void
    private let tabAction: (UUID) -> Tab?
    private let allWindowsAction: () -> [BrowserWindowState]
    private let prepareBackgroundTabIfNeededAction: (Tab) -> Void
    private let schedulePrepareVisibleWebViewsAction: (BrowserWindowState) -> Void
    private let refreshCompositorAction: (BrowserWindowState) -> Void

    private var startupProtectionRestoreTask: Task<Void, Never>?
    private(set) var hasFinishedProtectionRestore = false
    private var deferredBackgroundTabIds: Set<UUID> = []

    init(
        appliedProtectionLevel: @escaping () -> SumiProtectionLevel,
        restoreAppliedProtectionLevelForStartup: @escaping () async throws -> Void,
        tab: @escaping (UUID) -> Tab?,
        allWindows: @escaping () -> [BrowserWindowState],
        prepareBackgroundTabIfNeeded: @escaping (Tab) -> Void,
        schedulePrepareVisibleWebViews: @escaping (BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void
    ) {
        self.appliedProtectionLevelAction = appliedProtectionLevel
        self.restoreAppliedProtectionLevelForStartupAction = restoreAppliedProtectionLevelForStartup
        self.tabAction = tab
        self.allWindowsAction = allWindows
        self.prepareBackgroundTabIfNeededAction = prepareBackgroundTabIfNeeded
        self.schedulePrepareVisibleWebViewsAction = schedulePrepareVisibleWebViews
        self.refreshCompositorAction = refreshCompositor
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            appliedProtectionLevel: { [weak browserManager] in
                browserManager?.protectionCoordinator.settings.appliedLevel ?? .off
            },
            restoreAppliedProtectionLevelForStartup: { [weak browserManager] in
                guard let browserManager else { return }
                _ = try await browserManager.protectionCoordinator.restoreAppliedLevelForStartup()
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            prepareBackgroundTabIfNeeded: { [weak browserManager] tab in
                browserManager?.tabLifecycleService.opening.prepareBackgroundTabIfNeeded(tab, in: nil)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.visualMutationOwner.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.visualMutationOwner.refreshCompositor(for: windowState)
            }
        )
    }

    var shouldDeferNormalTabMaterializationDuringStartup: Bool {
        StartupNormalTabMaterializationPolicy.shouldDefer(
            appliedProtectionLevel: appliedProtectionLevelAction(),
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
            try await restoreAppliedProtectionLevelForStartupAction()
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
            guard let tab = tabAction(tabId) else { continue }
            prepareBackgroundTabIfNeededAction(tab)
        }

        for windowState in allWindowsAction() {
            schedulePrepareVisibleWebViewsAction(windowState)
            refreshCompositorAction(windowState)
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
