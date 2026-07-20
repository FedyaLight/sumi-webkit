import Foundation

@MainActor
final class BrowserRegularTabCloseTransaction {
    private let tabClosure: TabClosureService
    private let fallbackPlanner: BrowserTabCloseFallbackPlanner
    private let presentation: BrowserRegularTabClosePresentation
    private let residences: BrowserTabResidenceAuthority

    init(
        tabClosure: TabClosureService,
        fallbackPlanner: BrowserTabCloseFallbackPlanner,
        presentation: BrowserRegularTabClosePresentation,
        residences: BrowserTabResidenceAuthority
    ) {
        self.tabClosure = tabClosure
        self.fallbackPlanner = fallbackPlanner
        self.presentation = presentation
        self.residences = residences
    }

    func close(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        presentNotification: Bool = true
    ) -> Bool {
        guard let admission = residences.admitRegularRemoval(
            of: tab,
            from: windowState
        ) else {
            return false
        }
        let wasCurrent = windowState.currentTabId == admission.tab.id
        let fallback = wasCurrent
            ? fallbackPlanner.fallbackAfterClosingRegularTab(
                admission.tab,
                in: windowState
            )
            : nil
        guard residences.validates(admission),
              tabClosure.removeExactRegularTab(
                  admission.tab,
                  in: admission.spaceID,
                  presentNotification: presentNotification
              )
        else {
            return false
        }
        if let fallback {
            presentation.selectFallback(fallback, in: windowState)
        }

        if wasCurrent {
            if fallback == nil {
                presentation.showEmptyState(in: windowState)
            }
        } else {
            presentation.persist(windowState)
        }
        return true
    }
}
