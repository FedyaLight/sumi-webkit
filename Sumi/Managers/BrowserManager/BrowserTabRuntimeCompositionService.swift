import Combine
import Foundation

@MainActor
enum BrowserTabRuntimeCompositionService {
    struct Dependencies {
        let attachTabSuspensionRuntime: @MainActor (TabSuspensionRuntime) -> Void
        let attachBackgroundMediaOptimizationRuntime: @MainActor (
            SumiBackgroundMediaOptimizationRuntime
        ) -> Void
        let tabStructuralChanges: AnyPublisher<Void, Never>
        let incrementTabStructuralRevision: @MainActor () -> Void
        let scheduleTabSuspensionReconcile: @MainActor (_ reason: String) -> Void
        let scheduleBackgroundMediaReconcile: @MainActor (_ reason: String) -> Void
        let webViewCoordinator: @MainActor () -> WebViewCoordinator?
        let memoryMode: @MainActor () -> SumiMemoryMode
        let customDeactivationDelay: @MainActor () -> TimeInterval
        let tabEnergySaverActive: @MainActor () -> Bool
        let backgroundMediaEnergySaverActive: @MainActor () -> Bool
        let allKnownTabs: @MainActor () -> [Tab]
        let selectedTabIDs: @MainActor () -> Set<UUID>
        let tabSuspensionVisibleTabIDsByWindow: @MainActor () -> [UUID: Set<UUID>]
        let backgroundMediaVisibleTabIDsByWindow: @MainActor () -> [UUID: Set<UUID>]
        let refreshLazyRestoreQueue: @MainActor (
            _ context: TabSuspensionEvaluationContext
        ) -> Void
        let notifyTabActivatedIfLoaded: @MainActor (_ newTab: Tab, _ previousTab: Tab?) -> Void
    }

    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        attach(dependencies: .live(browserManager: browserManager))
    }

    static func attach(dependencies: Dependencies) -> AnyCancellable {
        dependencies.attachTabSuspensionRuntime(
            tabSuspensionRuntime(dependencies: dependencies)
        )
        dependencies.attachBackgroundMediaOptimizationRuntime(
            backgroundMediaOptimizationRuntime(dependencies: dependencies)
        )
        return bindTabManagerStructuralUpdates(dependencies: dependencies)
    }

    static func tabSelectionRuntimeNotifications(
        for browserManager: BrowserManager
    ) -> BrowserTabSelectionOwner.RuntimeNotifications {
        runtimeNotifications(dependencies: .live(browserManager: browserManager))
    }

    static func runtimeNotifications(
        dependencies: Dependencies
    ) -> BrowserTabSelectionOwner.RuntimeNotifications {
        BrowserTabSelectionOwner.RuntimeNotifications(
            tabActivated: { newTab, previousTab in
                dependencies.notifyTabActivatedIfLoaded(newTab, previousTab)
            },
            tabSelectionChanged: { reason in
                scheduleTabRuntimeReconcile(
                    dependencies: dependencies,
                    reason: reason
                )
            }
        )
    }

    private static func bindTabManagerStructuralUpdates(
        dependencies: Dependencies
    ) -> AnyCancellable {
        dependencies.tabStructuralChanges
            .receive(on: RunLoop.main)
            .sink { _ in
                handleTabManagerStructuralChange(dependencies: dependencies)
            }
    }

    private static func handleTabManagerStructuralChange(dependencies: Dependencies) {
        dependencies.incrementTabStructuralRevision()
        scheduleTabRuntimeReconcile(
            dependencies: dependencies,
            reason: "tab-structure-changed"
        )
    }

    private static func scheduleTabRuntimeReconcile(
        dependencies: Dependencies,
        reason: String
    ) {
        dependencies.scheduleTabSuspensionReconcile(reason)
        dependencies.scheduleBackgroundMediaReconcile(reason)
    }

    private static func backgroundMediaOptimizationRuntime(
        dependencies: Dependencies
    ) -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            webViewCoordinator: {
                dependencies.webViewCoordinator()
            },
            energySaverActive: {
                dependencies.backgroundMediaEnergySaverActive()
            },
            allKnownTabs: {
                dependencies.allKnownTabs()
            },
            visibleTabIDsByWindow: {
                dependencies.backgroundMediaVisibleTabIDsByWindow()
            }
        )
    }

    private static func tabSuspensionRuntime(
        dependencies: Dependencies
    ) -> TabSuspensionRuntime {
        TabSuspensionRuntime(
            webViewCoordinator: {
                dependencies.webViewCoordinator()
            },
            memoryMode: {
                dependencies.memoryMode()
            },
            customDeactivationDelay: {
                dependencies.customDeactivationDelay()
            },
            energySaverActive: {
                dependencies.tabEnergySaverActive()
            },
            allKnownTabs: {
                dependencies.allKnownTabs()
            },
            selectedTabIDs: {
                dependencies.selectedTabIDs()
            },
            visibleTabIDsByWindow: {
                dependencies.tabSuspensionVisibleTabIDsByWindow()
            },
            refreshLazyRestoreQueue: { context in
                dependencies.refreshLazyRestoreQueue(context)
            }
        )
    }
}

@MainActor
extension BrowserTabRuntimeCompositionService.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            attachTabSuspensionRuntime: { [weak browserManager] runtime in
                browserManager?.tabSuspensionService.attach(runtime: runtime)
            },
            attachBackgroundMediaOptimizationRuntime: { [weak browserManager] runtime in
                browserManager?.backgroundMediaOptimizationService.attach(runtime: runtime)
            },
            tabStructuralChanges: browserManager.tabManager.structuralChanges.eraseToAnyPublisher(),
            incrementTabStructuralRevision: { [weak browserManager] in
                browserManager?.tabStructuralRevision &+= 1
            },
            scheduleTabSuspensionReconcile: { [weak browserManager] reason in
                browserManager?.tabSuspensionService.scheduleProactiveTimerReconcile(
                    reason: reason
                )
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: reason
                )
            },
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            memoryMode: { [weak browserManager] in
                browserManager?.sumiSettings?.memoryMode ?? .balanced
            },
            customDeactivationDelay: { [weak browserManager] in
                browserManager?.sumiSettings?.memorySaverCustomDeactivationDelay
                    ?? SumiMemorySaverCustomDelay.defaultDelay
            },
            tabEnergySaverActive: { [weak browserManager] in
                browserManager?.sumiSettings?
                    .energySaverApplies(.deactivateInactiveTabsSooner) ?? false
            },
            backgroundMediaEnergySaverActive: { [weak browserManager] in
                browserManager?.sumiSettings?.energySaverActivation.isActive ?? false
            },
            allKnownTabs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allRuntimeTabs(for: browserManager)
            },
            selectedTabIDs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return tabSuspensionSelectedTabIDs(for: browserManager)
            },
            tabSuspensionVisibleTabIDsByWindow: { [weak browserManager] in
                guard let browserManager else { return [:] }
                return tabSuspensionVisibleTabIDsByWindow(for: browserManager)
            },
            backgroundMediaVisibleTabIDsByWindow: { [weak browserManager] in
                guard let browserManager else { return [:] }
                return backgroundMediaVisibleTabIDsByWindow(for: browserManager)
            },
            refreshLazyRestoreQueue: { [weak browserManager] context in
                guard let browserManager else { return }
                refreshTabSuspensionLazyRestoreQueue(context, for: browserManager)
            },
            notifyTabActivatedIfLoaded: { [weak browserManager] newTab, previousTab in
                browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: newTab,
                    previous: previousTab
                )
            }
        )
    }

    private static func backgroundMediaVisibleTabIDsByWindow(
        for browserManager: BrowserManager
    ) -> [UUID: Set<UUID>] {
        guard let windowRegistry = browserManager.windowRegistry else { return [:] }

        var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
        for windowState in windowRegistry.windows.values where windowState.windowVisibilityState.isEffectivelyVisible {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: browserManager.currentTab(for: windowState)?.id,
                splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
            )
            visibleTabIDsByWindow[windowState.id] = Set(tabIDs)
        }
        return visibleTabIDsByWindow
    }

    private static func tabSuspensionSelectedTabIDs(
        for browserManager: BrowserManager
    ) -> Set<UUID> {
        var selectedIDs = Set<UUID>()
        for windowState in browserManager.windowRegistry?.windows.values.map({ $0 }) ?? [] {
            if let current = browserManager.currentTab(for: windowState) {
                selectedIDs.insert(current.id)
            }
        }
        return selectedIDs
    }

    private static func tabSuspensionVisibleTabIDsByWindow(
        for browserManager: BrowserManager
    ) -> [UUID: Set<UUID>] {
        var visible: [UUID: Set<UUID>] = [:]
        for windowState in browserManager.windowRegistry?.windows.values.map({ $0 }) ?? [] {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: browserManager.currentTab(for: windowState)?.id,
                splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
            )
            visible[windowState.id] = Set(tabIDs)
        }
        return visible
    }

    private static func refreshTabSuspensionLazyRestoreQueue(
        _ context: TabSuspensionEvaluationContext,
        for browserManager: BrowserManager
    ) {
        guard let windowRegistry = browserManager.windowRegistry else { return }

        let activeWindowId = windowRegistry.activeWindow?.id
        let anchors = windowRegistry.allWindows
            .sorted { lhs, rhs in
                let lhsPriority = lhs.id == activeWindowId ? 0 : 1
                let rhsPriority = rhs.id == activeWindowId ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { windowState in
                let currentTab = browserManager.currentTab(for: windowState)
                return browserManager.tabManager.opportunisticRestoreAnchor(
                    in: windowState,
                    currentTab: currentTab
                )
            }

        browserManager.tabManager.lazyRestoreCoordinator.refresh(
            anchors: anchors,
            selectedTabIDs: context.selectedTabIDs,
            visibleTabIDs: context.visibleTabIDs
        )
    }

    private static func allRuntimeTabs(
        for browserManager: BrowserManager
    ) -> [Tab] {
        var seen = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seen.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        browserManager.tabManager.allTabs().forEach(append)
        (browserManager.windowRegistry?.windows.values.map { $0 } ?? [])
            .flatMap(\.ephemeralTabs)
            .forEach(append)
        return tabs
    }
}
