import Combine
import Foundation
import SumiWebRuntime
import WebKit

@MainActor
enum BrowserTabRuntimeCompositionService {
    struct Dependencies {
        let installTabSuspensionRuntime: @MainActor () -> Void
        let attachBackgroundMediaOptimizationRuntime: @MainActor (
            SumiBackgroundMediaOptimizationRuntime
        ) -> Void
        let tabStructuralChanges: AnyPublisher<Void, Never>
        let incrementTabStructuralRevision: @MainActor () -> Void
        let scheduleTabSuspensionReconcile: @MainActor (_ reason: String) -> Void
        let scheduleBackgroundMediaReconcile: @MainActor (_ reason: String) -> Void
        let webViewRuntimeAvailable: @MainActor () -> Bool
        let trackedWebViewEntries: @MainActor (Tab) -> [
            (windowID: UUID, webView: WKWebView)
        ]
        let backgroundMediaEnergySaverActive: @MainActor () -> Bool
        let allKnownTabs: @MainActor () -> [Tab]
        let backgroundMediaVisibleTabIDsByWindow: @MainActor () -> [UUID: Set<UUID>]
        let notifyTabActivatedIfLoaded: @MainActor (_ newTab: Tab, _ previousTab: Tab?) -> Void
    }

    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        attach(dependencies: .live(browserManager: browserManager))
    }

    static func attach(dependencies: Dependencies) -> AnyCancellable {
        dependencies.installTabSuspensionRuntime()
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
            webViewRuntimeAvailable: {
                dependencies.webViewRuntimeAvailable()
            },
            liveWebViewEntries: { tab in
                dependencies.trackedWebViewEntries(tab).map {
                    (windowID: Optional($0.windowID), webView: $0.webView)
                }
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

}

@MainActor
extension BrowserTabRuntimeCompositionService.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        let tabSuspensionController = browserManager.tabSuspensionController
        let shellRuntime = browserManager.shellRuntime
        let suspensionWebViewOwnership = browserManager.webViewOwnershipQuery
        let regularTabs = browserManager.tabManager.tabCollectionMembershipOwner
        let lazyRestore = browserManager.tabManager.lazyRestoreCoordinator
        let windowTabs = browserManager.windowSessionBundle.tabContextOwner
        let splitManager = browserManager.splitManager

        return Self(
            installTabSuspensionRuntime: {
                tabSuspensionController.install(
                    runtime: BrowserTabSuspensionRuntimeFactory.ports(
                        windowRegistry: { shellRuntime.windowRegistry },
                        regularTabs: regularTabs,
                        lazyRestore: lazyRestore,
                        windowTabs: windowTabs,
                        splitManager: splitManager,
                        webView: TabSuspensionWebViewRuntime(
                            isAvailable: {
                                shellRuntime.webViewCoordinator != nil
                            },
                            liveWebViews: { tab in
                                suspensionWebViewOwnership.suspensionLiveWebViews(for: tab)
                            },
                            suspendWebViews: { tab, reason in
                                shellRuntime.webViewCoordinator?.lifecycleService
                                    .suspendWebViews(for: tab, reason: reason) ?? false
                            },
                            isProtectedFromCompositorMutation: { webView in
                                shellRuntime.webViewCoordinator?.protectionRuntime
                                    .isProtected(webView) ?? false
                            }
                        )
                    )
                )
            },
            attachBackgroundMediaOptimizationRuntime: { [weak browserManager] runtime in
                browserManager?.backgroundMediaOptimizationService.attach(runtime: runtime)
            },
            tabStructuralChanges: browserManager.tabManager.tabStructureEventBus.structureChangedPublisher,
            incrementTabStructuralRevision: { [weak browserManager] in
                browserManager?.tabStructuralRevision &+= 1
            },
            scheduleTabSuspensionReconcile: { reason in
                tabSuspensionController.scheduleReconciliation(reason: reason)
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: reason
                )
            },
            webViewRuntimeAvailable: { [weak browserManager] in
                browserManager?.webViewCoordinator != nil
            },
            trackedWebViewEntries: { [weak browserManager] tab in
                guard let browserManager else { return [] }
                return browserManager.webViewOwnershipQuery.windowIDs(for: tab.id)
                    .compactMap { windowID in
                        browserManager.webViewOwnershipQuery.webView(
                            for: tab.id,
                            in: windowID
                        ).map { (windowID: windowID, webView: $0) }
                    }
            },
            backgroundMediaEnergySaverActive: { [weak browserManager] in
                browserManager?.sumiSettings?.energySaverActivation.isActive ?? false
            },
            allKnownTabs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allRuntimeTabs(for: browserManager)
            },
            backgroundMediaVisibleTabIDsByWindow: { [weak browserManager] in
                guard let browserManager else { return [:] }
                return backgroundMediaVisibleTabIDsByWindow(for: browserManager)
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
                currentTabId: browserManager.windowSessionBundle.tabContextOwner.currentTab(for: windowState)?.id,
                splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
            )
            visibleTabIDsByWindow[windowState.id] = Set(tabIDs)
        }
        return visibleTabIDsByWindow
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

        browserManager.tabManager.tabCollectionMembershipOwner.allTabs().forEach(append)
        (browserManager.windowRegistry.map { Array($0.windows.values) } ?? [])
            .flatMap(\.ephemeralTabs)
            .forEach(append)
        return tabs
    }
}
