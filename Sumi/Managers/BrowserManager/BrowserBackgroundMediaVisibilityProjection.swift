import Foundation
import SumiWebRuntime

@MainActor
final class BrowserBackgroundMediaVisibilityProjection {
    private let windows: WindowRegistry
    private let windowTabs: BrowserWindowTabContext
    private let splitQuery: WindowSplitQuery

    init(
        windows: WindowRegistry,
        windowTabs: BrowserWindowTabContext,
        splitQuery: WindowSplitQuery
    ) {
        self.windows = windows
        self.windowTabs = windowTabs
        self.splitQuery = splitQuery
    }

    func visibleTabIDsByWindow() -> [UUID: Set<UUID>] {
        var result: [UUID: Set<UUID>] = [:]
        for window in windows.windows.values
            where window.presentationState.visibility.isEffectivelyVisible {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: windowTabs.currentTab(for: window)?.id,
                splitTabIds: splitQuery.visibleTabIDs(in: window.id)
            )
            result[window.id] = Set(tabIDs)
        }
        return result
    }
}
