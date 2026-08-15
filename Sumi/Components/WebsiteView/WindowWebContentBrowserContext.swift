import Foundation

@MainActor
protocol WindowWebContentBrowserContext: AnyObject {
    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func tab(for tabId: UUID, in windowState: BrowserWindowState) -> Tab?
    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    )
    func repairFailedPage(
        _ tabID: UUID,
        in windowID: UUID,
        useNativeSnapshot: Bool
    )
}

extension WindowWebContentBrowserContext {
    func repairFailedPage(
        _: UUID,
        in _: UUID,
        useNativeSnapshot _: Bool
    ) {}
}

@MainActor
final class BrowserManagerWindowWebContentContext: WindowWebContentBrowserContext {
    private let windowTabs: BrowserWindowTabContext
    private let membership: TabCollectionMembershipOwner
    private let windowVisuals: BrowserWindowVisualCoordinator
    private let repairFailure: @MainActor (UUID, UUID, Bool) -> Void

    init(
        windowTabs: BrowserWindowTabContext,
        membership: TabCollectionMembershipOwner,
        windowVisuals: BrowserWindowVisualCoordinator,
        repairFailure: @escaping @MainActor (UUID, UUID, Bool) -> Void
    ) {
        self.windowTabs = windowTabs
        self.membership = membership
        self.windowVisuals = windowVisuals
        self.repairFailure = repairFailure
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        windowTabs.currentTab(for: windowState)
    }

    func tab(for tabId: UUID, in windowState: BrowserWindowState) -> Tab? {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == tabId }
        }
        return membership.tab(for: tabId)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        windowVisuals.enqueueWindowMutationDuringHistorySwipe(kind, for: windowState)
    }

    func repairFailedPage(
        _ tabID: UUID,
        in windowID: UUID,
        useNativeSnapshot: Bool
    ) {
        repairFailure(tabID, windowID, useNativeSnapshot)
    }
}
