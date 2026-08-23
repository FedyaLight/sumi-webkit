import Foundation
import SumiWebRuntime

@MainActor
enum BrowserTabSuspensionRuntimeFactory {
    static func ports(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        regularTabs: TabCollectionMembershipOwner,
        windowTabs: BrowserWindowTabContext,
        splitQuery: WindowSplitQuery,
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
                        splitQuery: splitQuery
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
                }
            )
        )
    }

    private static func selectedTabIDs(
        windowRegistry: WindowRegistry?,
        windowTabs: BrowserWindowTabContext
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
        windowTabs: BrowserWindowTabContext,
        splitQuery: WindowSplitQuery
    ) -> [UUID: Set<UUID>] {
        var visible: [UUID: Set<UUID>] = [:]
        for windowState in windowRegistry.map({
            Array($0.windows.values)
        }) ?? [] {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: windowTabs.currentTab(for: windowState)?.id,
                splitTabIds: splitQuery.visibleTabIDs(in: windowState.id)
            )
            visible[windowState.id] = Set(tabIDs)
        }
        return visible
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
