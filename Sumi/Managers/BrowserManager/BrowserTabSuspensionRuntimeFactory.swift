import Foundation
import SumiWebRuntime

@MainActor
enum BrowserTabSuspensionRuntimeFactory {
    static func ports(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        regularTabs: TabCollectionMembershipOwner,
        lazyRestore: TabLazyRestoreCoordinator,
        windowTabs: BrowserWindowTabContextOwner,
        splitManager: SplitViewManager,
        webView: TabSuspensionWebViewRuntime
    ) -> TabSuspensionRuntimePorts {
        TabSuspensionRuntimePorts(
            context: TabSuspensionContextRuntime(
                selectedTabIDs: {
                    selectedTabIDs(
                        windowRegistry: windowRegistry(),
                        windowTabs: windowTabs
                    )
                },
                visibleTabIDsByWindow: {
                    visibleTabIDsByWindow(
                        windowRegistry: windowRegistry(),
                        windowTabs: windowTabs,
                        splitManager: splitManager
                    )
                }
            ),
            webView: webView,
            catalog: TabSuspensionCatalogRuntime(
                allKnownTabs: {
                    allRuntimeTabs(
                        regularTabs: regularTabs,
                        windowRegistry: windowRegistry()
                    )
                },
                refreshLazyRestoreQueue: { context in
                    refreshLazyRestoreQueue(
                        context,
                        windowRegistry: windowRegistry(),
                        windowTabs: windowTabs,
                        lazyRestore: lazyRestore
                    )
                }
            )
        )
    }

    private static func selectedTabIDs(
        windowRegistry: WindowRegistry?,
        windowTabs: BrowserWindowTabContextOwner
    ) -> Set<UUID> {
        var selectedIDs = Set<UUID>()
        for windowState in windowRegistry.map({
            Array($0.windows.values)
        }) ?? [] {
            if let current = windowTabs.currentTab(for: windowState) {
                selectedIDs.insert(current.id)
            }
        }
        return selectedIDs
    }

    private static func visibleTabIDsByWindow(
        windowRegistry: WindowRegistry?,
        windowTabs: BrowserWindowTabContextOwner,
        splitManager: SplitViewManager
    ) -> [UUID: Set<UUID>] {
        var visible: [UUID: Set<UUID>] = [:]
        for windowState in windowRegistry.map({
            Array($0.windows.values)
        }) ?? [] {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: windowTabs.currentTab(for: windowState)?.id,
                splitTabIds: splitManager.visibleTabIds(for: windowState.id)
            )
            visible[windowState.id] = Set(tabIDs)
        }
        return visible
    }

    private static func refreshLazyRestoreQueue(
        _ context: TabSuspensionEvaluationContext,
        windowRegistry: WindowRegistry?,
        windowTabs: BrowserWindowTabContextOwner,
        lazyRestore: TabLazyRestoreCoordinator
    ) {
        guard let windowRegistry else { return }

        let activeWindowID = windowRegistry.activeWindow?.id
        let anchors = windowRegistry.allWindows
            .sorted { lhs, rhs in
                let lhsPriority = lhs.id == activeWindowID ? 0 : 1
                let rhsPriority = rhs.id == activeWindowID ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { windowState in
                lazyRestore.opportunisticRestoreAnchor(
                    in: windowState,
                    currentTab: windowTabs.currentTab(for: windowState)
                )
            }

        lazyRestore.refresh(
            anchors: anchors,
            selectedTabIDs: context.selectedTabIDs,
            visibleTabIDs: context.visibleTabIDs
        )
    }

    private static func allRuntimeTabs(
        regularTabs: TabCollectionMembershipOwner,
        windowRegistry: WindowRegistry?
    ) -> [Tab] {
        var seen = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seen.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        regularTabs.allTabs().forEach(append)
        (windowRegistry.map { Array($0.windows.values) } ?? [])
            .flatMap(\.ephemeralTabs)
            .forEach(append)
        return tabs
    }
}
